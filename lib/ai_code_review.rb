# frozen_string_literal: true

require 'json'
require_relative 'ai_code_review/analyzer'
require_relative 'ai_code_review/ai_client'
require_relative 'ai_code_review/reporter'

module AiCodeReview
  class << self
    # 主入口方法
    # full_review: true 表示评审文件全文，false 表示仅评审 diff 改动行
    def start(path = '.', repo: nil, pr_number: nil, dry_run: false, platform: 'github', skip_ai: false, full_review: false)
      project_root = File.expand_path(path)

      Dir.chdir(project_root) do
        puts "🚀 开始代码评审..."
        puts "📂 项目根目录: #{project_root}"
        puts full_review ? "🔍 模式: 全量评审 (Full Review)" : "🔍 模式: 增量评审 (Diff Review)"

        # 1. 获取 Git 改动的文件及行号
        changes = get_diff_changes('.', full: full_review)
        if changes.empty?
          puts "✅ 没有检测到 Ruby 文件的改动，跳过。"
          return
        end

        # 2. 运行静态分析 (RuboCop)
        puts " inspectors 正在运行静态分析..."
        analyzer = Analyzer.new('.')
        static_results = analyzer.run

        # 3. 准备 AI 客户端
        ai_client = AiClient.new unless skip_ai

        # 4. 遍历改动文件进行评审
        all_suggestions = []
        puts "🤖 正在为 #{changes.size} 个改动文件生成建议..."

        changes.each do |file_path, changed_lines|
          full_file_path = File.expand_path(file_path, project_root)
          next unless File.exist?(full_file_path)

          file_content = File.read(full_file_path)
          file_issues = static_results.select { |issue| issue[:file] == file_path }

          if skip_ai
            puts "⏭️  跳过 AI 评审: #{file_path}"
            next
          end

          # 调用 AI 获取建议
          suggestion = ai_client.get_review(
            file_path: file_path,
            content: file_content,
            lines: changed_lines,
            static_issues: file_issues,
            is_full: full_review
          )

          if suggestion
            all_suggestions << {
              file: file_path,
              suggestion: suggestion,
              # 如果是全量评审，评论默认挂在第一行，或者是该文件第一个改动行
              line: full_review ? (changed_lines.is_a?(Array) ? changed_lines.first : 1) : changed_lines.first
            }
          end
        end

        # 5. 发布结果
        if dry_run
          puts "\n🍎 [Dry Run] 评审建议如下:"
          all_suggestions.each { |s| puts "--- #{s[:file]}:#{s[:line]} ---\n#{s[:suggestion]}" }
        else
          reporter = Reporter.new(platform: platform, repo: repo, pr_number: pr_number)
          reporter.publish(all_suggestions)
        end
      end
    rescue StandardError => e
      puts "💥 程序运行出错:"
      puts "信息: #{e.message}"
      # puts e.backtrace # 调试时可开启
    end

    private

    # 获取 Diff 改动
    # @param path [String] 路径
    # @param full [Boolean] 是否为全量模式
    # @return [Hash] { "file_path" => [line_numbers] } 或 { "file_path" => :all }
    def get_diff_changes(path, full: false)
      changes = {}

      # 自动识别基础分支：GitHub Actions 环境用 origin/main，本地通常用 HEAD~1
      base = ENV['GITHUB_BASE_REF'] ? "origin/#{ENV['GITHUB_BASE_REF']}" : "HEAD~1"

      # 仅获取已存在的、被修改的 Ruby 文件名
      files = `git -C #{path} diff #{base}...HEAD --name-only --diff-filter=d`.split("\n")
      ruby_files = files.select { |f| f.end_with?('.rb') }

      ruby_files.each do |file|
        if full
          # 全量模式：标记该文件需要全部评审
          # 我们依然需要拿到它的有效行号，通常用 git 拿到的所有行
          line_count = `wc -l < #{file}`.to_i
          changes[file] = (1..line_count).to_a
        else
          # 增量模式：精准解析 diff 中的新增/修改行 (hunks)
          lines = []
          diff_hunks = `git -C #{path} diff #{base}...HEAD --unified=0 #{file}`
          diff_hunks.each_line do |line|
            # 匹配 @@ -1,1 +2,3 @@ 这种格式，提取 + 号后面的新行起始位置和数量
            if (match = line.match(/@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/))
              start_line = match[1].to_i
              count = (match[2] || 1).to_i
              count.times { |i| lines << (start_line + i) }
            end
          end
          changes[file] = lines unless lines.empty?
        end
      end
      changes
    end
  end
end
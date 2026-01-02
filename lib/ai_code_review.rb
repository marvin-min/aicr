# frozen_string_literal: true

require 'json'
require_relative 'ai_code_review/analyzer'
require_relative 'ai_code_review/ai_client'
require_relative 'ai_code_review/reporter'

module AiCodeReview
  class << self
    def start(path = '.', repo: nil, pr_number: nil, dry_run: false, platform: 'github', skip_ai: false, full_review: false)
      project_root = File.expand_path(path)

      Dir.chdir(project_root) do
        puts "🚀 开始代码评审..."
        puts "📂 项目根目录: #{project_root}"
        puts full_review ? "🔍 模式: 全量评审 (Full Review)" : "🔍 模式: 增量评审 (Diff Review)"

        # 1. 获取 Git 改动
        changes = get_diff_changes(full: full_review)
        if changes.empty?
          puts "✅ 没有检测到 Ruby 文件的改动，跳过。"
          return
        end

        # 2. 静态分析
        puts "🔍 正在运行静态分析 (RuboCop)..."
        analyzer = Analyzer.new('.')
        static_results = analyzer.run

        # 3. 初始化 AI 客户端
        ai_client = AiClient.new unless skip_ai

        # 4. 遍历文件评审
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

          suggestion = ai_client.get_review(
            file_path: file_path,
            content: file_content,
            lines: changed_lines,
            static_issues: file_issues,
            is_full: full_review
          )

          if suggestion
            all_suggestions << {
              file_path: file_path, # 改为 file_path 适配 Reporter
              suggestion: suggestion,
              line: (changed_lines.is_a?(Array) ? changed_lines.first : 1)
            }
          end
        end

        # 5. 发布结果
        if dry_run || all_suggestions.empty?
          puts "\n🍎 [预览模式] 评审建议如下:"
          if all_suggestions.empty?
            puts "✅ 所有代码均已通过评审 (PASS)。"
          else
            all_suggestions.each { |s| puts "--- #{s[:file]}:#{s[:line]} ---\n#{s[:suggestion]}\n" }
          end
        else
          reporter = Reporter.for(platform, repo, pr_number)
          reporter.publish_review(all_suggestions)
        end
      end
    rescue StandardError => e
      puts "💥 程序运行出错:"
      puts "信息: #{e.message}"
      puts "--- 调试信息 ---"
      # 这行会告诉你具体是哪一个文件的哪一行崩了
      puts e.backtrace.reject { |line| line.include?('gems') }.first(5)    end
    private

    def get_diff_changes(full: false)
      changes = {}
      base = ENV['GITHUB_BASE_REF'] ? "origin/#{ENV['GITHUB_BASE_REF']}" : "HEAD~1"

      files = `git diff #{base}...HEAD --name-only --diff-filter=d`.split("\n")
      ruby_files = files.select { |f| f.end_with?('.rb') }

      ruby_files.each do |file|
        if full
          line_count = File.foreach(file).count rescue 1
          changes[file] = (1..line_count).to_a
        else
          lines = []
          diff_hunks = `git diff #{base}...HEAD --unified=0 #{file}`
          diff_hunks.each_line do |line|
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
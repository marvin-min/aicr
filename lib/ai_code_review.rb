# frozen_string_literal: true

require 'json'
require_relative 'ai_code_review/ai_client'
require_relative 'ai_code_review/reporter'

module AiCodeReview
  class << self
    # 核心入口：专注于 Ruby 逻辑的深度评审
    def start(path = '.', repo: nil, pr_number: nil, dry_run: false, platform: 'github', skip_ai: false, full_review: false)
      project_root = File.expand_path(path)

      Dir.chdir(project_root) do
        puts "🚀 开始专业级 Ruby 代码逻辑评审..."
        puts "📂 项目根目录: #{project_root}"
        puts "🔍 模式: #{full_review ? '全量评审 (Full)' : '增量评审 (Diff)'}"

        # 1. 获取 Git 改动（自动过滤非 Ruby 文件）
        changes = get_ruby_diff_changes(full: full_review)

        if changes.empty?
          puts "✅ 未检测到相关 Ruby 文件的改动，跳过。"
          return
        end

        # 2. 初始化 AI 客户端（彻底移除 Analyzer/RuboCop）
        return if skip_ai
        ai_client = AiClient.new

        all_suggestions = []
        puts "🤖 正在通过 Gemini 分析 #{changes.size} 个文件的业务逻辑..."

        # 3. 循环评审每个文件
        changes.each do |file_path, changed_lines|
          full_file_path = File.expand_path(file_path, project_root)
          next unless File.exist?(full_file_path)

          print "📝 正在评审: #{file_path} ... "

          file_content = File.read(full_file_path)

          # 调用 AI：去掉了 static_issues 传递，专注内容
          suggestion = ai_client.get_review(
            file_path: file_path,
            content: file_content,
            lines: changed_lines,
            is_full: full_review
          )

          # 只有非 LGTM 的建议才会被记录
          if suggestion && !suggestion.strip.upcase.start_with?("LGTM")
            puts "💡 发现改进点"
            all_suggestions << {
              file_path: file_path,
              suggestion: suggestion,
              line: (changed_lines.is_a?(Array) ? changed_lines.first : 1)
            }
          else
            puts "✅ 通过"
          end
        end

        # 4. 发布评审结果
        handle_report(all_suggestions, dry_run, platform, repo, pr_number)
      end
    rescue StandardError => e
      puts "💥 评审中断: #{e.message}"
      puts e.backtrace.first(5)
    end

    private

    # 专门获取 Ruby 文件的变动逻辑
    def get_ruby_diff_changes(full: false)
      changes = {}
      # 智能判断基准分支
      base = ENV['GITHUB_BASE_REF'] ? "origin/#{ENV['GITHUB_BASE_REF']}" : "HEAD~1"

      # 只关注 .rb, .rake, Gemfile
      files = `git diff #{base}...HEAD --name-only --diff-filter=d`.split("\n")
      ruby_files = files.select { |f| f.end_with?('.rb', '.rake') || f == 'Gemfile' }

      ruby_files.each do |file|
        if full
          line_count = File.foreach(file).count rescue 1
          changes[file] = (1..line_count).to_a
        else
          lines = []
          # 提取具体的变动行号
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

    def handle_report(suggestions, dry_run, platform, repo, pr_number)
      if dry_run || suggestions.empty?
        puts "\n--- 评审摘要 ---"
        if suggestions.empty?
          puts "🎉 非常棒！AI 没有发现明显的逻辑缺陷。"
        else
          suggestions.each { |s| puts "\n📍 [#{s[:file_path]}:#{s[:line]}]\n#{s[:suggestion]}" }
        end
      else
        puts "\n📡 正在将评审意见同步至 #{platform}..."
        reporter = Reporter.for(platform, repo, pr_number)
        reporter.publish_review(suggestions)
      end
    end
  end
end
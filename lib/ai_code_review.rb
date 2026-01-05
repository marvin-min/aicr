# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'ai_code_review/ai_client'
require_relative 'ai_code_review/reporter'

module AiCodeReview
  class << self
    def start(path = '.', repo: nil, pr_number: nil, dry_run: false, platform: 'github', skip_ai: false, full_review: false)
      project_root = File.expand_path(path, Dir.pwd)

      # 采纳建议：增加目录存在性检查
      unless Dir.exist?(project_root)
        puts "💥 项目根目录不存在: #{project_root}"
        return
      end

      Dir.chdir(project_root) do
        puts "🚀 开始专业级 Ruby 代码逻辑评审..."

        changes = get_ruby_diff_changes(full: full_review)
        if changes.empty?
          puts "✅ 未检测到相关 Ruby 文件的改动，跳过。"
          return
        end

        return if skip_ai
        ai_client = AiClient.new

        all_suggestions = []
        puts "🤖 正在深度分析 #{changes.size} 个文件的业务逻辑..."

        changes.each do |file_path, changed_lines|
          full_file_path = File.expand_path(file_path, project_root)
          next unless File.exist?(full_file_path)

          print "📝 正在评审: #{file_path} ... "
          file_content = File.read(full_file_path)

          suggestion = ai_client.get_review(
            file_path: file_path,
            content: file_content,
            lines: changed_lines,
            is_full: full_review
          )

          # 采纳建议：增加 suggestion 的 nil 检查，防止 strip 崩溃
          if suggestion && !suggestion.strip.empty? && !suggestion.strip.upcase.start_with?("PASS")
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

        handle_report(all_suggestions, dry_run, platform, repo, pr_number)
      end
    rescue StandardError => e
      puts "💥 评审中断: #{e.message}"
      puts e.backtrace.first(3)
    end

    private

    def get_ruby_diff_changes(full: false)
      changes = {}
      base = ENV.fetch('GITHUB_BASE_REF', 'HEAD~1')
      base = "origin/#{base}" if ENV['GITHUB_BASE_REF']

      # 采纳建议：完全参数化 git 命令
      stdout, _, status = Open3.capture3("git", "diff", "--name-only", "--diff-filter=d", "#{base}...HEAD")
      return {} unless status.success?

      ruby_files = stdout.split("\n").select { |f| f.end_with?('.rb', '.rake') || f == 'Gemfile' }

      ruby_files.each do |file|
        if full
          # 采纳建议：使用 lazy 读取，防止大文件内存溢出
          line_count = File.foreach(file).lazy.count rescue 0
          changes[file] = (1..line_count).to_a
        else
          diff_out, _, diff_stat = Open3.capture3("git", "diff", "--unified=0", "#{base}...HEAD", file)
          if diff_stat.success?
            lines = []
            diff_out.each_line do |line|
              if (match = line.match(/@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/))
                start_line = match[1].to_i
                count = (match[2] || 1).to_i
                # 采纳建议：更 Ruby 风格的写法
                (start_line...start_line + count).each { |i| lines << i }
              end
            end
            changes[file] = lines unless lines.empty?
          end
        end
      end
      changes.reject { |_, v| v.empty? }
    end

    def handle_report(suggestions, dry_run, platform, repo, pr_number)
      # 采纳建议：优化 handle_report 逻辑结构
      if suggestions.empty?
        puts "\n--- 评审摘要 ---"
        puts "🎉 非常棒！AI 没有发现明显的逻辑缺陷。"
      elsif dry_run
        puts "\n--- 评审摘要 ---"
        suggestions.each { |s| puts "\n📍 [#{s[:file_path]}:#{s[:line]}]\n#{s[:suggestion]}" }
      else
        puts "\n📡 正在将评审意见同步至 #{platform}..."
        reporter = Reporter.for(platform, repo, pr_number)
        sanitized = suggestions.map { |s| s.merge(suggestion: s[:suggestion].strip) }
        reporter.publish_review(sanitized)
      end
    end
  end
end
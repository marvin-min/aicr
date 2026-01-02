# frozen_string_literal: true

require_relative 'ai_code_review/analyzer'
require_relative 'ai_code_review/ai_client'
require_relative 'ai_code_review/reporter'

module AiCodeReview
  class << self
    # 主入口方法
    def start(path = '.', repo: nil, pr_number: nil, dry_run: false, platform: 'github', skip_ai: false)
      puts '🔍 正在分析 Git Diff 改动内容...'

      # 1. 获取本次改动的文件及其行号 (基于 Git)
      # 这里默认对比 HEAD~1，在 CI 环境下可以根据环境变量调整对比分支
      changes = get_diff_changes(path)

      if changes.empty?
        puts '✅ 未检测到 Ruby 代码改动，任务结束。'
        return
      end

      # 2. 运行 RuboCop 获取静态分析参考
      # 虽然我们看全文，但 RuboCop 的报错能帮 AI 快速锁定低级错误
      analyzer = Analyzer.new(path)
      static_results = analyzer.run

      if skip_ai
        puts '⚠️ 已开启 --skip-ai，仅展示静态扫描结果：'
        render_static_report(static_results)
        return
      end

      puts "🤖 正在为 #{changes.keys.size} 个改动文件生成 AI 评审建议..."
      ai_client = AiClient.new
      review_items = []

      # 3. 遍历改动的文件进行精准评审
      changes.each do |file_path, changed_lines|
        next unless File.exist?(file_path)

        puts "  - 正在分析: #{file_path} (改动行: #{changed_lines.join(', ')})"

        file_content = File.read(file_path)
        # 提取该文件相关的 RuboCop 问题
        file_issues = static_results.find { |r| r[:file_path] == file_path }&.fetch(:issues, []) || []

        # 调用 AI 获取评审（传入全文、改动行号、以及静态分析参考）
        suggestion = ai_client.get_diff_review(file_path, file_content, changed_lines, file_issues)

        if suggestion && !suggestion.strip.empty?
          review_items << {
            file_path: file_path,
            line: changed_lines.first, # 建议贴在改动的第一行
            suggestion: suggestion
          }
        end
      end

      # 4. 发布报告
      if review_items.empty?
        puts 'System: AI 未发现需要人工介入的逻辑问题。'
      elsif dry_run
        render_local_report(review_items)
      else
        publish_remote_report(platform, repo, pr_number, review_items)
      end
    end

    private

    # 解析 Git Diff 提取改动的文件名和具体行号
    def get_diff_changes(path)
      changes = {}
      # unified=0 确保只输出改动行，不带上下文，方便解析
      # HEAD~1 是针对本地最近一次 commit，CI 环境下可改为 origin/main...HEAD
      raw_diff = `git -C #{path} diff HEAD~1 --unified=0`.force_encoding('UTF-8')

      current_file = nil
      raw_diff.each_line do |line|
        if line.start_with?('+++ b/')
          current_file = line.sub('+++ b/', '').strip
          changes[current_file] = [] if current_file.end_with?('.rb')
        elsif line.start_with?('@@') && current_file&.end_with?('.rb')
          # 解析 @@ -10,4 +12,6 @@ 这种格式，提取 + 后面新代码的起始行和长度
          if (match = line.match(/@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/))
            start_line = match[1].to_i
            count = (match[2] || 1).to_i
            # 将改动的行号存入数组 (例如 [12, 13, 14, 15, 16, 17])
            count.times { |i| changes[current_file] << (start_line + i) }
          end
        end
      end
      changes.delete_if { |_, lines| lines.empty? }
      changes
    end

    def render_static_report(results)
      results.each do |result|
        puts "\n📁 文件: #{result[:file_path]}"
        result[:issues].each { |i| puts "  [L#{i[:line]}] #{i[:message]}" }
      end
    end

    def render_local_report(items)
      puts "\n#{"═" * 60}\n🧪 [DRY RUN] AI 深度评审结果\n#{"═" * 60}"
      items.each do |item|
        puts "\n📍 #{item[:file_path]} (第 #{item[:line]} 行起)\n#{'─' * 40}\n#{item[:suggestion]}\n"
      end
    end

    def publish_remote_report(platform, repo, pr_number, items)
      reporter = Reporter.for(platform, repo, pr_number)
      reporter.publish_review(items)
      puts "🎉 评审已成功发布到 #{platform}！"
    rescue StandardError => e
      puts "❌ 发布失败: #{e.message}"
      render_local_report(items)
    end
  end
end
# frozen_string_literal: true

require 'dotenv/load'
require 'json'
require_relative 'ai_code_review/analyzer'
require_relative 'ai_code_review/ai_client'
require_relative 'ai_code_review/reporter'

module AiCodeReview
  class << self
    def start(path = '.', repo: nil, pr_number: nil)
      puts '🚀 AI Code Review 启动...'
      puts "📍 目标仓库: #{repo || '未指定'}"
      puts "📍 PR 编号: #{pr_number || '未指定'}"

      analyzer = Analyzer.new(path)

      # 1. 自动修复基础格式问题
      analyzer.fix!

      # 2. 扫描剩余的复杂问题
      results = analyzer.run

      if results.empty?
        puts '✅ 代码非常完美，无需 AI 介入。'
        return
      end

      # 3. 初始化组件
      ai_client = AiClient.new
      reporter = repo && pr_number ? Reporter.new(repo, pr_number) : nil
      all_review_items = [] # 用于收集所有文件的建议

      results.each do |result|
        puts "\n📄 正在分析: #{result[:file_path]}"

        # 为了实现行内评论，我们可能需要让 AI 针对每个 issue 给出短建议
        # 或者直接取第一个 issue 的行号作为锚点
        suggestion = ai_client.get_review_suggestions(result[:file_path], result[:issues])
        # 获取该文件第一个问题的行号作为锚点（或者你可以根据 AI 返回细化）
        line_anchor = result[:issues].first[:line]

        all_review_items << {
          file_path: result[:file_path],
          line: line_anchor,
          suggestion: suggestion
        }
      end

      # 发布结果
      if reporter && !all_review_items.empty?
        reporter.publish_review(all_review_items)
      else
        puts "\n💡 本地运行结果 (未发送至 GitHub):"
        all_review_items.each { |item| puts "[#{item[:file_path]}:#{item[:line]}]\n#{item[:suggestion]}" }
      end
    end
  end
end

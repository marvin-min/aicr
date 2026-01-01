# frozen_string_literal: true

require 'dotenv/load'
require 'json'
require_relative 'ai_code_review/analyzer'
require_relative 'ai_code_review/ai_client'
require_relative 'ai_code_review/reporter'

module AiCodeReview
  class << self
    def start(path = '.')
      puts '🚀 AI Code Review 启动...'
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

      # 最后统一发布
      repo = ENV['GITHUB_REPOSITORY']
      pr_id = ENV['GITHUB_PR_NUMBER']
      if repo && pr_id && !all_review_items.empty?
        Reporter.new(repo, pr_id).publish_review(all_review_items)
      end
    end
  end
end

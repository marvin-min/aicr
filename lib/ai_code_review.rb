# frozen_string_literal: true

require 'dotenv/load'
require 'json'
require 'octokit'
require 'faraday'

# 加载子模块
require_relative 'ai_code_review/analyzer'
require_relative 'ai_code_review/ai_client'

module AiCodeReview
  class << self
    def start(path = '.')
      # 1. 运行 RuboCop 分析
      analyzer = Analyzer.new(path)
      analyzer.run
      # 第一步：物理修复（直接改文件）
      analyzer.fix!

      # 第二步：重新分析修复后还剩下的问题
      results = analyzer.run

      if results.empty?
        puts '✅ 完美！没发现需要 AI 介入的代码问题。'
        return
      end

      puts "🔍 发现 #{results.size} 个文件存在改进空间，准备请求 AI 评审..."

      ai_client = AiClient.new

      results.each do |result|
        puts "\n📄 文件: #{result[:file_path]}"

        # 打印具体的 RuboCop 发现
        result[:issues].each do |issue|
          puts "  📍 行 #{issue[:line]}: [#{issue[:cop_name]}] #{issue[:message]}"
        end

        puts '🤖 正在请求 AI 深度评审...'

        # 2. 获取 AI 建议
        suggestion = ai_client.get_review_suggestions(result[:file_path], result[:issues])

        puts "\n💡 AI 评审建议："
        puts '------------------------------------------'
        puts suggestion
        puts '------------------------------------------'
      end
    end
  end
end

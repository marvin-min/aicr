require 'dotenv/load'
require 'json'
require_relative 'ai_code_review/analyzer'
require_relative 'ai_code_review/ai_client'
require_relative 'ai_code_review/reporter'

module AiCodeReview
  class << self
    def start(path = ".")
      puts "🚀 AI Code Review 启动..."
      analyzer = Analyzer.new(path)

      # 1. 自动修复基础格式问题
      analyzer.fix!

      # 2. 扫描剩余的复杂问题
      results = analyzer.run

      if results.empty?
        puts "✅ 代码非常完美，无需 AI 介入。"
        return
      end

      # 3. 初始化组件
      ai_client = AiClient.new

      # 只有当环境变量存在时才初始化 Reporter
      repo = ENV['GITHUB_REPOSITORY']
      pr_id = ENV['GITHUB_PR_NUMBER']
      reporter = (repo && pr_id) ? Reporter.new(repo, pr_id) : nil

      # 4. 逐个评审
      results.each do |result|
        puts "\n📄 正在评审: #{result[:file_path]}"

        suggestion = ai_client.get_review_suggestions(result[:file_path], result[:issues])

        puts "💡 AI 建议：\n#{suggestion}"

        # 5. 发布到 GitHub
        reporter&.publish(result[:file_path], suggestion)
      end
    end
  end
end
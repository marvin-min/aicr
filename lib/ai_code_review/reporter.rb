require 'octokit'

module AiCodeReview
  class Reporter
    def initialize(repo_name, pr_number)
      @repo_name = repo_name
      @pr_number = pr_number.to_i
      @client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
    end

    # 新方法：一次性发布所有文件的行内评论
    def publish_review(review_data)
      return if review_data.empty?

      # 构造 GitHub 要求的行内评论格式
      comments = review_data.map do |item|
        {
          path: item[:file_path],
          line: item[:line].to_i,
          body: "🤖 **AI 建议**：\n\n#{item[:suggestion]}"
        }
      end

      # 发起一次 PR Review 动作
      @client.create_pull_request_review(
        @repo_name,
        @pr_number,
        {
          event: 'COMMENT', # 或者 'REQUEST_CHANGES'
          comments: comments
        }
      )
      puts "✅ 已成功在 GitHub PR ##{@pr_number} 发布行内评审！"
    rescue => e
      puts "❌ 发布行内评审失败: #{e.message}"
    end
  end
end
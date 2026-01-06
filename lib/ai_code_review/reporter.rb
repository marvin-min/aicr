# frozen_string_literal: true

require 'octokit' # 👈 别忘了这个！

module AiCodeReview
  class Reporter
    def self.for(platform, repo, pr_number)
      case platform.to_s.downcase
      when 'github'
        GitHubReporter.new(repo, pr_number)
      else
        raise "Unsupported platform: #{platform}"
      end
    end
  end

  class GitHubReporter
    def initialize(repo, pr_number)
      @repo = repo
      @pr_number = pr_number.to_i
      @client = Octokit::Client.new(access_token: ENV.fetch('GITHUB_TOKEN', nil))
    end

    def publish_review(items)
      # 1. 准备 Commit SHA
      head_sha = @client.pull_request(@repo, @pr_number).head.sha

      # 2. 将 AI 的建议转换成 GitHub 期待的 "Draft Comments" 格式
      # 每一项都会对应到具体的行
      draft_comments = items.map do |item|
        {
          path: item[:file_path],
          line: item[:line].to_i, # 必须是精准行号
          side: 'RIGHT',
          body: "[🤖 AI 建议]\n#{item[:suggestion]}"
        }
      end

      if draft_comments.empty?
        puts '✅ 没有发现问题，无需创建 Review。'
        return
      end

      # 3. 核心步骤：这就是你说的 "Start a review" 并 "Submit"
      # 这一个 API 调用就完成了：开启评审 -> 添加多个行内评论 -> 提交评审
      @client.create_pull_request_review(
        @repo,
        @pr_number,
        {
          commit_id: head_sha,
          event: 'COMMENT', # 对应 "Comment" 模式，也可以是 "REQUEST_CHANGES"
          body: "🤖 AI 代码评审已完成，共发现 #{draft_comments.size} 处改进建议。",
          comments: draft_comments
        }
      )
      puts '🚀 批量行内评审已成功提交！'
    end
  end
end

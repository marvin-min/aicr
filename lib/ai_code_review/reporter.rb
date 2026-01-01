# frozen_string_literal: true

require 'octokit'

module AiCodeReview
  class Reporter
    def initialize(repo_name, pr_number)
      @repo_name = repo_name
      @pr_number = pr_number.to_i
      @client = Octokit::Client.new(access_token: ENV.fetch('GITHUB_TOKEN', nil))
    end

    def publish_review(review_data)
      return if review_data.empty?

      # 1. 尝试构造行内评论
      comments = review_data.map do |item|
        {
          path: item[:file_path],
          line: item[:line].to_i,
          side: 'RIGHT',
          body: "🤖 **AI 建议**：\n\n#{item[:suggestion]}"
        }
      end

      begin
        # 尝试发起正式的 Review
        @client.create_pull_request_review(@repo_name, @pr_number, {
                                             event: 'COMMENT',
                                             comments: comments
                                           })
        puts '✅ 行内评审已成功发布！'
      rescue Octokit::UnprocessableEntity => e
        # 2. 如果行号不在 Diff 范围内，触发降级方案
        puts '⚠️ 部分行号不在 PR 改动范围内，正在汇总发表全局评论...'
        publish_summary_comment(review_data)
      end
    end

    private

    def publish_summary_comment(review_data)
      summary = review_data.map do |item|
        "### 📄 文件: `#{item[:file_path]}` (第 #{item[:line]} 行)\n#{item[:suggestion]}"
      end.join("\n\n---\n\n")

      header = "### 🤖 AI 代码评审报告\n> 提示：部分建议涉及未改动的上下文行，已汇总至此。\n\n"
      @client.add_comment(@repo_name, @pr_number, header + summary)
      puts '✅ 全局汇总评论已发布！'
    end
  end
end

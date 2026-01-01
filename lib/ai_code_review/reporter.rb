require 'octokit'

module AiCodeReview
  class Reporter
    def initialize(repo_name, pr_number)
      @repo_name = repo_name # 格式如 "user/project"
      @pr_number = pr_number
      @client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
    end

    def publish(file_path, suggestion)
      puts "📤 正在将建议发布到 GitHub PR ##{@pr_number}..."

      comment_body = <<~MARKDOWN
        ### 🤖 AI 代码评审建议
        **文件：** `#{file_path}`

        #{suggestion}

        ---
        *由 [AI-Code-Reviewer] 自动生成*
      MARKDOWN

      # 在 PR 下方发表全局评论
      @client.add_comment(@repo_name, @pr_number, comment_body)
      puts "✅ 发布成功！"
    rescue => e
      puts "❌ 发布失败: #{e.message}"
    end
  end
end
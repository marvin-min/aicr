# frozen_string_literal: true

require 'octokit'

module AiCodeReview
  class Reporter
    # 工厂方法：根据平台返回对应的实例
    def self.for(platform, repo, id)
      case platform.to_s.downcase
      when 'github'
        GitHubReporter.new(repo, id)
      when 'gitlab'
        GitLabReporter.new(repo, id)
      else
        raise "❌ 不支持的平台: #{platform}"
      end
    end
  end

  # GitHub 发布逻辑
  class GitHubReporter
    def initialize(repo, pr_number)
      @repo = repo
      @pr_number = pr_number.to_i
      @token = ENV['GITHUB_TOKEN'] || ENV['AI_REVIEW_TOKEN']

      if @token.nil? || @token.empty?
        raise "❌ 缺少 GITHUB_TOKEN，无法发布评论到 GitHub。"
      end

      @client = Octokit::Client.new(access_token: @token)
    end

    def publish_review(items)
      return if items.nil? || items.empty?
      # 1. 过滤掉 AI 返回 PASS 的项目，以及内容为空的项目
      valid_items = items.reject do |item|
        item[:suggestion].nil? ||
          item[:suggestion].to_s.strip.upcase == 'PASS'
      end
      if valid_items.empty?
        puts "✅ 所有改动均通过 AI 评审，无需发布评论。"
        return
      end
      puts "📢 发现有效建议，正在发布到 #{@platform}..."
      items.each do |item|
        begin
          # 在 PR 的指定行号添加行内评论 (Line Comment)
          @client.create_pull_request_comment(
            @repo,
            @pr_number,
            "[🤖 AI Review]\n\n#{item[:suggestion]}",
            @client.pull_request(@repo, @pr_number).head.sha,
            item[:file_path],
            item[:line]
          )
        rescue Octokit::UnprocessableEntity => e
          # 如果报错位置不在 Diff 中，GitHub 会抛出 422 错误
          # 此时我们可以选择降级，发布一条全局评论
          puts "⚠️ 无法在 #{item[:file_path]}:#{item[:line]} 处发布行内评论（可能超出了 PR 改动范围）。"
          publish_fallback_comment(item)
        rescue StandardError => e
          puts "❌ 发布到 GitHub 失败: #{e.message}"
        end
      end
    end

    private

    # 降级方案：如果行内评论发不出，就发普通评论
    def publish_fallback_comment(item)
      body = "### 🤖 AI 补充建议\n**文件**: #{item[:file_path]}\n**建议**: #{item[:suggestion]}"
      @client.add_comment(@repo, @pr_number, body)
    end
  end

  # GitLab 发布逻辑 (预留扩展)
  class GitLabReporter
    def initialize(repo, mr_id)
      @repo = repo
      @mr_id = mr_id
      # 这里可以集成 gitlab gem
    end

    def publish_review(items)
      puts "🛠 GitLab 发布功能正在开发中..."
      items.each { |i| puts "本地预览 [GitLab]: #{i[:suggestion]}" }
    end
  end
end
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
      # 支持从不同的环境变量读取，更灵活
      @token = ENV['GITHUB_TOKEN'] || ENV['AI_REVIEW_TOKEN']

      raise "❌ 缺少 GITHUB_TOKEN，请检查环境变量设置" if @token.nil? || @token.empty?

      @client = Octokit::Client.new(access_token: @token)
    end

    def publish_review(items)
      puts "DEBUG: 收到 AI 建议共 #{items&.size || 0} 条"

      valid_items = items.reject do |item|
        s = item[:suggestion].to_s.strip
        s.empty? || s.upcase == 'PASS'
      end

      if valid_items.empty?
        puts "✅ 经过过滤，没有需要发布的有效建议。"
        return
      end

      puts "📢 发现 #{valid_items.size} 条有效建议，准备发布至 GitHub..."

      # 💡 优化：获取当前 PR 最新的 Commit SHA
      begin
        pr_info = @client.pull_request(@repo, @pr_number)
        head_sha = pr_info.head.sha
      rescue => e
        puts "❌ 无法获取 PR 信息: #{e.message}"
        return
      end

      valid_items.each do |item|
        puts "DEBUG: 正在尝试发布评论到 #{item[:file_path]}:#{item[:line]}"
        begin
          # GitHub API 需要四个关键参数：path, position/line, body, commit_id
          @client.create_pull_request_comment(
            @repo,
            @pr_number,
            "[🤖 AI Review]\n\n#{item[:suggestion]}",
            head_sha,
            item[:file_path],
            item[:line]
          )
          puts "✨ 成功为 #{item[:file_path]} 第 #{item[:line]} 行添加评论"
        rescue Octokit::UnprocessableEntity => e
          # 常见的错误是 line 不在 diff 中，这时调用 fallback
          puts "⚠️ 行内评论失败 (可能是行号不在本次 Diff 范围内): #{e.message}"
          publish_fallback_comment(item)
        rescue => e
          puts "❌ 发布失败: #{e.class} - #{e.message}"
        end
      end
    end

    private

    def publish_fallback_comment(item)
      body = <<~MARKDOWN
        ### 🤖 AI 补充建议
        **文件**: `#{item[:file_path]}` (第 #{item[:line]} 行)
        **建议**: 
        #{item[:suggestion]}
      MARKDOWN
      @client.add_comment(@repo, @pr_number, body)
      puts "📝 已将建议作为普通评论发布至 PR"
    end
  end
end
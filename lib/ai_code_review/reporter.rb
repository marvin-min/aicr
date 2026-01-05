class GitHubReporter
  def initialize(repo, pr_number)
    @repo = repo
    @pr_number = pr_number.to_i
    @token = ENV['GITHUB_TOKEN'] || ENV['AI_REVIEW_TOKEN']

    raise "❌ 缺少 GITHUB_TOKEN" if @token.nil? || @token.empty?

    @client = Octokit::Client.new(access_token: @token)
  end

  def publish_review(items)
    # 打印收到的原始数据量，确认 AI 确实给东西了
    puts "DEBUG: 收到 AI 建议共 #{items&.size || 0} 条"

    valid_items = items.reject do |item|
      s = item[:suggestion].to_s.strip
      s.empty? || s.upcase == 'PASS'
    end

    if valid_items.empty?
      puts "✅ 经过过滤，没有需要发布的有效建议。"
      return
    end

    # 修复变量错误：@platform 改为 "GitHub"
    puts "📢 发现 #{valid_items.size} 条有效建议，准备发布..."

    # 获取 SHA
    head_sha = @client.pull_request(@repo, @pr_number).head.sha

    valid_items.each do |item|
      puts "DEBUG: 正在尝试发布评论到 #{item[:file_path]}:#{item[:line]}"
      begin
        @client.create_pull_request_comment(
          @repo, @pr_number,
          "[🤖 AI Review]\n\n#{item[:suggestion]}",
          head_sha,
          item[:file_path],
          item[:line]
        )
        puts "✨ 成功为 #{item[:file_path]} 第 #{item[:line]} 行添加评论"
      rescue Octokit::UnprocessableEntity => e
        puts "⚠️ 行内评论失败 (行号可能不在 Diff 内): #{e.message}"
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
        **建议**: #{item[:suggestion]}
      MARKDOWN
    @client.add_comment(@repo, @pr_number, body)
  end
end
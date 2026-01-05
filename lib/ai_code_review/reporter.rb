class GitHubReporter
  def initialize(repo, pr_number)
    @repo = repo
    @pr_number = pr_number.to_i
    @token = ENV['GITHUB_TOKEN'] || ENV['AI_REVIEW_TOKEN']

    raise "❌ 缺少 GITHUB_TOKEN" if @token.nil? || @token.empty?

    @client = Octokit::Client.new(access_token: @token)
  end

  def publish_review(items)
    return if items.nil? || items.empty?

    # 1. 仅处理有意义的建议
    valid_items = items.reject do |item|
      s = item[:suggestion].to_s.strip
      s.empty? || s.upcase == 'PASS'
    end

    if valid_items.empty?
      puts "✅ 所有改动均通过 AI 评审。"
      return
    end

    # 2. 性能优化：循环外获取一次 SHA，避免重复请求
    puts "📢 正在发布 #{valid_items.size} 条建议到 GitHub..."
    head_sha = @client.pull_request(@repo, @pr_number).head.sha

    # 3. 遍历过滤后的集合
    valid_items.each do |item|
      begin
        @client.create_pull_request_comment(
          @repo,
          @pr_number,
          "🤖 **[AI Review]**\n\n#{item[:suggestion]}",
          head_sha,
          item[:file_path],
          item[:line]
        )
      rescue Octokit::UnprocessableEntity
        puts "⚠️ 无法在 #{item[:file_path]}:#{item[:line]} 发布行内评论，转为全局评论。"
        publish_fallback_comment(item)
      rescue StandardError => e
        puts "❌ 发布失败: #{e.message}"
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
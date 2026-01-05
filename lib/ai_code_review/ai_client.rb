# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module AiCodeReview
  class AiClient
    DEFAULT_API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

    # 1. 专业的全维度 Template，强制要求无发现不准回复
    PROMPT_TEMPLATE = <<~PROMPT
      ### Role
      你是一位追求极致品质的资深 Ruby on Rails 架构师。

      ### Task
      请对下方提供的 Ruby 代码进行深度评审。
      评审维度：1.安全隐患 2.逻辑缺陷 3.命名规范 4.Rails 最佳实践。

      ### Operational Rules (重要)
      - **Silence is Approval**: 如果代码符合标准，【严禁】输出任何字符。
      - **Bypass Annotation**: 严禁评审处于 `# ai:disable` 到 `# ai:enable` 之间或包含 `# ai:skip` 的代码。
      - **No Chat**: 严禁回复 PASS 或要求代码，没问题请保持绝对沉默。

      ### Source Code to Review
      File: %{file_path}
      Scope: %{scope}
      [CODE_START]
      %{content}
      [CODE_END]

      ### Output Format (仅在有建议时)
      #### 🛠️ [类别]
      - **Issue**: [精准描述]
      - **Fix**:
      ```ruby
      [建议代码]
      ```
    PROMPT

    def initialize
      env_url = ENV['AI_API_URL']&.strip || DEFAULT_API_URL
      @uri = URI.parse(env_url.start_with?('http') ? env_url : "https://#{env_url}")
      @api_key = ENV['AI_API_KEY']&.strip
      @model   = ENV['AI_MODEL_NAME'] || "qwen-max"

      raise "❌ AI_API_KEY 未设置" if @api_key.nil? || @api_key.empty?
    end

    def get_review(file_path:, content:, lines:, is_full: false)
      scope = is_full ? "全量评审" : "改动行: #{lines.join(', ')}"
      prompt = PROMPT_TEMPLATE % { file_path: file_path, scope: scope, content: content }
      call_ai_api(prompt)
    end

    private

    def call_ai_api(prompt)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == 'https')
      http.read_timeout = 120

      request = Net::HTTP::Post.new(@uri.request_uri, {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      })
      request.body = { model: @model, messages: [{ role: 'user', content: prompt }], temperature: 0.1 }.to_json

      begin
        response = http.request(request)
        return nil unless response.code == '200'

        content = JSON.parse(response.body).dig('choices', 0, 'message', 'content')&.strip

        # --- 极致自动化拦截逻辑 ---
        # 1. 如果为空或包含 PASS，直接静默
        return nil if content.nil? || content.empty? || content.upcase.include?("PASS")

        # 2. 如果回复中没有结构化的标题（####），说明 AI 在闲聊或问问题，直接静默
        return nil unless content.include?("####")

        content
      rescue StandardError
        nil
      end
    end
  end
end
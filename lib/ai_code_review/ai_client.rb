# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module AiCodeReview
  class AiClient
    DEFAULT_API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    PROMPT_PATH = File.expand_path('prompts/default.md', __dir__)

    def initialize
      @prompt_template = File.read(PROMPT_PATH)
      env_url = ENV['AI_API_URL']&.strip || DEFAULT_API_URL
      @uri = URI.parse(env_url.start_with?('http') ? env_url : "https://#{env_url}")
      @api_key = ENV['AI_API_KEY']&.strip
      @model   = ENV['AI_MODEL_NAME'] || "qwen-max"

      raise "❌ AI_API_KEY 未设置" if @api_key.nil? || @api_key.empty?
    end

    def get_review(file_path:, content:, lines:, is_full: false)
      # 1. 构造任务描述
      scope_desc = is_full ? "全量评审整个文件" : "重点评审以下行号: #{lines.join(', ')}"

      # 2. 将 Prompt 指令与具体代码完全隔离
      # 使用 heredoc 构造用户消息，避免 % 导致的格式化报错
      user_input = <<~USER_MSG
          [目标文件]: #{file_path}
          [评审范围]: #{scope_desc}
          
          [待评审源码]:
          ```ruby
          #{content}
          ```
          USER_MSG

      # 3. 发送给 API
      # 这里的 @prompt_template 仅包含 expert.md 的纯指令内容
      call_ai_api(system_prompt: @prompt_template, user_message: user_input)
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
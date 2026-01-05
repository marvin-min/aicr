# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'cgi'
require 'openssl'

module AiCodeReview
  class AiClient
    DEFAULT_API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

    PROMPT_TEMPLATE = <<~PROMPT
      ### Role
      你是一位拥有 10 年经验的资深 Ruby on Rails 架构师。

      ### Context
      - 文件路径: %{file_path}
      - 评审范围: %{scope}

      ### Rules
      - 无隐患则仅回复 "PASS"。
      - 必须提供具体的优化建议代码。

      ### 待评审代码内容:
      %{content}
    PROMPT

    def initialize
      # 采纳建议：环境变量 strip 处理
      env_url = ENV['AI_API_URL']&.strip || DEFAULT_API_URL
      @uri = parse_url(env_url)

      @api_key = ENV['AI_API_KEY']&.strip
      @model   = ENV['AI_MODEL_NAME']&.strip || "qwen-max"

      raise "❌ AI_API_KEY 未设置" if @api_key.nil? || @api_key.empty?
    end

    def get_review(file_path:, content:, lines:, is_full: false)
      scope = is_full ? "全量评审" : "改动行: #{lines.join(', ')}"
      # 采纳建议：对元数据进行转义处理，防止 Prompt 注入
      prompt = PROMPT_TEMPLATE % {
        file_path: CGI.escapeHTML(file_path),
        scope: CGI.escapeHTML(scope),
        content: content # 保持代码原文以利于 AI 理解逻辑
      }
      call_ai_api(prompt)
    end

    private

    def parse_url(url)
      parsed = URI.parse(url)
      return parsed if parsed.is_a?(URI::HTTP) || parsed.is_a?(URI::HTTPS)
      URI.parse("https://#{url}")
    rescue URI::InvalidURIError
      raise "❌ 无效的 AI_API_URL: #{url}"
    end

    def call_ai_api(prompt)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == 'https')

      # 采纳建议：SSL 安全加固
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?

      http.read_timeout = 120
      http.open_timeout = 30

      request = Net::HTTP::Post.new(@uri.request_uri, {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      })

      request.body = {
        model: @model,
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.1
      }.to_json

      begin
        response = http.request(request)
        handle_response(response)
      rescue Timeout::Error, Errno::ECONNRESET, EOFError, Net::ProtocolError, OpenSSL::SSL::SSLError => e
        puts "⚠️ 通讯失败: #{e.message}"
        nil
      rescue StandardError => e
        puts "⚠️ 未知错误: #{e.message}"
        nil
      end
    end

    def handle_response(response)
      if response.code == '200'
        res_body = JSON.parse(response.body)
        content = res_body.dig('choices', 0, 'message', 'content')
        (content.nil? || content.strip.upcase == 'PASS') ? nil : content
      else
        puts "⚠️ API 错误: #{response.code} - #{response.message}"
        nil
      end
    rescue JSON::ParserError
      puts "⚠️ API 返回了无效的 JSON"
      nil
    end
  end
end
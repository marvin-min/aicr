# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module AiCodeReview
  class AiClient
    def initialize
      # 1. 优先从环境变量读取，否则使用写死的默认地址
      @api_url = ENV['AI_API_URL'] || "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      @api_key = ENV['AI_API_KEY']
      @model   = ENV['AI_MODEL_NAME'] || "qwen-max"

      if @api_key.nil? || @api_key.empty?
        raise "❌ 环境变量 AI_API_KEY 未设置。"
      end

      # 2. 预解析并强制转换类型
      # URI.parse 在某些情况下会返回 URI::Generic，通过 URI() 转换更稳健
      @uri = URI(@api_url.strip)

      unless @uri.is_a?(URI::HTTP) || @uri.is_a?(URI::HTTPS)
        raise "❌ 无效的 API URL 格式 (#{@uri.class}): #{@api_url}。请确保以 https:// 开头。"
      end
    end

    def get_diff_review(file_path, content, changed_lines, static_issues = [])
      issues_context = static_issues.map { |i| "- [L#{i[:line]}] #{i[:message]}" }.join("\n")

      prompt = <<~PROMPT
        你是一个 Ruby 专家。请评审 `#{file_path}` 的改动行：#{changed_lines.join(', ')}。
        参考 RuboCop 报错：\n#{issues_context}
        要求：只评改动行，逻辑优先。若无问题回复 "PASS"。
        代码全文：\n#{content}
      PROMPT

      call_ai_api(prompt)
    end

    private

    def call_ai_api(prompt)
      # 获取路径，如果 path 为空则默认为 /
      # 这样可以避免 request_uri 在 Generic 对象上失效的问题
      path = @uri.path.empty? ? "/" : @uri.request_uri

      header = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      }

      body = {
        model: @model,
        messages: [
          { role: 'system', content: 'You are a professional Ruby code reviewer.' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.2
      }

      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 30

      # 这里使用 path 替代 @uri.request_uri 以增加兼容性
      request = Net::HTTP::Post.new(path, header)
      request.body = body.to_json

      response = http.request(request)

      if response.code == '200'
        result = JSON.parse(response.body)
        content = result.dig('choices', 0, 'message', 'content')
        content.to_s.strip.upcase == 'PASS' ? nil : content
      else
        puts "❌ API 请求失败 (Code: #{response.code}): #{response.body}"
        nil
      end
    rescue StandardError => e
      puts "❌ AI 服务连接异常: #{e.message}"
      nil
    end
  end
end
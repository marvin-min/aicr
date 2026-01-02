# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module AiCodeReview
  class AiClient
    DEFAULT_API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

    def initialize
      env_url = ENV['AI_API_URL']
      @api_url = (env_url && !env_url.strip.empty?) ? env_url.strip : DEFAULT_API_URL
      @api_key = ENV['AI_API_KEY']
      @model   = ENV['AI_MODEL_NAME'] || "qwen-max"

      raise "❌ AI_API_KEY 未设置" if @api_key.nil? || @api_key.strip.empty?

      @uri = URI(@api_url)
      if @uri.is_a?(URI::Generic) && !@uri.is_a?(URI::HTTP) && !@uri.is_a?(URI::HTTPS)
        @uri = URI("https://#{@api_url}")
      end
    end

    def get_review(file_path:, content:, lines:, static_issues: [], is_full: false)
      issues_context = static_issues.empty? ? "无" : static_issues.map { |i| "- [L#{i[:line]}] #{i[:message]}" }.join("\n")

      task_instruction = is_full ? "请全量评审该文件。" : "仅审阅改动行: #{lines.join(', ')}。"

      prompt = <<~PROMPT
        你是一个严谨的 Ruby 代码评审专家。
        文件: #{file_path}
        任务: #{task_instruction}
        参考静态扫描: #{issues_context}
        要求: 若代码合格回复 "PASS"，否则给出改进建议和重构示例。
        代码全文:
        #{content}
      PROMPT

      call_ai_api(prompt)
    end

    private

    def call_ai_api(prompt)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == 'https')
      http.read_timeout = 180

      request = Net::HTTP::Post.new(@uri.request_uri, {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      })

      request.body = {
        model: @model,
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.1
      }.to_json

      response = http.request(request)
      if response.code == '200'
        content = JSON.parse(response.body).dig('choices', 0, 'message', 'content')
        content.to_s.strip.upcase == 'PASS' ? nil : content
      end
    rescue => e
      puts "⚠️ AI 调用异常: #{e.message}"
      nil
    end
  end
end
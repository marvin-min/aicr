# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'code_processor'

module AiCodeReview
  class AiClient
    DEFAULT_API_URL = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'
    PROMPT_PATH = File.expand_path('prompts/default.md', __dir__)

    def initialize
      @prompt_template = File.read(PROMPT_PATH)
      env_url = ENV['AI_API_URL']&.strip || DEFAULT_API_URL
      @uri = URI.parse(env_url.start_with?('http') ? env_url : "https://#{env_url}")
      @api_key = ENV['AI_API_KEY']&.strip
      @model   = ENV['AI_MODEL_NAME'] || 'qwen-max'

      raise '❌ AI_API_KEY 未设置' if @api_key.nil? || @api_key.empty?
    end

    def get_review(file_path:, content:, lines:, is_full:)
      system_prompt = <<~SYSTEM
        你是一个严苛的 Ruby 专家。请评审代码并**只**返回 JSON 格式的数组。
        格式：[{"line": 行号, "suggestion": "建议内容"}]
        如果没有发现问题，请直接返回空数组 []。
        注意：line 必须在提供的行号范围内：#{lines.inspect}
      SYSTEM

      user_message = "文件：#{file_path}\n代码内容：\n#{content}"

      response = call_ai_api(system_prompt: system_prompt, user_message: user_message)

      return [] if response.nil? || response.empty?

      suggestions = []

      # 1. 尝试暴力正则提取：匹配 {"line": 数字, "suggestion": "内容"}
      # 这个正则可以跨越换行符，并且对中间的空格不敏感
      items = response.scan(/\{\s*"line":\s*(\d+),\s*"suggestion":\s*"(.*?)"\s*\}/m)

      if items.any?
        items.each do |line_num, text|
          # 清理 text 中可能存在的转义引号或换行符
          clean_text = text.gsub('\"', '"').gsub('\n', "\n").strip

          suggestions << {
            'line' => line_num.to_i,
            'suggestion' => clean_text
          }
        end
      else
        # 2. 如果正则没抓到，尝试最后一次标准解析（带强力空格清理）
        begin
          clean_json = response.encode('UTF-8', invalid: :replace, undef: :replace)
                               .gsub(/[^[:print:]\n]/, ' ') # 替换所有不可见字符为空格
          suggestions = begin
            JSON.parse(clean_json)
          rescue StandardError
            []
          end
        rescue StandardError
          return []
        end
      end

      # 3. 过滤行号逻辑
      is_full ? suggestions : suggestions.select { |s| lines.include?(s['line'].to_i) }
    end

    private

    def call_ai_api(system_prompt:, user_message:)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == 'https')
      http.read_timeout = 120

      request = Net::HTTP::Post.new(@uri.request_uri, {
                                      'Content-Type' => 'application/json',
                                      'Authorization' => "Bearer #{@api_key}"
                                    })

      request.body = {
        model: @model,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_message }
        ],
        temperature: 0.1
        # 强制要求 JSON 模式（如果模型支持的话，阿里 Qwen 部分模型支持）
      }.to_json

      begin
        response = http.request(request)

        if response.code != '200'
          puts "❌ API 错误: #{response.code} - #{response.body}"
          return nil
        end

        content = JSON.parse(response.body).dig('choices', 0, 'message', 'content')&.strip

        if ENV['DEBUG']
          puts "\n--- AI 原始回复内容 ---"
          puts content.nil? ? '空返回' : content
          puts "------------------------\n"
        end

        # ✅ 修正 2：移除旧的 #### 拦截逻辑，因为 JSON 不包含这些
        return nil if content.nil? || content.empty? || content.upcase == 'PASS'

        content
      rescue StandardError => e
        puts "⚠️ 发生异常: #{e.message}"
        nil
      end
    end
  end
end

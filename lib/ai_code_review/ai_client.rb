# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'code_processor'

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

      # 2. 对代码内容进行预处理（骨架提取）

      # --- 添加以下调试代码 ---
      if ENV['DEBUG']
        puts "\n" + "—" * 40
        puts "DEBUG: 发送给 AI 的文件: #{file_path}"
        puts "DEBUG: 原始行数: #{content.count("\n")}"
        puts "—" * 40 + "\n"
      end
      # -----------------------
      # 3. 将指令与加工后的代码构造为用户消息
      user_input = <<~USER_MSG
    [目标文件]: #{file_path}
    [评审范围]: #{scope_desc}
    
    [待评审源码]:
    ```ruby
    #{content}
    ```
  USER_MSG

      # 4. 发送给 API
      call_ai_api(system_prompt: @prompt_template, user_message: user_input)
    end

    private

    private

    # 修正：支持接收两个参数，并修正调试变量名
    def call_ai_api(system_prompt:, user_message:)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == 'https')
      http.read_timeout = 120

      request = Net::HTTP::Post.new(@uri.request_uri, {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      })

      # 将 system_prompt 和 user_message 组合发送
      request.body = {
        model: @model,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_message }
        ],
        temperature: 0.1
      }.to_json

      begin
        response = http.request(request)

        # 如果 code 不是 200，在 DEBUG 模式下至少给个响声
        if response.code != '200'
          puts "❌ API 错误: #{response.code} - #{response.body}" if ENV['DEBUG']
          return nil
        end

        content = JSON.parse(response.body).dig('choices', 0, 'message', 'content')&.strip

        # 修正变量名为 content
        if ENV['DEBUG']
          puts "\n--- AI 原始回复内容 ---"
          puts content.nil? ? "空返回" : content
          puts "------------------------\n"
        end

        # --- 极致自动化拦截逻辑 ---
        return nil if content.nil? || content.empty? || content.upcase.include?("PASS")
        return nil unless content.include?("####")

        content
      rescue StandardError => e
        puts "⚠️ 发生异常: #{e.message}" if ENV['DEBUG']
        nil
      end
    end
  end
end
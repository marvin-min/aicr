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
      # 保持你原有的默认模型 Qwen
      @model   = ENV['AI_MODEL_NAME'] || "qwen-max"

      raise "❌ AI_API_KEY 未设置" if @api_key.nil? || @api_key.strip.empty?

      @uri = URI(@api_url)
      if @uri.is_a?(URI::Generic) && !@uri.is_a?(URI::HTTP) && !@uri.is_a?(URI::HTTPS)
        @uri = URI("https://#{@api_url}")
      end
    end

    # 核心功能优化：移除 static_issues，注入专业评审维度
    def get_review(file_path:, content:, lines:, is_full: false)
      scope_instruction = is_full ? "全量评审该文件内容。" : "仅重点评审改动行（行号：#{lines.join(', ')}）。"

      # 整合专业 Prompt 模板
      prompt = <<~PROMPT
        ### Role
        你是一位拥有 10 年经验的资深 Ruby/Rails 专家，正在进行代码评审。

        ### Context
        - 文件路径: #{file_path}
        - 评审范围: #{scope_instruction}

        ### Review Dimensions (优先级排序)
        1. **Security & Performance**: 检查 SQL 注入、越权风险、N+1 查询、内存溢出或慢查询。
        2. **Business Logic**: 检查边界条件（nil 处理）、逻辑漏洞。
        3. **Maintainability**: 检查复杂的嵌套、过长的方法、硬编码。
        4. **Code Style**: 仅指出严重违反 Ruby 惯例的命名或风格。

        ### Rules
        - 如果代码表现完美，**必须仅回复 "PASS"**。
        - 否则，请指出问题并给出**优化后的代码示例**。
        - 忽略琐碎的空格、引号等格式问题。

        ### 代码内容:
        #{content}

        ### Output Format (如果有建议)
        #### 🛡️ 安全与性能 (Critical)
        - [描述]
        - ```ruby [建议代码] ```
        #### 🧠 逻辑与架构 (Logic)
        - [描述]
        ---
        #### 💡 综合评价
        [一句话总结]
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
        temperature: 0.1 # 保持低随机性
      }.to_json

      response = http.request(request)
      if response.code == '200'
        content = JSON.parse(response.body).dig('choices', 0, 'message', 'content')
        # 兼容处理：只有明确回复 PASS 才跳过，否则返回建议
        content.to_s.strip.upcase == 'PASS' ? nil : content
      else
        puts "⚠️ API 返回错误: #{response.code} - #{response.body}"
        nil
      end
    rescue => e
      puts "⚠️ AI 调用异常: #{e.message}"
      nil
    end
  end
end
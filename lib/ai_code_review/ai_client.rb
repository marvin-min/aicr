# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module AiCodeReview
  class AiClient
    def initialize
      # 1. 基础配置读取
      @api_url = ENV['AI_API_URL'] || "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      @api_key = ENV['AI_API_KEY']
      @model   = ENV['AI_MODEL_NAME'] || "qwen-max"

      if @api_key.nil? || @api_key.empty?
        raise "❌ 环境变量 AI_API_KEY 未设置，请在 GitHub Secrets 中配置。"
      end

      # 2. 稳健的 URI 解析
      # 使用 strip 去除可能存在的首尾空格，防止 URI 解析失败
      begin
        @uri = URI(@api_url.strip)
      rescue URI::InvalidURIError => e
        raise "❌ 无法解析 AI_API_URL: #{e.message}。请检查地址是否包含 http(s)://。"
      end

      unless @uri.is_a?(URI::HTTP) || @uri.is_a?(URI::HTTPS)
        raise "❌ 无效的 API URL 格式 (#{@uri.class}): #{@api_url}。必须以 https:// 或 http:// 开头。"
      end
    end

    # 针对改动行进行精准评审
    def get_diff_review(file_path, content, changed_lines, static_issues = [])
      # 格式化 RuboCop 问题供 AI 参考
      issues_context = if static_issues.empty?
                         "未发现基础规范问题。"
                       else
                         static_issues.map { |i| "- [第 #{i[:line]} 行] #{i[:cop_name]}: #{i[:message]}" }.join("\n")
                       end

      prompt = <<~PROMPT
        你是一个严谨的 Ruby 代码评审专家。
        
        【背景】
        文件: #{file_path}
        改动行号: #{changed_lines.join(', ')}
        
        【参考 RuboCop 报错】
        #{issues_context}
        
        【任务】
        1. 仅审阅上述【改动行号】内的代码。
        2. 忽略未改动的陈旧代码。
        3. 重点关注：逻辑漏洞、性能隐患、代码可读性。
        4. 如果改动行质量合格，请直接回复 "PASS"，不要有任何废话。
        5. 否则，请给出精炼的改进建议和重构示例。

        【代码全文】
        #{content}
      PROMPT

      call_ai_api(prompt)
    end

    private

    def call_ai_api(prompt)
      # 确保路径正确，避免 request_uri 在 Generic 对象上报错
      path = @uri.path.empty? ? "/" : @uri.request_uri

      header = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      }

      body = {
        model: @model,
        messages: [
          { role: 'system', content: 'You are a professional Ruby reviewer who provides concise and actionable feedback.' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.1 # 极低随机性，确保评审结果稳定
      }

      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == 'https')

      # --- 关键：解决 ReadTimeout 的配置 ---
      http.open_timeout = 30   # 连接超时 (秒)
      http.read_timeout = 180  # 读取响应超时 (增加到 3 分钟，应对复杂逻辑分析)
      # ----------------------------------

      max_retries = 2
      attempt = 0

      begin
        attempt += 1
        request = Net::HTTP::Post.new(path, header)
        request.body = body.to_json

        response = http.request(request)

        if response.code == '200'
          result = JSON.parse(response.body)
          content = result.dig('choices', 0, 'message', 'content')
          # AI 觉得没问题则返回 nil，不发布评论
          content.to_s.strip.upcase == 'PASS' ? nil : content
        else
          puts "❌ API 业务错误 (Code: #{response.code}): #{response.body}"
          nil
        end
      rescue Net::ReadTimeout, Net::OpenTimeout => e
        if attempt <= max_retries
          puts "⚠️ AI 响应超时，正在进行第 #{attempt} 次重试..."
          retry
        else
          puts "❌ AI 服务响应超时：服务器在 180 秒内未返回结果，已停止重试。"
          nil
        end
      rescue StandardError => e
        puts "❌ AI 服务连接异常: #{e.message}"
        nil
      end
    end
  end
end
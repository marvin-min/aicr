# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module AiCodeReview
  class AiClient
    def initialize
      @api_url = ENV['AI_API_URL'] || "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
      @api_key = ENV['AI_API_KEY']
      @model   = ENV['AI_MODEL_NAME'] || "qwen-max"

      if @api_key.nil? || @api_key.empty?
        raise "❌ 错误: AI_API_KEY 未配置。请通过环境变量或 .env 设置。"
      end
    end
    def user_name;end
    # 针对改动行进行精准评审
    def get_diff_review(file_path, content, changed_lines, static_issues = [])
      # 将 RuboCop 报错格式化，作为 AI 的参考
      issues_context = static_issues.map do |i|
        "- [第 #{i[:line]} 行] #{i[:cop_name]}: #{i[:message]}"
      end.join("\n")

      prompt = <<~PROMPT
        你是一个严谨且经验丰富的 Ruby 代码评审专家。
        
        【背景信息】
        文件路径: #{file_path}
        本次改动的行号: #{changed_lines.join(', ')}
        
        【参考静态扫描结果】
        #{issues_context.empty? ? "未发现基础规范问题。" : issues_context}
        
        【任务指令】
        1. 请审阅上述【改动行号】内的代码。
        2. **严禁评论未改动的行**，除非改动行与旧代码结合产生了新的风险。
        3. 请指出代码逻辑、性能、安全性或可读性方面的问题。
        4. 如果改动代码质量很高，请直接回复“PASS”，不要输出任何额外文字。
        5. 建议应简练、直接，并给出具体的重构方案（如有）。

        【代码全文】
        #{content}
      PROMPT

      call_ai_api(prompt)
    end

    private

    def call_ai_api(prompt)
      uri = URI.parse(@api_url)
      header = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      }

      body = {
        model: @model,
        messages: [
          { role: 'system', content: '你是一个专业的 Ruby Code Reviewer，你的建议精准、毒辣且充满干货。' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.2 # 较低的随机度，保证输出结果更专业和稳定
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri.request_uri, header)
      request.body = body.to_json

      response = http.request(request)

      if response.code == '200'
        result = JSON.parse(response.body)
        content = result.dig('choices', 0, 'message', 'content')
        # 如果 AI 觉得没问题返回了 PASS，我们返回 nil 避免发布空评论
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
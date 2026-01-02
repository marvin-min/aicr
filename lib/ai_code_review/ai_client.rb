# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'json'

module AiCodeReview
  class AiClient
    def initialize
      # 动态读取环境变量，默认为 DashScope
      @api_url = ENV.fetch('AI_API_URL', '').strip
      @api_key = ENV.fetch('AI_API_KEY', '').strip
      @model   = ENV.fetch('AI_MODEL_NAME', '').strip
      raise 'AI_API_URL configuration is missing' if @api_url == ''
      raise 'AI_MODEL_NAME is missing' if @model.strip == ''
      raise 'AI_API_KEY is missing' if @api_key.strip == ''
      raise '\r\n无法调用AI专业建议' if @api_url == '' || @api_key == '' || @model == ''

      @conn = Faraday.new(url: @api_url) do |f|
        f.request :json
        f.response :json

        # 增加重试机制，应对网络波动
        f.request :retry, max: 2, interval: 0.5

        # 增加超时设置，因为 AI 思考代码需要时间
        f.options.timeout = 60
        f.options.open_timeout = 10

        f.adapter Faraday.default_adapter
      end
    end

    def get_review_suggestions(file_path, issues)
      code_content = File.read(file_path)

      # 构造专业的 Prompt
      prompt = <<~PROMPT
        你是一个严苛但友好的 Ruby 技术专家。请审查以下代码。

        [上下文信息]
        文件: #{file_path}
        RuboCop 发现的问题: #{issues.map { |i| "#{i[:cop_name]}: #{i[:message]}" }.join(', ')}

        [完整源代码]
        #{code_content}

        [任务要求]
        1. 不要只复述 RuboCop 的报错，要解释这个报错在 Ruby 最佳实践中意味着什么。
        2. 如果发现代码有潜在的性能隐患（比如 N+1 查询、内存泄露）或安全风险，请指出。
        3. 提供一个“优雅”的重构范例，使用 Ruby 的 Idiomatic 风格。
        4. 你的回复应该是鼓励性的，并保持简洁。
        5. 请使用 Markdown 格式，代码部分使用 Ruby 语法高亮。
      PROMPT

      response = @conn.post do |req|
        req.headers['Authorization'] = "Bearer #{@api_key}"
        req.body = {
          model: @model,
          messages: [
            { role: 'system', content: '你是一个专业的代码评审助手。' },
            { role: 'user', content: prompt }
          ],
          temperature: 0.3 # 较低的随机性，保证建议的稳定性
        }
      end

      extract_suggestion(response)
    rescue StandardError => e
      "❌ AI 客户端发生异常: #{e.message}"
    end

    private

    def extract_suggestion(response)
      if response.success?
        # 自动兼容标准的 OpenAI 响应格式
        content = response.body.dig('choices', 0, 'message', 'content')
        return content if content && !content.empty?

        '⚠️ AI 返回了空结果，请检查模型配置。'
      else
        # 错误处理：解析 API 返回的报错详情
        error_info = response.body.is_a?(Hash) ? (response.body['error'] || response.body['errors']) : nil
        error_msg = error_info.is_a?(Hash) ? error_info['message'] : response.body

        puts "❌ API 调用失败 (状态码: #{response.status})"
        puts "详情: #{error_msg}"
        "AI 评审暂时不可用 (错误码: #{response.status})"
      end
    end
  end
end

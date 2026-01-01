# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'json'

module AiCodeReview
  class AiClient
    # 更新为 DashScope 的标准 OpenAI 兼容接口
    API_URL = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'

    def initialize
      @api_key = ENV.fetch('AI_API_KEY', nil)
      # 在 DashScope 上，模型名称就是 qwen-max
      @model = ENV['AI_MODEL_NAME'] || 'qwen-max'

      @conn = Faraday.new(url: API_URL) do |f|
        f.request :json
        f.response :json
        f.options.timeout = 60 # qwen-max 思考较慢，给足时间
        f.request :retry, max: 2, interval: 0.5
        f.adapter Faraday.default_adapter
      end
    end

    def get_review_suggestions(file_path, issues)
      code_content = File.read(file_path)

      prompt = <<~PROMPT
        你是一个资深的 Ruby 专家。请针对以下 RuboCop 报错进行代码审查，并提供重构建议。

        [文件] #{file_path}
        [报错] #{issues.to_json}

        [源代码]
        #{code_content}

        要求：
        1. 解释报错原因。
        2. 给出优化后的代码示例。
        3. 如果有性能或安全性隐患，请一并指出。
        4. 请用中文回答。
      PROMPT

      response = @conn.post do |req|
        req.headers['Authorization'] = "Bearer #{@api_key}"
        req.body = {
          model: @model,
          messages: [
            { role: 'system', content: '你是一个专业的代码评审助手。' },
            { role: 'user', content: prompt }
          ]
        }
      end

      if response.success?
        response.body.dig('choices', 0, 'message', 'content')
      else
        error_detail = if response.body.is_a?(Hash)
                         response.body.fetch('error', {}).fetch('message',
                                                                response.body)
                       else
                         response.body
                       end
        puts "❌ AI 调用失败: #{error_detail}"
        "AI 繁忙中 (错误详情: #{error_detail})"
      end
    rescue StandardError => e
      "AI 异常: #{e.message}"
    end
  end
end

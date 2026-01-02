# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module AiCodeReview
  class AiClient
    # 默认 API 地址（通义千问兼容模式）
    DEFAULT_API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

    def initialize
      # 1. 配置读取与预处理
      env_url = ENV['AI_API_URL']
      @api_url = (env_url && !env_url.strip.empty?) ? env_url.strip : DEFAULT_API_URL
      @api_key = ENV['AI_API_KEY']
      @model   = ENV['AI_MODEL_NAME'] || "qwen-max"

      if @api_key.nil? || @api_key.strip.empty?
        raise "❌ 环境变量 AI_API_KEY 未设置或为空。"
      end

      # 2. 健壮的 URI 解析
      begin
        @uri = URI(@api_url)
        # 如果漏写协议头，自动补全
        if @uri.is_a?(URI::Generic) && !@uri.is_a?(URI::HTTP) && !@uri.is_a?(URI::HTTPS)
          @api_url = "https://#{@api_url}"
          @uri = URI(@api_url)
        end
      rescue => e
        raise "❌ URL 解析失败: #{e.message} (地址: #{@api_url})"
      end
    end

    # 统一评审接口
    # @param file_path [String] 文件路径
    # @param content [String] 文件全文内容
    # @param lines [Array] 需要评审的行号
    # @param static_issues [Array] RuboCop 发现的问题
    # @param is_full [Boolean] 是否开启全量模式
    def get_review(file_path:, content:, lines:, static_issues: [], is_full: false)
      issues_context = if static_issues.empty?
                         "未发现基础规范问题。"
                       else
                         static_issues.map { |i| "- [第 #{i[:line]} 行] #{i[:cop_name]}: #{i[:message]}" }.join("\n")
                       end

      # 根据全量/增量模式动态生成任务指令
      task_instruction = if is_full
                           <<~TASK
                             1. 请对该文件的【全文】进行全量评审。
                             2. 重点关注：整体架构设计、逻辑漏洞、性能隐患、代码可读性。
                           TASK
                         else
                           <<~TASK
                             1. 仅审阅上述【改动行号】内的代码：#{lines.join(', ')}。
                             2. 忽略未改动的陈旧代码。
                             3. 重点关注：改动逻辑引发的漏洞、性能隐患、代码可读性。
                           TASK
                         end

      prompt = <<~PROMPT
        你是一个严谨的 Ruby 代码评审专家。
        
        【背景】
        文件: #{file_path}
        #{is_full ? "模式: 全量评审 (Full Review)" : "改动行号: #{lines.join(', ')}"}
        
        【参考 RuboCop 报错】
        #{issues_context}
        
        【任务】
        #{task_instruction}
        4. 如果质量合格，请直接回复 "PASS"，不要有任何废话。
        5. 否则，请给出精炼的改进建议和重构示例。

        【代码全文】
        #{content}
      PROMPT

      call_ai_api(prompt)
    end

    private

    def call_ai_api(prompt)
      # 兼容性路径获取
      req_path = @uri.path.empty? ? "/" : @uri.request_uri

      header = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      }

      body = {
        model: @model,
        messages: [
          { role: 'system', content: 'You are a professional Ruby code reviewer. Reply "PASS" if the code is good.' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.1
      }

      # 网络请求配置
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == 'https')
      http.open_timeout = 20  # 连接超时
      http.read_timeout = 180 # 读取超时（应对大模型长文本处理）

      max_retries = 2
      attempt = 0

      begin
        attempt += 1
        request = Net::HTTP::Post.new(req_path, header)
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
      rescue Net::ReadTimeout, Net::OpenTimeout
        if attempt <= max_retries
          puts "⚠️ AI 响应超时，正在进行第 #{attempt} 次重试..."
          retry
        else
          puts "❌ AI 服务连接超时，已达到最大重试次数。"
          nil
        end
      rescue StandardError => e
        puts "❌ AI 服务连接异常: #{e.message}"
        nil
      end
    end
  end
end
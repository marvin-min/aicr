#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'ai_code_review/analyzer'
require_relative 'ai_code_review/ai_client'
require_relative 'ai_code_review/reporter'

module AiCodeReview
  class << self
    # 主入口方法
    # @param path [String] 项目路径
    # @param repo [String] 仓库名 (user/repo)
    # @param pr_number [Integer/String] PR 编号
    # @param dry_run [Boolean] 是否为干跑模式
    # @param platform [String] 平台类型 (github/gitlab)
    def start(path = '.', repo: nil, pr_number: nil, dry_run: false, platform: 'github', skip_ai: false)
      puts '🔍 正在启动代码扫描...'

      # 1. 运行 RuboCop 分析代码
      analyzer = Analyzer.new(path)
      # 如果你想在 AI 评审前自动修复基础格式问题，可以取消下面一行的注释

      results = analyzer.run
      if results.empty?
        puts '✅ 太棒了！未发现任何 RuboCop 报错，无需 AI 介入。'
        return
      else
        puts "🔧 正在尝试自动修复基础规范问题..."
        # analyzer.fix!
      end

      # --- 新增：如果开启了 skip_ai，展示完结果直接结束 ---
      if skip_ai
        puts '⚠️  已开启 --skip-ai，跳过 AI 分析步骤。'
        render_static_report(results)
        return
      end
      # -----------------------------------------------

      puts "🤖 正在连接 AI 获取评审建议 (模型: #{ENV.fetch('AI_MODEL_NAME', nil)})..."
      ai_client = AiClient.new
      review_items = []

      # 2. 遍历分析结果，逐个获取 AI 建议
      results.each do |result|
        file_path = result[:file_path]
        issues = result[:issues]

        # 调用 AI 客户端
        suggestion = ai_client.get_review_suggestions(file_path, issues)

        # 记录评审数据
        review_items << {
          file_path: file_path,
          line: issues.first[:line], # 默认贴在第一个报错行
          suggestion: suggestion
        }
        puts "  - 已完成分析: #{file_path}"
      end

      # 3. 根据模式决定输出去向
      if dry_run
        render_local_report(review_items)
      else
        publish_remote_report(platform, repo, pr_number, review_items)
      end
    end

    def my_method;end

    private

    # 新增一个专门展示静态分析结果的方法
    def render_static_report(results)
      puts "\n#{'═' * 60}"
      puts '📊 静态分析报告 (仅 RuboCop)'
      puts '═' * 60
      results.each do |result|
        puts "\n📁 文件: #{result[:file_path]}"
        result[:issues].each do |issue|
          puts "  [第 #{issue[:line]} 行] #{issue[:cop_name]}: #{issue[:message]}"
        end
      end
      puts "\n#{'═' * 60}"
    end

    # 在终端打印美化的评审报告
    def render_local_report(items)
      puts "\n#{'═' * 60}"
      puts '🧪 [DRY RUN] 评审结果预览'
      puts '═' * 60

      items.each_with_index do |item, index|
        puts "\n[#{index + 1}] 📍 路径: #{item[:file_path]} (第 #{item[:line]} 行附近)"
        puts '─' * 40
        puts item[:suggestion]
        puts '─' * 40
      end

      puts "\n✨ 本地预览结束。如需发布到 PR，请确保提供了仓库名和 PR 编号。"
    end

    # 发布到远程平台 (GitHub/GitLab)
    def publish_remote_report(platform, repo, pr_number, items)
      puts "📡 正在同步评审建议到 #{platform.capitalize}..."

      # 昨天我们讨论了 Reporter 的工厂模式
      reporter = Reporter.for(platform, repo, pr_number)
      reporter.publish_review(items)

      puts "🎉 评审已成功发布到 #{repo} ##{pr_number}！"
    rescue StandardError => e
      puts "❌ 发布失败: #{e.message}"
      # 如果远程发布失败，作为保底，把内容打在屏幕上
      render_local_report(items)
    end
  end
end

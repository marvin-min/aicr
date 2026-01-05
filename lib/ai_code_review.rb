# frozen_string_literal: true

require 'open3'
require_relative 'ai_code_review/ai_client'
# require_relative 'ai_code_review/code_processor'
require_relative 'ai_code_review/reporter'
module AiCodeReview
  class << self
    def start(project_root: '.', full_review: false, dry_run: true, platform: 'github', repo: nil, pr_number: nil, skip_ai: false)      # 打印出当前 get_ruby_diff_changes 到底是在哪个文件、哪一行定义的
      puts "🔍 方法定义来源: #{method(:get_ruby_diff_changes).source_location}"
      # 打印出当前方法的参数要求
      puts "🔍 参数要求: #{method(:get_ruby_diff_changes).parameters}"
      ai_client = AiClient.new
      all_suggestions = []

      # 1. 获取变更文件和行号
      changes = get_ruby_diff_changes(full: full_review)

      puts "🚀 开始专业级 Ruby 代码逻辑评审..."
      puts "🤖 正在分析 #{changes.keys.size} 个文件的业务逻辑..."

      changes.each do |file_path, changed_lines|
        full_file_path = File.expand_path(file_path, project_root)
        next unless File.exist?(full_file_path)

        # 2. 核心：过滤掉包含忽略注释的行 (# ai:skip, # ai:disable...# ai:enable)
        active_lines = filter_ignored_lines(full_file_path, changed_lines, full_review)

        # 如果过滤后没有需要评审的行，直接跳过该文件
        next if active_lines.empty?

        print "📝 正在评审: #{file_path} ... "
        file_content = File.read(full_file_path)

        suggestion = ai_client.get_review(
          file_path: file_path,
          content: file_content,
          lines: active_lines,
          is_full: full_review
        )

        if suggestion
          puts "💡 发现改进点"
          all_suggestions << {
            file_path: file_path,
            suggestion: suggestion,
            line: active_lines.first
          }
        else
          puts "✅ 通过"
        end
      end

      handle_report(all_suggestions, dry_run, platform, repo, pr_number)
    end

    private

    # 解析文件，找出所有被注释忽略的行号
    def filter_ignored_lines(file_path, changed_lines, is_full)
      file_lines = File.readlines(file_path)
      ignored_line_numbers = []
      in_disabled_block = false

      file_lines.each_with_index do |content, index|
        line_num = index + 1

        if content.match?(/#\s*ai:disable/)
          in_disabled_block = true
        elsif content.match?(/#\s*ai:enable/)
          in_disabled_block = false
          # 这里的改动：不再执行 ignored_line_numbers << line_num
          # 这样 enable 这一行本身如果改了，AI 也能看见
          next
        end

        # 命中块忽略或单行忽略 (# ai:skip 或 # ai:ignore)
        if in_disabled_block || content.match?(/#\s*ai:(skip|ignore)/)
          ignored_line_numbers << line_num
        end
      end

      # 如果是全量评审，范围是全文件减去忽略行；如果是 diff 评审，则是改动行减去忽略行
      base_lines = is_full ? (1..file_lines.size).to_a : changed_lines
      base_lines - ignored_line_numbers
    end
    def get_ruby_diff_changes(full: false)
      changes = {}
      target = ENV.fetch('TARGET_BRANCH', 'master').gsub(/^origin\//, '')
      is_ci = ENV.include?('GITHUB_ACTIONS')

      # 1. 确定基准引用
      base_ref = is_ci ? "origin/#{target}" : (system("git rev-parse --verify origin/#{target} >/dev/null 2>&1") ? "origin/#{target}" : target)

      # 2. 获取分叉点
      merge_base = `git merge-base #{base_ref} HEAD`.strip
      merge_base = "HEAD~1" if merge_base.empty?

      # 3. 获取文件列表
      stdout, _, status = Open3.capture3("git", "diff", "--name-only", "--diff-filter=d", merge_base)
      return {} unless status.success?

      files = stdout.split("\n").select do |f|
        is_ruby = f.end_with?('.rb', '.rake') || f == 'Gemfile'
        is_not_spec = !f.include?('spec/') && !f.include?('test/')
        is_not_schema = f != 'db/schema.rb'
        is_ruby && is_not_spec && is_not_schema
      end

      puts "🔍 正在对比基准 [#{merge_base}] 与当前工作区的差异..."

      files.each do |file|
        if full
          # 全量模式：标记为空数组，filter_ignored_lines 会将其识别为“全文件”
          changes[file] = []
        else
          # ✅ 修复点：将 base 改为 merge_base，并去掉 ...HEAD 以支持未提交代码
          diff_out, _, diff_stat = Open3.capture3("git", "diff", "--unified=0", merge_base, file)

          if diff_stat.success?
            lines = []
            diff_out.each_line do |line|
              if (match = line.match(/@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/))
                start_line = match[1].to_i
                count = (match[2] || 1).to_i
                (start_line...start_line + count).each { |i| lines << i }
              end
            end
            changes[file] = lines unless lines.empty?
          end
        end
      end
      changes
    end
    # def get_ruby_diff_changes(full: false)
    #   changes = {}
    #   # 1. 获取目标分支名，去掉可能存在的 origin/ 前缀（防止重复）
    #   target = ENV.fetch('TARGET_BRANCH', 'master').gsub(/^origin\//, '')
    #
    #   # 2. 检查是否在 CI 环境
    #   is_ci = ENV.include?('GITHUB_ACTIONS')
    #
    #   # 3. 确定基准
    #   # CI 模式下强制用 origin/，本地模式下先尝试 origin/，失败则用本地分支
    #   base_ref = is_ci ? "origin/#{target}" : (system("git rev-parse --verify origin/#{target} >/dev/null 2>&1") ? "origin/#{target}" : target)
    #
    #   # 4. 获取分叉点 (Merge Base)
    #   merge_base = `git merge-base #{base_ref} HEAD`.strip
    #   merge_base = "HEAD~1" if merge_base.empty?
    #
    #   # 5. 执行对比
    #   # 注意：去掉 ...HEAD，直接 diff merge_base。
    #   # 这样不仅能抓到已 commit 的，还能抓到你本地正在改但还没 commit 的代码！
    #   stdout, _, status = Open3.capture3("git", "diff", "--name-only", "--diff-filter=d", merge_base)
    #
    #   puts "🔍 正在对比基准 [#{merge_base}] 与当前工作区..."
    #   return {} unless status.success?
    #
    #   # files = stdout.split("\n").select { |f| f.end_with?('.rb', '.rake') || f == 'Gemfile' }
    #   files = stdout.split("\n").select do |f|
    #     # 只评审 Ruby 文件
    #     is_ruby = f.end_with?('.rb', '.rake') || f == 'Gemfile'
    #
    #     # 排除掉测试代码或自动生成的代码（可选）
    #     is_not_spec = !f.include?('spec/') && !f.include?('test/')
    #     is_not_schema = f != 'db/schema.rb'
    #
    #     is_ruby && is_not_spec && is_not_schema
    #   end
    #   files.each do |file|
    #     if full
    #       changes[file] = [] # 全量模式逻辑交由 filter_ignored_lines 处理
    #     else
    #       diff_out, _, diff_stat = Open3.capture3("git", "diff", "--unified=0", "#{merge_base}...HEAD", file)
    #       if diff_stat.success?
    #         lines = []
    #         diff_out.each_line do |line|
    #           if (match = line.match(/@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/))
    #             start_line = match[1].to_i
    #             count = (match[2] || 1).to_i
    #             (start_line...start_line + count).each { |i| lines << i }
    #           end
    #         end
    #         changes[file] = lines unless lines.empty?
    #       end
    #     end
    #   end
    #   changes
    # end

    def handle_report(suggestions, dry_run, platform, repo, pr_number)
      if suggestions.empty?
        puts "\n--- 评审摘要 ---"
        puts "🎉 非常棒！AI 没有发现明显的逻辑缺陷。"
        return
      end

      if dry_run
        puts "\n--- 评审摘要 ---"
        suggestions.each { |s| puts "\n📍 [#{s[:file_path]}:#{s[:line]}]\n#{s[:suggestion]}" }
        puts "\n💡 提示: 当前为 [Dry Run] 模式，建议未同步至 GitHub。"
      else
        # 🚀 关键：在这里把接力棒交给 Reporter 类
        puts "\n🚀 准备发布评审结果到 #{platform}..."

        begin
          # 使用我们之前定义的工厂方法实例化
          reporter = AiCodeReview::Reporter.for(platform, repo, pr_number)

          # 执行发布逻辑
          reporter.publish_review(suggestions)
        rescue => e
          puts "❌ 发布报告时出错: #{e.message}"
          # 发生错误时，降级打印到控制台，确保建议不丢失
          suggestions.each { |s| puts "\n📍 [#{s[:file_path]}:#{s[:line]}]\n#{s[:suggestion]}" }
        end
      end
    end
  end
end
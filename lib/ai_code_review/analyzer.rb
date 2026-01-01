# frozen_string_literal: true

require 'json'

module AiCodeReview
  class Analyzer
    def initialize(path = '.')
      @path = File.expand_path(path)
    end

    def fix!
      puts '🛠️  正在执行强制自动修复...'
      Bundler.with_unbundled_env do
        # 使用 -A 强制修复所有规则，包括配置中的 final_newline
        # 增加 --fail-level fatal 确保只有严重错误才中断
        system("bundle exec rubocop #{@path} -A --fail-level fatal > /dev/null 2>&1")
      end
      # 物理延迟 0.5 秒，给操作系统文件系统同步的时间
      sleep 0.5
    end

    def run
      puts '🔍 扫描修复后的代码...'
      json_output = Bundler.with_unbundled_env do
        `bundle exec rubocop #{@path} --format json`
      end

      parse_report(json_output)
    end

    private

    def parse_report(json_data)
      return [] if json_data.nil? || json_data.strip.empty?

      data = JSON.parse(json_data)
      data['files'].map do |file_data|
        offenses = file_data['offenses']
        next if offenses.empty?

        {
          file_path: file_data['path'],
          issues: offenses.map do |o|
                    {
                      line: o['location']['start_line'],
                      message: o['message'],
                      cop_name: o['cop_name']
                    }
                  end
        }
      end.compact
    end
  end
end

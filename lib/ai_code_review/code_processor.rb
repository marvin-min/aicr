module AiCodeReview
  class CodeProcessor
    # 定义默认的上下文行数
    DEFAULT_PADDING = 50
    # 定义头部保留行数（通常包含 class 定义、require 等）
    HEADER_SIZE = 20

    class << self
      # 核心方法：提取带有“骨架”的代码内容
      # @param content [String] 原始代码全文
      # @param changed_lines [Array<Integer>] 发生变动的行号数组
      # @param padding [Integer] 变动行前后保留的行数
      def extract_skeleton(content, changed_lines, padding: DEFAULT_PADDING)
        return content if changed_lines.nil? || changed_lines.empty?

        lines = content.split("\n")
        total_lines = lines.size

        # 如果文件本身很短，没必要截取
        return content if total_lines <= HEADER_SIZE + padding

        # 1. 确定需要保留的行号索引（从 0 开始）
        keep_indices = calculate_keep_indices(total_lines, changed_lines, padding)

        # 2. 根据索引组装最终内容，并插入省略标记
        build_processed_content(lines, keep_indices)
      end

      private

      def calculate_keep_indices(total_lines, changed_lines, padding)
        # 始终保留文件头部
        indices = (0...[HEADER_SIZE, total_lines].min).to_a

        # 加上每个变动行及其前后的 padding
        changed_lines.each do |line_num|
          target_idx = line_num - 1 # 行号转数组下标
          start_idx = [target_idx - padding, 0].max
          end_idx = [target_idx + padding, total_lines - 1].min
          indices.concat((start_idx..end_idx).to_a)
        end

        indices.uniq.sort
      end

      def build_processed_content(lines, keep_indices)
        result = []
        last_idx = -1

        keep_indices.each do |idx|
          # 检查是否出现了不连续的行，如果是，插入省略号
          if last_idx != -1 && idx > last_idx + 1
            omitted_count = idx - last_idx - 1
            result << "\n# ... [此处省略 #{omitted_count} 行代码] ...\n"
          end

          result << lines[idx]
          last_idx = idx
        end

        result.join("\n")
      end
    end
  end
end
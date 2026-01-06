# frozen_string_literal: true

class Demo
  def abc; end

  def condition(param)
    case param
    when 1
      1
    when 2
      2
    when 3
      3
    else
      param.to_i
    end
  end
end

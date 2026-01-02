class Demo
  def abc;end

  def condition param
    if param == 1
      return 1
    elsif param == 2
      return 2
    elsif param == 3
      return 3
    else
      return param.to_i
    end
  end
end
class ReturnExpression < BaseNode
  delegate [:find_arg, :method_call] => :parent_node

  def return_value
    case type
    when :true
      'true'
    when :str
      "'#{children.last}'"
    when :int
      children.last.to_s
    when :lvar
      "'#{find_arg(children.last).value}'"
    when :send
      receiver, operator, param = children
      arg = find_arg(receiver.children.last)
      "'#{arg.value.send(operator, param.children.last)}'"
    else
      binding.irb
      raise "unhandled type: #{type}"
    end
  end

  def return_name
    case type
    when :true
      'true'
    when :str
      "'#{children.last}'"
    when :int
      children.last.to_s
    when :lvar
      children.last.to_s
    when :send
      receiver, operator, param = children
      "#{receiver.children.last} #{operator} #{param.children.last}"
    else
      binding.irb
      raise "unhandled type: #{type}"
    end
  end

  def conditions
    [Condition.new(self)]
  end
end

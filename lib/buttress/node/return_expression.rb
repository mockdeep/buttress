class ReturnExpression < BaseNode
  def find_arg(arg_name)
    parent_node.find_arg(arg_name)
  end

  def return_value
    case raw_node.type
    when :true
      'true'
    when :str
      "'#{raw_node.children.last}'"
    when :int
      raw_node.children.last.to_s
    when :lvar
      "'#{find_arg(raw_node.children.last).value}'"
    when :send
      receiver, operator, param = raw_node.children
      arg = find_arg(receiver.children.last)
      "'#{arg.value.send(operator, param.children.last)}'"
    else
      binding.irb
      raise "unhandled type: #{raw_node.type}"
    end
  end

  def return_name
    case raw_node.type
    when :true
      'true'
    when :str
      "'#{raw_node.children.last}'"
    when :int
      raw_node.children.last.to_s
    when :lvar
      raw_node.children.last.to_s
    when :send
      receiver, operator, param = raw_node.children
      "#{receiver.children.last} #{operator} #{param.children.last}"
    else
      binding.irb
      raise "unhandled type: #{raw_node.type}"
    end
  end

  def conditions
    [Condition.new(self)]
  end

  def method_call
    parent_node.method_call
  end
end

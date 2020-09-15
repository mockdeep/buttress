class MethodNode < BaseNode
  def method_call
    if args.any?
      "#{name}('#{args.map(&:value).join("', '")}')"
    else
      name
    end
  end

  def args
    raw_node.children[1].children.map.with_index do |arg, index|
      ArgumentNode.new(arg, index + 1)
    end
  end

  def name
    raw_node.children.first.to_s
  end

  def return_expression
    ReturnExpression.new(raw_node.children.last, parent_node: self)
  end

  def conditions
    return_expression.conditions
  end

  def return_value
    return_expression.return_value
  end

  def find_arg(name)
    args.detect { |arg| arg.name == name }
  end

  def return_name
    return_expression.return_name
  end
end

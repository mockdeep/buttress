class MethodNode < BaseNode
  delegate [:conditions, :return_value, :return_name] => :return_expression
  def method_call
    if args.any?
      "#{name}('#{args.map(&:value).join("', '")}')"
    else
      name
    end
  end

  def args
    children[1].children.map.with_index do |arg, index|
      ArgumentNode.new(arg, index + 1)
    end
  end

  def name
    children.first.to_s
  end

  def return_expression
    ReturnExpression.new(children.last, parent_node: self)
  end

  def find_arg(name)
    args.detect { |arg| arg.name == name }
  end
end

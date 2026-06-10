class ReturnExpression < BaseNode
  attr_accessor :bindings

  def initialize(raw_node, parent_node:, bindings: {})
    super(raw_node, parent_node: parent_node)
    self.bindings = bindings
  end

  def return_value
    case type
    when :true
      'true'
    when :nil
      'nil'
    when :str
      "'#{children.last}'"
    when :int
      children.last.to_s
    when :lvar
      Buttress::Literal.render(bindings.fetch(children.last))
    when :send
      receiver, operator, param = children
      value = bindings.fetch(receiver.children.last)
      Buttress::Literal.render(value.send(operator, param.children.last))
    else
      binding.irb
      raise "unhandled type: #{type}"
    end
  end

  def return_name
    case type
    when :true
      'true'
    when :nil
      'nil'
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
end

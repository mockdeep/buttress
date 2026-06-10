class ReturnExpression < BaseNode
  attr_accessor :bindings

  def initialize(raw_node, parent_node:, bindings: {})
    super(raw_node, parent_node: parent_node)
    self.bindings = bindings
  end

  def return_value
    Buttress::Literal.render(Buttress::Evaluator.call(raw_node, bindings))
  end

  def return_name
    raw_node.location&.expression&.source || 'nil'
  end
end

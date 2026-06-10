class ReturnExpression < BaseNode
  attr_accessor :bindings, :evaluator

  def initialize(raw_node, parent_node:, bindings: {}, evaluator: nil)
    super(raw_node, parent_node: parent_node)
    self.bindings = bindings
    self.evaluator = evaluator || Buttress::Evaluator.new
  end

  def return_value
    Buttress::Literal.render(evaluator.call(raw_node, bindings))
  end

  def return_name
    raw_node.location&.expression&.source || 'nil'
  end
end

class ArgumentNode < BaseNode
  attr_accessor :position

  def initialize(raw_node, position)
    super(raw_node)
    self.position = position
  end

  def value
    "blah#{position}"
  end

  def name
    children.last
  end
end

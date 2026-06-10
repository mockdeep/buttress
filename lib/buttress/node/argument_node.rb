class ArgumentNode < BaseNode
  attr_accessor :position

  def initialize(raw_node, position)
    super(raw_node)
    self.position = position
  end

  def value
    "blah#{position}"
  end

  # The parameter name is the first child for every parameter node type
  # (arg, optarg, kwarg, kwoptarg, restarg); for optional parameters the
  # last child is the default value, so children.last would be wrong.
  def name
    children.first
  end
end

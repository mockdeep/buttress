class BaseNode
  attr_accessor :raw_node, :parent_node

  def initialize(raw_node, parent_node: nil)
    raise "missing node" unless raw_node
    self.raw_node = raw_node
    self.parent_node = parent_node
  end
end

class ClassNode < BaseNode
  def find_method(method_name)
    MethodNode.new(find_method_node(raw_node, method_name), parent_node: self)
  end

  def find_method_node(raw_node, method_name)
    children.detect do |child_node|
      next unless child_node
      child_node.type == :def ||
        child_node.type == :begin && find_method_node(child_node, method_name)
    end
  end

  def name
    children.first.children.last.to_s
  end

  def instance_name
    name.split('::').last
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase
  end
end

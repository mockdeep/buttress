class ClassNode < BaseNode
  def find_method(method_name)
    lookup_method(method_name) ||
      raise(Buttress::Error, "method not found: ##{method_name}")
  end

  def lookup_method(method_name)
    node = find_method_node(raw_node, method_name.to_sym)
    node && MethodNode.new(node, parent_node: self)
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

  private

  def find_method_node(node, method_name)
    return nil unless node.is_a?(Parser::AST::Node)
    return node if node.type == :def && node.children.first == method_name

    node.children.each do |child|
      found = find_method_node(child, method_name)
      return found if found
    end
    nil
  end
end

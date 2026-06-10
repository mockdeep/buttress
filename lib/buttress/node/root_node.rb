class RootNode < BaseNode
  def find_class(class_name)
    node = find_class_node(raw_node, class_name.split('::').last)
    raise Buttress::Error, "class not found: #{class_name}" unless node

    ClassNode.new(node)
  end

  private

  # Finds a class definition by the last segment of its name, however
  # deeply nested in modules or written with a compact qualified name
  # (class Foo::Bar::Baz).
  def find_class_node(node, basename)
    return nil unless node.is_a?(Parser::AST::Node)

    if node.type == :class &&
       node.children.first.children.last.to_s == basename
      return node
    end

    node.children.each do |child|
      found = find_class_node(child, basename)
      return found if found
    end
    nil
  end
end

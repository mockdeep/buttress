class RootNode < BaseNode
  def find_class(class_name)
    basename = class_name.split('::').last
    node = find_class_node(raw_node, basename)
    raise Buttress::Error, "class not found: #{class_name}" unless node

    ClassNode.new(node, data_members: data_members_for(basename))
  end

  private

  # Member names from a sibling `Const = Data.define(:a, :b)` assignment
  # matching the class's basename — the reopened-Data-subclass idiom.
  def data_members_for(basename)
    casgn = find_data_define(raw_node, basename)
    return [] unless casgn

    casgn.children.last.children.drop(2)
      .select { |arg| arg.type == :sym }
      .map { |arg| arg.children.last }
  end

  def find_data_define(node, basename)
    return nil unless node.is_a?(Parser::AST::Node)

    if node.type == :casgn && node.children[1].to_s == basename &&
       data_define?(node.children.last)
      return node
    end

    node.children.each do |child|
      found = find_data_define(child, basename)
      return found if found
    end
    nil
  end

  def data_define?(node)
    return false unless node.is_a?(Parser::AST::Node) && node.type == :send

    receiver, message = node.children
    message == :define && receiver&.type == :const &&
      receiver.children.last == :Data
  end

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

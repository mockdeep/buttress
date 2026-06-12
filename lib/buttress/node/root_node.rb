class RootNode < BaseNode
  def find_class(class_name)
    lookup_class(class_name) ||
      raise(Buttress::Error, "class not found: #{class_name}")
  end

  # The named class by the last segment of its name, or nil.
  def lookup_class(class_name)
    basename = class_name.split('::').last
    node = find_class_node(raw_node, basename)
    return nil unless node

    ClassNode.new(
      node, parent_node: self, data_members: data_members_for(basename)
    )
  end

  # A module defined in this file, by the last segment of its name, or
  # nil.
  def find_module(module_name)
    node = find_module_node(raw_node, module_name.split('::').last)
    node && ModuleNode.new(node, parent_node: self)
  end

  # Fully qualified names of every class defined in this file, in
  # definition order, however deeply nested in modules or written with
  # compact qualified names.
  def class_names
    collect_class_names(raw_node).uniq
  end

  private

  def collect_class_names(node, namespace = [], found = [])
    return found unless node.is_a?(Parser::AST::Node)

    case node.type
    when :class, :module
      segments = const_segments(node.children.first)
      qualified = namespace + segments
      found << qualified.join('::') if node.type == :class
      node.children.drop(1).each do |child|
        collect_class_names(child, qualified, found)
      end
    else
      node.children.each do |child|
        collect_class_names(child, namespace, found)
      end
    end
    found
  end

  def const_segments(node)
    segments = []
    while node.is_a?(Parser::AST::Node) && node.type == :const
      segments.unshift(node.children.last.to_s)
      node = node.children.first
    end
    segments
  end

  def find_module_node(node, basename)
    return nil unless node.is_a?(Parser::AST::Node)

    if node.type == :module &&
       node.children.first.children.last.to_s == basename
      return node
    end

    node.children.each do |child|
      found = find_module_node(child, basename)
      return found if found
    end
    nil
  end

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

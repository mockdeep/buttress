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
    Buttress::Inflector.underscore(name)
  end

  def attr_readers
    attr_names(:reader)
  end

  def attr_writers
    attr_names(:writer)
  end

  private

  # Attribute names declared by the attr-family macros in the class
  # body. The legacy `attr :name, true` form (a 1.8-ism) declares a
  # writer via its boolean flag.
  def attr_names(role)
    body_statements.flat_map do |stmt|
      next [] unless stmt.is_a?(Parser::AST::Node) && stmt.type == :send

      receiver, macro, *args = stmt.children
      next [] unless receiver.nil?

      roles =
        case macro
        when :attr_reader then [:reader]
        when :attr_writer then [:writer]
        when :attr_accessor then %i[reader writer]
        when :attr
          args.any? { |arg| arg.type == :true } ? %i[reader writer] : [:reader]
        else []
        end
      next [] unless roles.include?(role)

      args.select { |arg| arg.type == :sym }.map { |arg| arg.children.last }
    end
  end

  def body_statements
    body = children[2]
    return [] if body.nil?

    body.type == :begin ? body.children : [body]
  end

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

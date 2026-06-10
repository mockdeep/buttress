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

  # Names of public instance methods defined in the class body, in
  # definition order, honoring visibility modifiers. initialize is
  # never included; it's exercised through instantiation instead.
  def public_method_names
    visibility = :public
    names = []

    body_statements.each do |stmt|
      next unless stmt.is_a?(Parser::AST::Node)

      case stmt.type
      when :def
        names << stmt.children.first if visibility == :public
      when :send
        receiver, message, *args = stmt.children
        next unless receiver.nil? && %i[public protected private].include?(message)

        if args.empty?
          visibility = message
        else
          marked = args.filter_map do |arg|
            case arg.type
            when :sym then arg.children.last
            when :def then arg.children.first
            end
          end
          if message == :public
            names.concat(marked)
          else
            names -= marked
          end
        end
      end
    end

    names - [:initialize]
  end

  # The defining expression of a constant assigned in the class body,
  # or nil.
  def lookup_constant(const_name)
    body_statements.each do |stmt|
      next unless stmt.is_a?(Parser::AST::Node) && stmt.type == :casgn

      scope, name, value = stmt.children
      return value if scope.nil? && name == const_name
    end
    nil
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

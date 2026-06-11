class ClassNode < BaseNode
  # Member names when this class reopens a `Const = Data.define(...)`
  # assignment; empty for ordinary classes.
  attr_accessor :data_members

  def initialize(raw_node, parent_node: nil, data_members: [])
    super(raw_node, parent_node: parent_node)
    self.data_members = data_members
  end

  def find_method(method_name)
    lookup_method(method_name) ||
      raise(Buttress::Error, "method not found: ##{method_name}")
  end

  def lookup_method(method_name)
    node = find_method_node(raw_node, method_name.to_sym)
    node && MethodNode.new(node, parent_node: self)
  end

  # A class-level method: `def self.x` (normalized to a plain def) or a
  # def inside `class << self`.
  def lookup_singleton_method(method_name)
    node = find_singleton_method_node(raw_node, method_name.to_sym)
    node && MethodNode.new(node, parent_node: self)
  end

  def name
    children.first.children.last.to_s
  end

  def instance_name
    Buttress::Inflector.underscore(name)
  end

  # The declared superclass's dotted path, or nil when this definition
  # declares none (which does not prove the class has none — a reopen
  # elsewhere may declare it; Sources records those).
  def superclass_name
    superclass = children[1]
    superclass && qualified_const_name(superclass)
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

  # Names of modules mixed in with `include`, in method lookup order:
  # a later include statement sits closer to the class than an earlier
  # one, while arguments of a single include keep their written order.
  def included_modules
    statements = body_statements.filter_map do |stmt|
      next unless stmt.is_a?(Parser::AST::Node) && stmt.type == :send

      receiver, macro, *args = stmt.children
      next unless receiver.nil? && macro == :include

      args.filter_map { |arg| qualified_const_name(arg) }
    end
    statements.reverse.flatten
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

  # The dotted path of a constant node, or nil for anything fancier
  # (Module.new, splats) — those includes just resolve to nothing.
  def qualified_const_name(node)
    return nil unless node.is_a?(Parser::AST::Node) && node.type == :const

    scope, name = node.children
    case scope&.type
    when nil then name.to_s
    when :const
      prefix = qualified_const_name(scope)
      prefix && "#{prefix}::#{name}"
    when :cbase then "::#{name}"
    end
  end

  # Walks for an instance method def, without descending into singleton
  # scopes (class << self, def self.x) or nested class/module bodies —
  # their defs are not instance methods of this class.
  def find_method_node(node, method_name)
    return nil unless node.is_a?(Parser::AST::Node)
    return node if node.type == :def && node.children.first == method_name

    node.children.each do |child|
      next if child.is_a?(Parser::AST::Node) &&
              %i[sclass defs class module].include?(child.type)

      found = find_method_node(child, method_name)
      return found if found
    end
    nil
  end

  def find_singleton_method_node(node, method_name)
    return nil unless node.is_a?(Parser::AST::Node)

    if node.type == :defs && node.children[0].type == :self &&
       node.children[1] == method_name
      return Parser::AST::Node.new(:def, node.children.drop(1))
    end

    if node.type == :sclass && node.children.first.type == :self
      found = find_method_node(node.children[1], method_name)
      return found if found
    end

    node.children.each do |child|
      next if child.is_a?(Parser::AST::Node) &&
              %i[class module].include?(child.type)

      found = find_singleton_method_node(child, method_name)
      return found if found
    end
    nil
  end
end

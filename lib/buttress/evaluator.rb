module Buttress
  # Raised when a node is beyond the evaluator's reach: user-defined
  # methods, non-whitelisted core methods, or unsupported syntax.
  class CannotEvaluate < Error; end

  # Statically evaluates an expression node against an environment of
  # variable bindings, without ever executing the code under analysis.
  # Core-type methods are delegated to the host Ruby, but only when they
  # appear in the purity whitelist, so evaluation can never trigger side
  # effects.
  class Evaluator
    PURE_METHODS = {
      String => %i[
        + * == != < > <= >= <=> nil? length size empty? upcase downcase
        capitalize swapcase reverse strip lstrip rstrip chomp chop squeeze
        include? start_with? end_with? index rindex sub gsub tr delete
        count split chars succ next center ljust rjust slice
        to_s to_i to_f to_sym inspect
      ],
      Integer => %i[
        + - * / % ** == != < > <= >= <=> nil? abs ceil floor round truncate
        succ next pred divmod gcd lcm digits
        zero? positive? negative? even? odd?
        to_s to_i to_f to_r inspect
      ],
      Float => %i[
        + - * / % ** == != < > <= >= <=> nil? abs ceil floor round truncate
        zero? positive? negative? nan? infinite? finite?
        to_s to_i to_f to_r inspect
      ],
      Symbol => %i[== != <=> nil? length size upcase downcase capitalize
                   succ next to_s to_sym inspect],
      NilClass => %i[== != nil? to_s to_a to_i inspect],
      TrueClass => %i[== != & | ^ nil? to_s inspect],
      FalseClass => %i[== != & | ^ nil? to_s inspect],
      ClassReference => %i[== != nil?],
      # String#[] is deliberately absent: its semantics changed between
      # 1.8 and 1.9, so it needs version-aware handling first.
      # Mutators like Array#<< are safe here: they only ever touch
      # values the evaluator built itself (Condition deep-dups bindings
      # into the evaluation env).
      Array => %i[
        + - * & | == != nil? [] << push concat length size empty? first
        last reverse sort min max any? none? one?
        sum uniq compact flatten include? index join slice take drop
        to_a inspect
      ],
      Hash => %i[== != nil? [] []= store delete fetch length size empty?
                 any? none? one? keys values invert merge include? key?
                 has_key? has_value? value? to_a inspect],
      Range => %i[== != nil? to_a min max first last size count sum
                  include? cover?],
    }.freeze

    # Methods allowed to receive an interpreted block. All confine the
    # block's effects to the receiver and the block body itself.
    BLOCK_METHODS = {
      Array => %i[
        map collect each select filter reject flat_map each_with_object
        detect find any? all? none? one? count sum min_by max_by sort_by
        group_by partition take_while drop_while each_with_index
        find_index reduce inject
      ],
      Hash => %i[
        map each each_pair select filter reject any? all? none? count
        sum min_by max_by sort_by group_by partition detect find
        each_with_object transform_values transform_keys
      ],
      Range => %i[
        map collect each select filter reject flat_map each_with_object
        detect find any? all? none? count sum min_by max_by sort_by
        group_by partition reduce inject
      ],
      Integer => %i[times upto downto],
    }.freeze

    # Interpreted sibling calls deeper than this are assumed to be
    # runaway recursion.
    MAX_DEPTH = 50

    # Core constants whose identity and class ancestry are stable
    # across every supported target version, so type checks against
    # them can be answered from the host.
    CORE_CONSTANTS = {
      'String' => String, 'Integer' => Integer, 'Float' => Float,
      'Symbol' => Symbol, 'Array' => Array, 'Hash' => Hash,
      'Range' => Range, 'Numeric' => Numeric, 'Object' => Object,
      'BasicObject' => BasicObject, 'NilClass' => NilClass,
      'TrueClass' => TrueClass, 'FalseClass' => FalseClass,
      'Regexp' => Regexp, 'Proc' => Proc, 'Struct' => Struct,
      'Comparable' => Comparable, 'Enumerable' => Enumerable,
      'Kernel' => Kernel,
    }.freeze

    # Methods that existed on core types in some supported target
    # version but not on the host (the taint family and Object#=~ were
    # removed in 3.x). Host absence proves nothing for these.
    REMOVED_CORE_METHODS = %i[
      taint untaint tainted? trust untrust untrusted? =~ type id
    ].freeze

    def self.call(node, env)
      new.call(node, env)
    end

    # depth carries the interpretation depth across evaluators, so
    # mutual recursion between classes still hits MAX_DEPTH. ivars
    # seeds instance state, for dispatching onto an already-built
    # InstanceValue. class_path is the qualified name of class_node
    # (which only knows its basename); target gates the few answers
    # that depend on the analyzed codebase's Ruby version.
    def initialize(class_node: nil, model_attributes: nil, sources: nil,
                   depth: 0, ivars: {}, class_path: nil, target: nil)
      @class_node = class_node
      @model_attributes = model_attributes
      @sources = sources
      @ivars = ivars
      @class_path = class_path || class_node&.name
      @target = target
      @constants = {}
      @modules = {}
      @classes = {}
      @resolving = []
      @depth = depth
    end

    attr_reader :ivars

    # Interprets the class's initialize method (if any) to populate
    # instance state, using the given argument values.
    def run_initialize(args, keywords = {})
      init = @class_node&.lookup_method(:initialize)
      invoke(init, args, keywords) if init
    end

    # Entry point for another evaluator delegating a call here (a
    # class-method send resolved to this evaluator's class).
    def invoke_method(method, args, keywords = {})
      invoke(method, args, keywords)
    end

    # Entry point for a send resolved against this evaluator's class
    # and instance state, used by instance-value dispatch. Type
    # predicates the class doesn't define itself are answered from
    # static class shape, when provable.
    def dispatch(operator, args, arg_nodes = [])
      value = resolve_send(operator, args, arg_nodes)
      value = instance_type_query(operator, args) if value.equal?(MISSING)
      if value.equal?(MISSING)
        raise CannotEvaluate, "#{@class_node.name}##{operator}"
      end

      value
    end

    def call(node, env)
      case node.type
      when :true then true
      when :false then false
      when :nil then nil
      when :int, :float, :str, :sym then node.children.last
      when :lvar then fetch(node, env)
      when :lvasgn
        env[node.children.first] = call(node.children.last, env)
      when :ivar
        # Without an interpreted initialize we can't know instance state.
        raise CannotEvaluate, source(node) unless @class_node

        @ivars[node.children.first]
      when :ivasgn
        @ivars[node.children.first] = call(node.children.last, env)
      when :return
        value = node.children.first && call(node.children.first, env)
        throw :method_return, value
      when :send then evaluate_send(node, env)
      when :super then evaluate_super(node, env)
      when :const then resolve_constant(node)
      when :begin
        node.children.map { |child| call(child, env) }.last
      when :array
        node.children.map { |child| call(child, env) }
      when :hash
        node.children.to_h do |pair|
          raise CannotEvaluate, source(node) unless pair.type == :pair

          [call(pair.children.first, env), call(pair.children.last, env)]
        end
      when :dstr
        node.children.map { |part| call(part, env).to_s }.join
      when :and
        left, right = node.children
        call(left, env) && call(right, env)
      when :or
        left, right = node.children
        call(left, env) || call(right, env)
      when :if
        condition, then_branch, else_branch = node.children
        branch = call(condition, env) ? then_branch : else_branch
        branch && call(branch, env)
      when :irange, :erange
        low, high = node.children.map { |child| child && call(child, env) }
        Range.new(low, high, node.type == :erange)
      when :block
        _send, params, body = node.children
        evaluate_block(node, block_param_names(node, params), body, env)
      when :numblock
        _send, count, body = node.children
        names = (1..count).map { |index| :"_#{index}" }
        evaluate_block(node, names, body, env)
      when :next
        value = node.children.first && call(node.children.first, env)
        throw :block_next, value
      when :break
        value = node.children.first && call(node.children.first, env)
        throw :block_break, value
      else
        raise CannotEvaluate, source(node)
      end
    end

    private

    def fetch(node, env)
      env.fetch(node.children.last) do
        raise CannotEvaluate, "unbound variable #{node.children.last}"
      end
    end

    # An unqualified constant assigned in the class body evaluates to
    # its defining expression; anything else becomes a symbolic class
    # reference.
    def resolve_constant(node)
      scope, name = node.children
      if scope.nil? && @class_node
        return @constants[name] if @constants.key?(name)

        definition = @class_node.lookup_constant(name)
        if definition
          raise CannotEvaluate, "circular constant #{name}" if
            @resolving.include?(name)

          @resolving.push(name)
          begin
            return @constants[name] = call(definition, {})
          ensure
            @resolving.pop
          end
        end
      end

      ClassReference.new(const_path(node))
    end

    def const_path(node)
      scope, name = node.children
      case scope&.type
      when nil then name.to_s
      when :const then "#{const_path(scope)}::#{name}"
      when :cbase then "::#{name}"
      else raise CannotEvaluate, source(node)
      end
    end

    def evaluate_send(node, env)
      receiver_node, operator, *arg_nodes = node.children
      return evaluate_block_pass(node, env) if
        arg_nodes.last&.type == :block_pass

      args = arg_nodes.map { |arg_node| call(arg_node, env) }

      if receiver_node.nil? || receiver_node.type == :self
        return invoke_sibling(node, operator, args, arg_nodes)
      end

      receiver = call(receiver_node, env)
      if receiver.is_a?(ClassReference)
        result = invoke_class_method(receiver, operator, args, arg_nodes)
        return result unless result.equal?(MISSING)
      end
      if receiver.is_a?(InstanceValue)
        return invoke_on_instance(receiver, operator, args, arg_nodes)
      end

      apply(receiver, operator, args)
    end

    # A send to another interpreted instance: resolve its class and
    # dispatch in a child evaluator seeded with that instance's state.
    def invoke_on_instance(instance, operator, args, arg_nodes)
      class_node = resolve_class(instance.class_path)
      unless class_node
        raise CannotEvaluate, "#{instance.class_path}##{operator}"
      end

      Evaluator.new(
        class_node: class_node, sources: @sources, depth: @depth,
        ivars: instance.ivars, class_path: instance.class_path,
        target: @target,
      ).dispatch(operator, args, arg_nodes)
    end

    # A method call on a symbolic class or module reference: resolve
    # the constant's definition (same file first, then sibling sources)
    # and interpret its singleton method in a fresh evaluator scoped to
    # it. A `new` with no singleton def constructs an interpreted
    # instance instead. MISSING when the definition or method can't be
    # found, so the caller degrades with the usual message.
    def invoke_class_method(reference, operator, args, arg_nodes)
      definition = resolve_class(reference.path) ||
                   resolve_module(reference.path)
      method = definition&.lookup_singleton_method(operator)
      if method.nil?
        return MISSING unless operator == :new

        return construct_instance(reference, args, arg_nodes)
      end

      evaluator = Evaluator.new(
        class_node: definition, sources: @sources, depth: @depth,
        class_path: reference.path, target: @target,
      )
      positional, keywords = split_keywords(method, args, arg_nodes)
      evaluator.invoke_method(method, positional, keywords)
    end

    # Class.new on a project class: interpret its initialize in a child
    # evaluator and capture the resulting instance state as an
    # InstanceValue. Without an initialize to interpret, construction
    # is only provable for an argless class with no Data members and no
    # declared superclass — anything else would fabricate instance
    # state an inherited initialize might really set.
    def construct_instance(reference, args, arg_nodes)
      class_node = resolve_class(reference.path)
      return MISSING unless class_node

      evaluator = Evaluator.new(
        class_node: class_node, sources: @sources, depth: @depth,
        class_path: reference.path, target: @target,
      )
      init = class_node.lookup_method(:initialize)
      positional, keywords = [args, {}]
      if init
        positional, keywords = split_keywords(init, args, arg_nodes)
        evaluator.invoke_method(init, positional, keywords)
      else
        return MISSING unless args.empty? &&
                              bare_class?(class_node, reference.path)
      end

      InstanceValue.new(
        class_path: reference.path, positional: positional,
        keywords: keywords, ivars: evaluator.ivars,
      )
    end

    def bare_class?(class_node, path)
      class_node.data_members.empty? &&
        class_node.superclass_name.nil? &&
        (@sources.nil? || @sources.superclass_names(path).empty?)
    end

    def resolve_class(path)
      return @classes[path] if @classes.key?(path)

      root = @class_node&.parent_node
      @classes[path] =
        (root && root.lookup_class(path)) || @sources&.find_class(path)
    end

    # super in a reopened Data subclass's initialize assigns the member
    # values. Only the keyword form is supported, and it must set every
    # member — Data.new raises for missing members, so a partial super
    # degrades rather than fabricating instance state.
    def evaluate_super(node, env)
      members = @class_node&.data_members || []
      raise CannotEvaluate, source(node) if members.empty?

      unless node.children.size == 1 && node.children.first.type == :hash
        raise CannotEvaluate, source(node)
      end

      values = call(node.children.first, env)
      unless values.keys.sort == members.sort
        raise CannotEvaluate, source(node)
      end

      values.each { |name, value| @ivars[:"@#{name}"] = value }
      nil
    end

    def evaluate_block(node, names, body, env)
      send_node = node.children.first
      receiver_node, operator, *arg_nodes = send_node.children
      raise CannotEvaluate, source(node) unless receiver_node

      receiver = call(receiver_node, env)
      args = arg_nodes.map { |arg_node| call(arg_node, env) }

      with_block(receiver, operator, args) do |*block_args|
        bind_block_params(env, names, block_args)
        catch(:block_next) { body ? call(body, env) : nil }
      end
    end

    # The &:symbol form: receiver.map(&:upcase).
    def evaluate_block_pass(node, env)
      receiver_node, operator, *arg_nodes = node.children
      sym_node = arg_nodes.pop.children.first
      unless receiver_node && sym_node&.type == :sym
        raise CannotEvaluate, source(node)
      end

      receiver = call(receiver_node, env)
      args = arg_nodes.map { |arg_node| call(arg_node, env) }
      message = sym_node.children.first

      with_block(receiver, operator, args) do |*block_args|
        apply(block_args.first, message, [])
      end
    end

    def with_block(receiver, operator, args)
      unless BLOCK_METHODS[receiver.class]&.include?(operator)
        raise CannotEvaluate, "#{receiver.class}##{operator} with a block"
      end

      catch(:block_break) do
        receiver.public_send(operator, *args) do |*block_args|
          yield(*block_args)
        end
      rescue CannotEvaluate
        raise
      rescue StandardError => error
        raise CannotEvaluate,
              "#{receiver.class}##{operator} raises #{error.class}"
      end
    end

    def block_param_names(node, params_node)
      params_node.children.flat_map do |param|
        case param.type
        when :arg then [param.children.first]
        when :procarg0
          param.children.map do |inner|
            raise CannotEvaluate, source(node) unless inner.type == :arg

            inner.children.first
          end
        else
          raise CannotEvaluate, source(node)
        end
      end
    end

    # Mimics proc argument semantics: a multi-param block destructures a
    # single array argument (hash iteration yields [key, value] pairs).
    def bind_block_params(env, names, block_args)
      if names.size > 1 && block_args.size == 1 &&
         block_args.first.is_a?(Array)
        block_args = block_args.first
      end

      names.each_with_index { |name, index| env[name] = block_args[index] }
    end

    # Sentinel distinguishing "this layer doesn't define it" from any
    # legitimately returned value, including nil.
    MISSING = Object.new

    # Receiverless sends resolve in method lookup order: the class's
    # own defs, then its attr macros and Data members (also methods on
    # the class itself), then included modules, then schema-declared
    # model attributes (defined below user includes in the ancestry).
    def invoke_sibling(node, operator, args, arg_nodes = [])
      value = resolve_send(operator, args, arg_nodes)
      raise CannotEvaluate, source(node) if value.equal?(MISSING)

      value
    end

    def resolve_send(operator, args, arg_nodes)
      return MISSING unless @class_node

      # self.class — def class is not definable, so this can't shadow.
      return ClassReference.new(@class_path) if
        operator == :class && args.empty?

      method = @class_node.lookup_method(operator)
      return invoke_split(method, args, arg_nodes) if method

      value = class_attr_access(operator, args)
      return value unless value.equal?(MISSING)

      method = included_module_method(operator)
      return invoke_split(method, args, arg_nodes) if method

      model_attr_access(operator, args)
    end

    def invoke_split(method, args, arg_nodes)
      positional, keywords = split_keywords(method, args, arg_nodes)
      invoke(method, positional, keywords)
    end

    # Ruby 3 callsite semantics for interpreted methods: a trailing
    # hash literal binds to declared keyword parameters.
    def split_keywords(method, args, arg_nodes)
      keyworded = method.args.any? do |param|
        %i[kwarg kwoptarg kwrestarg].include?(param.type)
      end
      unless keyworded && arg_nodes.last&.type == :hash &&
             args.last.is_a?(Hash)
        return [args, {}]
      end

      [args[0..-2], args.last]
    end

    # Accessors the class defines without a def to interpret:
    # attr_reader/attr_writer macros and Data members.
    def class_attr_access(operator, args)
      if args.empty? &&
         (@class_node.attr_readers.include?(operator) ||
          @class_node.data_members.include?(operator))
        return @ivars[:"@#{operator}"]
      end

      if operator.to_s.end_with?('=') && args.size == 1
        attr = operator.to_s.chomp('=').to_sym
        if @class_node.attr_writers.include?(attr)
          return @ivars[:"@#{attr}"] = args.first
        end
      end

      MISSING
    end

    def model_attr_access(operator, args)
      return MISSING unless @model_attributes

      if args.empty? && @model_attributes.column?(operator)
        return @model_attributes.read(operator)
      end

      if operator.to_s.end_with?('=') && args.size == 1
        attr = operator.to_s.chomp('=').to_sym
        if @model_attributes.column?(attr)
          return @model_attributes.write(attr, args.first)
        end
      end

      MISSING
    end

    # The first definition among included modules, in lookup order.
    # Module methods interpret in this evaluator, sharing self and
    # instance state, which mirrors include semantics. Unresolvable
    # modules (gems, stdlib) are skipped silently so the caller
    # degrades with the original message.
    def included_module_method(operator)
      @class_node.included_modules.each do |name|
        method = resolve_module(name)&.lookup_method(operator)
        return method if method
      end
      nil
    end

    def resolve_module(name)
      return @modules[name] if @modules.key?(name)

      @modules[name] =
        @class_node&.parent_node&.find_module(name) ||
        @sources&.find_module(name)
    end

    def invoke(method, args, keywords = {})
      @depth += 1
      raise CannotEvaluate, "recursion in ##{method.name}" if @depth > MAX_DEPTH

      catch(:method_return) do
        body = method.children.last
        body ? call(body, bind_params(method, args, keywords)) : nil
      end
    ensure
      @depth -= 1
    end

    def bind_params(method, args, keywords)
      env = {}
      positional = args.dup
      declared = method.args.select do |param|
        %i[kwarg kwoptarg].include?(param.type)
      end.map(&:name)
      kwrest = method.args.any? { |param| param.type == :kwrestarg }
      # An unknown keyword raises ArgumentError at runtime; binding it
      # away silently could assert the wrong behavior.
      cannot_bind(method) if !kwrest && (keywords.keys - declared).any?

      method.args.each do |param|
        name = param.name
        case param.type
        when :arg
          cannot_bind(method) if positional.empty?
          env[name] = positional.shift
        when :optarg
          env[name] =
            positional.any? ? positional.shift : call(param.children.last, env)
        when :kwarg
          env[name] = keywords.fetch(name) { cannot_bind(method) }
        when :kwoptarg
          env[name] = keywords.fetch(name) { call(param.children.last, env) }
        when :restarg
          env[name] = positional.dup if name
          positional.clear
        when :kwrestarg
          env[name] = keywords.except(*declared) if name
        when :blockarg
          nil
        else
          cannot_bind(method)
        end
      end
      cannot_bind(method) if positional.any?

      env
    end

    def cannot_bind(method)
      raise CannotEvaluate, "cannot bind arguments for ##{method.name}"
    end

    def apply(receiver, operator, args)
      result = host_type_query(receiver, operator, args)
      return result unless result.equal?(MISSING)

      unless PURE_METHODS[receiver.class]&.include?(operator)
        raise CannotEvaluate, "#{receiver.class}##{operator}"
      end

      begin
        receiver.public_send(operator, *args)
      rescue StandardError => error
        raise CannotEvaluate,
              "#{receiver.class}##{operator} raises #{error.class}"
      end
    end

    def source(node)
      node.location&.expression&.source || "#{node.type} node"
    end

    # --- Type predicates, answered only when provable. ---

    # On host values: class identity is version-stable, so is_a? checks
    # against known constants answer from the host. Method existence is
    # not version-stable, so respond_to? answers only false, only for
    # 1.9+ targets, and never for names with a removal history.
    def host_type_query(receiver, operator, args)
      return MISSING if receiver.is_a?(ClassReference)

      case operator
      when :is_a?, :kind_of?, :instance_of?
        return MISSING unless args.size == 1 &&
                              args.first.is_a?(ClassReference)

        host_is_a?(receiver, operator, args.first.path)
      when :respond_to?
        return MISSING unless args.size == 1 && args.first.is_a?(Symbol)

        host_responds_false?(receiver, args.first)
      else
        MISSING
      end
    end

    def host_is_a?(receiver, operator, path)
      name = path.sub(/\A::/, '')
      constant = CORE_CONSTANTS[name]
      if constant
        return receiver.instance_of?(constant) if operator == :instance_of?

        receiver.is_a?(constant)
      elsif resolve_class(name)
        # Core values are never instances of project-defined classes.
        # (Project modules could be mixed into core classes by core_ext
        # reopens, so module references stay unanswered.)
        false
      else
        MISSING
      end
    end

    def host_responds_false?(receiver, name)
      return MISSING unless @target&.at_least?('1.9')
      return MISSING if REMOVED_CORE_METHODS.include?(name)

      receiver.respond_to?(name) ? MISSING : false
    end

    # On interpreted instances: ancestry comes from project sources.
    def instance_type_query(operator, args)
      case operator
      when :is_a?, :kind_of?, :instance_of?
        return MISSING unless args.size == 1 &&
                              args.first.is_a?(ClassReference)

        instance_is_a?(operator, args.first.path)
      when :respond_to?
        return MISSING unless args.size == 1 && args.first.is_a?(Symbol)

        # Absence proves nothing: unresolvable modules, superclasses,
        # or method_missing could still answer.
        responds_to?(args.first) ? true : MISSING
      else
        MISSING
      end
    end

    def instance_is_a?(operator, path)
      ref = path.sub(/\A::/, '')
      if operator == :instance_of?
        return true if name_match?(ref, @class_path)

        return reference_kind(ref) == :unknown ? MISSING : false
      end

      chain, complete = ancestry_chain
      return true if chain.any? { |name| name_match?(ref, name) }
      return true if
        @class_node.included_modules.any? { |name| name_match?(ref, name) }

      # Falsity for a class reference needs only a complete superclass
      # chain (modules never add class ancestry). Falsity for a module
      # reference would need complete include knowledge — not modeled.
      return false if reference_kind(ref) == :class && complete

      MISSING
    end

    # The superclass chain as far as project sources prove it, ending
    # with Object's host ancestry when the chain provably ends at
    # implicit Object. The flag is false when any link is unresolvable,
    # conflicting, or cyclic.
    def ancestry_chain
      @ancestry_chain ||= build_ancestry_chain
    end

    def build_ancestry_chain
      chain = [@class_path]
      node = @class_node
      path = @class_path
      seen = []
      loop do
        return [chain, false] if node.nil? || seen.include?(path)

        seen << path
        declared = ([node.superclass_name] + recorded_superclasses(path))
          .compact.uniq
        case declared.size
        when 0
          return [chain + %w[Object Kernel BasicObject], true]
        when 1
          name = declared.first
          constant = CORE_CONSTANTS[name]
          if constant.is_a?(Class)
            return [chain + constant.ancestors.map(&:to_s), true]
          end

          chain << name
          path = name
          node = resolve_class(name)
        else
          return [chain, false]
        end
      end
    end

    def recorded_superclasses(path)
      @sources ? @sources.superclass_names(path) : []
    end

    # A written reference matches a known name when they're identical
    # or one is a trailing qualification of the other; bare basenames
    # only count when the project has exactly one class by that name,
    # since the lexical resolution is otherwise ambiguous.
    def name_match?(ref, name)
      return false if name.nil?
      return true if ref == name
      return true if name.end_with?("::#{ref}") && unambiguous?(ref)

      ref.end_with?("::#{name}")
    end

    def unambiguous?(ref)
      return true if ref.include?('::')

      @sources ? @sources.unique_class_basename?(ref) : true
    end

    def reference_kind(ref)
      constant = CORE_CONSTANTS[ref]
      return constant.is_a?(Class) ? :class : :module if constant
      return :unknown unless unambiguous?(ref)

      return :class if resolve_class(ref)
      return :module if resolve_module(ref)

      :unknown
    end

    # Whether the resolution chain can see a definition for name,
    # proving respond_to? true.
    def responds_to?(name)
      return false unless @class_node

      writer = name.to_s.end_with?('=') ? name.to_s.chomp('=').to_sym : nil
      !!(@class_node.lookup_method(name) ||
         @class_node.attr_readers.include?(name) ||
         @class_node.data_members.include?(name) ||
         (writer && @class_node.attr_writers.include?(writer)) ||
         included_module_method(name) ||
         @model_attributes&.column?(name) ||
         (writer && @model_attributes&.column?(writer)))
    end
  end
end

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
        last reverse sort min max
        sum uniq compact flatten include? index join slice take drop
        to_a inspect
      ],
      Hash => %i[== != nil? [] []= store delete fetch length size empty?
                 keys values invert merge include? key? has_key?
                 has_value? value? to_a inspect],
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

    def self.call(node, env)
      new.call(node, env)
    end

    def initialize(class_node: nil, model_attributes: nil)
      @class_node = class_node
      @model_attributes = model_attributes
      @ivars = {}
      @constants = {}
      @resolving = []
      @depth = 0
    end

    # Interprets the class's initialize method (if any) to populate
    # instance state, using the given argument values.
    def run_initialize(args, keywords = {})
      init = @class_node&.lookup_method(:initialize)
      invoke(init, args, keywords) if init
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
        return invoke_sibling(node, operator, args)
      end

      receiver = call(receiver_node, env)
      apply(receiver, operator, args)
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

    def invoke_sibling(node, operator, args)
      method = @class_node&.lookup_method(operator)
      return invoke(method, args) if method

      attr_access(node, operator, args)
    end

    # Falls back to attr_reader/attr_writer-declared accessors and
    # schema-declared model attributes, which have no def to interpret.
    def attr_access(node, operator, args)
      raise CannotEvaluate, source(node) unless @class_node

      if args.empty?
        if @class_node.attr_readers.include?(operator) ||
           @class_node.data_members.include?(operator)
          return @ivars[:"@#{operator}"]
        end
        if @model_attributes&.column?(operator)
          return @model_attributes.read(operator)
        end
      end

      if operator.to_s.end_with?('=') && args.size == 1
        attr = operator.to_s.chomp('=').to_sym
        if @class_node.attr_writers.include?(attr)
          return @ivars[:"@#{attr}"] = args.first
        end
        if @model_attributes&.column?(attr)
          return @model_attributes.write(attr, args.first)
        end
      end

      raise CannotEvaluate, source(node)
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
          env[name] = {} if name
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
  end
end

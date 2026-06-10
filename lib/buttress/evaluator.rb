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
      Array => %i[
        + - * & | == != nil? length size empty? first last reverse sort
        min max
        sum uniq compact flatten include? index join slice take drop
        to_a inspect
      ],
      Hash => %i[== != nil? length size empty? keys values invert merge
                 include? key? has_key? has_value? value? to_a inspect],
    }.freeze

    # Interpreted sibling calls deeper than this are assumed to be
    # runaway recursion.
    MAX_DEPTH = 50

    def self.call(node, env)
      new.call(node, env)
    end

    def initialize(class_node: nil)
      @class_node = class_node
      @ivars = {}
      @depth = 0
    end

    # Interprets the class's initialize method (if any) to populate
    # instance state, using the given argument values.
    def run_initialize(args)
      init = @class_node&.lookup_method(:initialize)
      invoke(init, args) if init
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
      when :begin
        node.children.map { |child| call(child, env) }.last
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

    def evaluate_send(node, env)
      receiver_node, operator, *arg_nodes = node.children
      args = arg_nodes.map { |arg_node| call(arg_node, env) }

      if receiver_node.nil? || receiver_node.type == :self
        return invoke_sibling(node, operator, args)
      end

      receiver = call(receiver_node, env)
      apply(receiver, operator, args)
    end

    def invoke_sibling(node, operator, args)
      method = @class_node&.lookup_method(operator)
      raise CannotEvaluate, source(node) unless method

      invoke(method, args)
    end

    def invoke(method, args)
      @depth += 1
      raise CannotEvaluate, "recursion in ##{method.name}" if @depth > MAX_DEPTH

      catch(:method_return) do
        body = method.children.last
        body ? call(body, bind_params(method, args)) : nil
      end
    ensure
      @depth -= 1
    end

    def bind_params(method, args)
      params = method.args
      unless params.size == args.size &&
             params.all? { |param| param.type == :arg }
        raise CannotEvaluate, "cannot bind arguments for ##{method.name}"
      end

      params.zip(args).to_h { |param, value| [param.name, value] }
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

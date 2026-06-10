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
        + * == != < > <= >= <=> length size empty? upcase downcase
        capitalize swapcase reverse strip lstrip rstrip chomp chop squeeze
        include? start_with? end_with? index rindex sub gsub tr delete
        count split chars succ next center ljust rjust slice
        to_s to_i to_f to_sym inspect
      ],
      Integer => %i[
        + - * / % ** == != < > <= >= <=> abs ceil floor round truncate
        succ next pred divmod gcd lcm digits
        zero? positive? negative? even? odd?
        to_s to_i to_f to_r inspect
      ],
      Float => %i[
        + - * / % ** == != < > <= >= <=> abs ceil floor round truncate
        zero? positive? negative? nan? infinite? finite?
        to_s to_i to_f to_r inspect
      ],
      Symbol => %i[== != <=> length size upcase downcase capitalize succ
                   next to_s to_sym inspect],
      NilClass => %i[== != nil? to_s to_a to_i inspect],
      TrueClass => %i[== != & | ^ to_s inspect],
      FalseClass => %i[== != & | ^ to_s inspect],
      Array => %i[
        + - * & | == != length size empty? first last reverse sort min max
        sum uniq compact flatten include? index join slice take drop
        to_a inspect
      ],
      Hash => %i[== != length size empty? keys values invert merge
                 include? key? has_key? has_value? value? to_a inspect],
    }.freeze

    def self.call(node, env)
      new.call(node, env)
    end

    def call(node, env)
      case node.type
      when :true then true
      when :false then false
      when :nil then nil
      when :int, :float, :str, :sym then node.children.last
      when :lvar then fetch(node, env)
      when :send then evaluate_send(node, env)
      when :begin
        node.children.map { |child| call(child, env) }.last
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
      raise CannotEvaluate, source(node) if receiver_node.nil?

      receiver = call(receiver_node, env)
      args = arg_nodes.map { |arg_node| call(arg_node, env) }
      apply(receiver, operator, args)
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

module Buttress
  # A branch condition along an execution path, with the polarity needed
  # to take that path. Acts as the tier-one constraint solver: picks
  # argument values that satisfy (or violate) the condition.
  class Predicate
    COMPARISON_NEGATIONS = {
      :== => :'!=',
      :'!=' => :==,
      :> => :<=,
      :>= => :<,
      :< => :>=,
      :<= => :>,
    }.freeze

    QUERY_STATES = { empty?: 'empty', nil?: 'nil' }.freeze

    # Returned by solvers when any default argument value satisfies the
    # predicate (defaults are non-nil, non-empty strings).
    UNCONSTRAINED = Object.new.freeze

    attr_reader :node, :polarity

    def initialize(node, polarity)
      @node = node
      @polarity = polarity
    end

    def description
      case form
      when :truthiness
        "#{name} is #{polarity}"
      when :comparison
        op = polarity ? operator : COMPARISON_NEGATIONS.fetch(operator)
        "#{name} #{op} #{literal.inspect}"
      when :query
        state = QUERY_STATES.fetch(operator)
        "#{name} is #{polarity ? state : "not #{state}"}"
      when :unsupported
        polarity ? source : "!(#{source})"
      end
    end

    def bindings
      return {} unless solvable?

      value = solve
      UNCONSTRAINED.equal?(value) ? {} : { name => value }
    end

    def solvable?
      form != :unsupported
    end

    # The named value the predicate tests — the variable a solvable
    # form constrains, or (for unsupported forms like items.any?) the
    # reference the failure-driven search may try to assign. Nil when
    # the condition reads no direct reference.
    def variable_name
      name
    end

    def source
      cleaned = node.location&.expression&.source&.gsub("'", '"')
      cleaned || "(#{node.type})"
    end

    private

    def form
      @form ||= detect_form
    end

    def detect_form
      return :truthiness if reference?(node)

      if node.type == :send && reference?(node.children.first)
        return :comparison if comparison?
        return :query if QUERY_STATES.key?(operator) && node.children[2].nil?
      end

      :unsupported
    end

    # A node that reads a named value: a local variable, or a
    # receiverless zero-arg call (a model attribute or method).
    def reference?(target)
      !reference_name(target).nil?
    end

    def reference_name(target)
      return nil unless target.is_a?(Parser::AST::Node)

      case target.type
      when :lvar then target.children.last
      when :send
        receiver, message, *args = target.children
        message if receiver.nil? && args.empty?
      end
    end

    def comparison?
      return false unless COMPARISON_NEGATIONS.key?(operator) && literal_node

      # Ordered comparisons are only solvable against integers.
      %i[== !=].include?(operator) || literal.is_a?(Integer)
    end

    def literal_node
      arg = node.children[2]
      arg if arg && [:int, :str].include?(arg.type)
    end

    def solve
      case form
      when :truthiness then polarity
      when :comparison then solve_comparison
      when :query then solve_query
      end
    end

    # Boundary values: the smallest move that crosses the comparison.
    def solve_comparison
      case operator
      when :== then polarity ? literal : other_value
      when :'!=' then polarity ? other_value : literal
      when :> then polarity ? literal + 1 : literal
      when :>= then polarity ? literal : literal - 1
      when :< then polarity ? literal - 1 : literal
      when :<= then polarity ? literal : literal + 1
      end
    end

    def other_value
      literal.is_a?(Integer) ? literal + 1 : "not #{literal}"
    end

    def solve_query
      case operator
      when :empty? then polarity ? '' : UNCONSTRAINED
      when :nil? then polarity ? nil : UNCONSTRAINED
      end
    end

    def name
      reference_name(node) || reference_name(node.children.first)
    end

    def operator
      node.children[1]
    end

    def literal
      literal_node.children.last
    end
  end
end

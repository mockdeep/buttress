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
      end
    end

    def bindings
      value = solve
      UNCONSTRAINED.equal?(value) ? {} : { name => value }
    end

    private

    def form
      @form ||= detect_form
    end

    def detect_form
      return :truthiness if node.type == :lvar

      if node.type == :send && node.children.first&.type == :lvar
        return :comparison if COMPARISON_NEGATIONS.key?(operator) && literal_node
        return :query if QUERY_STATES.key?(operator) && node.children[2].nil?
      end

      raise Error, "cannot solve predicate of type #{node.type}"
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

    def solve_comparison
      case operator
      when :== then polarity ? literal : other_value
      when :'!=' then polarity ? other_value : literal
      else solve_ordered
      end
    end

    # Boundary values: the smallest move that crosses the comparison.
    def solve_ordered
      unless literal.is_a?(Integer)
        raise Error,
              "cannot solve predicate: #{name} #{operator} #{literal.inspect}"
      end

      case operator
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
      node.type == :lvar ? node.children.last : node.children.first.children.last
    end

    def operator
      node.children[1]
    end

    def literal
      literal_node.children.last
    end
  end
end

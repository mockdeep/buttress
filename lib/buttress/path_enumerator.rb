module Buttress
  # Walks a method body and enumerates every execution path through it.
  # Each path carries an ordered list of steps — intermediate statements
  # and branch predicates, in the order execution encounters them — plus
  # the expression whose value the method returns on that path (nil when
  # the path falls off the end of the method). Step order matters:
  # predicates must be checked against the environment as it was at the
  # branch point, not at the end of the path.
  class PathEnumerator
    Path = Struct.new(:steps, :return_node) do
      def predicates
        steps.grep(Predicate)
      end

      def statements
        steps.reject { |step| step.is_a?(Predicate) }
      end
    end

    def self.call(body_node)
      new.call(body_node)
    end

    def call(body_node)
      walk(statements(body_node), [])
    end

    private

    def statements(node)
      return [] if node.nil?

      node.type == :begin ? node.children : [node]
    end

    def walk(stmts, steps)
      stmt, *rest = stmts

      case stmt&.type
      when nil
        [Path.new(steps, nil)]
      when :if
        cond, then_branch, else_branch = stmt.children
        split(cond, then_branch, else_branch, rest, steps)
      when :case
        subject, *whens, else_body = stmt.children
        case_paths(subject, whens, else_body, rest, steps)
      when :return
        return_paths(stmt.children.first, steps)
      else
        rest.empty? ? return_paths(stmt, steps) : walk(rest, steps + [stmt])
      end
    end

    # Splits a return-position && / || by short-circuit semantics: each
    # operand that can decide the expression's value gets its own path,
    # ending with a polarity predicate on that operand and the operand
    # itself as the return node (the replay reuses the predicate's
    # value rather than evaluating the node twice — see
    # Condition#return_value_for). The last operand is returned
    # unconstrained: a guard idiom's right side (x && x.name) is a
    # value, not a branch, and a comparison-family right side gets its
    # outcomes from tier-3b.
    def return_paths(node, steps)
      inner = strip(node)
      unless inner.is_a?(Parser::AST::Node) && %i[and or].include?(inner.type)
        return [Path.new(steps, node)]
      end

      left, right = inner.children
      if inner.type == :and
        deciding_paths(left, false, steps) +
          passing_steps(left, true, steps)
            .flat_map { |passed| return_paths(right, passed) }
      else
        deciding_paths(left, true, steps) +
          passing_steps(left, false, steps)
            .flat_map { |passed| return_paths(right, passed) }
      end
    end

    # Paths where `node` evaluates with the given truthiness and its
    # value is what the enclosing expression returns.
    def deciding_paths(node, polarity, steps)
      node = strip(node)
      case node.type
      when :and
        left, right = node.children
        compound = passing_steps(left, true, steps)
          .flat_map { |passed| deciding_paths(right, polarity, passed) }
        polarity ? compound : deciding_paths(left, false, steps) + compound
      when :or
        left, right = node.children
        compound = passing_steps(left, false, steps)
          .flat_map { |passed| deciding_paths(right, polarity, passed) }
        polarity ? deciding_paths(left, true, steps) + compound : compound
      else
        [Path.new(with(steps, node, polarity), node)]
      end
    end

    # Step lists after which `node` has evaluated with the given
    # truthiness without deciding the enclosing expression's value.
    def passing_steps(node, polarity, steps)
      node = strip(node)
      case node.type
      when :and
        left, right = node.children
        compound = passing_steps(left, true, steps)
          .flat_map { |passed| passing_steps(right, polarity, passed) }
        polarity ? compound : passing_steps(left, false, steps) + compound
      when :or
        left, right = node.children
        compound = passing_steps(left, false, steps)
          .flat_map { |passed| passing_steps(right, polarity, passed) }
        polarity ? passing_steps(left, true, steps) + compound : compound
      else
        [with(steps, node, polarity)]
      end
    end

    # Unwraps parenthesized expressions: (a && b) parses as a begin
    # node around the operator.
    def strip(node)
      while node.is_a?(Parser::AST::Node) && node.type == :begin &&
            node.children.size == 1
        node = node.children.first
      end
      node
    end

    # Splits a branch condition into paths, decomposing && and || by
    # their short-circuit semantics.
    def split(cond, then_branch, else_branch, rest, steps)
      case cond.type
      when :begin
        split(cond.children.first, then_branch, else_branch, rest, steps)
      when :and
        left, right = cond.children
        split(right, then_branch, else_branch, rest,
              with(steps, left, true)) +
          branch_paths(else_branch, rest, with(steps, left, false))
      when :or
        left, right = cond.children
        branch_paths(then_branch, rest, with(steps, left, true)) +
          split(right, then_branch, else_branch, rest,
                with(steps, left, false))
      else
        branch_paths(then_branch, rest, with(steps, cond, true)) +
          branch_paths(else_branch, rest, with(steps, cond, false))
      end
    end

    # Desugars case/when into equality predicates on the subject.
    def case_paths(subject, whens, else_body, rest, steps)
      return branch_paths(else_body, rest, steps) if whens.empty?

      first, *remaining = whens
      *values, body = first.children

      matched = values.flat_map do |value|
        branch_paths(body, rest, with(steps, equality(subject, value), true))
      end
      unmatched = values.reduce(steps) do |acc, value|
        with(acc, equality(subject, value), false)
      end

      matched + case_paths(subject, remaining, else_body, rest, unmatched)
    end

    def equality(subject, value)
      Parser::AST::Node.new(:send, [subject, :==, value])
    end

    def with(steps, node, polarity)
      steps + [Predicate.new(node, polarity)]
    end

    def branch_paths(branch, rest, steps)
      walk(statements(branch) + rest, steps)
    end
  end
end

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
        [Path.new(steps, stmt.children.first)]
      else
        rest.empty? ? [Path.new(steps, stmt)] : walk(rest, steps + [stmt])
      end
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

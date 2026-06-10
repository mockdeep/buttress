module Buttress
  # Walks a method body and enumerates every execution path through it.
  # Each path carries the branch predicates that must hold to reach it,
  # the intermediate statements it executes along the way (assignments
  # and the like), and the expression whose value the method returns on
  # that path (nil when the path falls off the end of the method).
  class PathEnumerator
    Path = Struct.new(:predicates, :statements, :return_node)

    def self.call(body_node)
      new.call(body_node)
    end

    def call(body_node)
      walk(statements(body_node), [], [])
    end

    private

    def statements(node)
      return [] if node.nil?

      node.type == :begin ? node.children : [node]
    end

    def walk(stmts, predicates, collected)
      stmt, *rest = stmts

      case stmt&.type
      when nil
        [Path.new(predicates, collected, nil)]
      when :if
        cond, then_branch, else_branch = stmt.children
        split(cond, then_branch, else_branch, rest, predicates, collected)
      when :case
        subject, *whens, else_body = stmt.children
        case_paths(subject, whens, else_body, rest, predicates, collected)
      when :return
        [Path.new(predicates, collected, stmt.children.first)]
      else
        if rest.empty?
          [Path.new(predicates, collected, stmt)]
        else
          walk(rest, predicates, collected + [stmt])
        end
      end
    end

    # Splits a branch condition into paths, decomposing && and || by
    # their short-circuit semantics.
    def split(cond, then_branch, else_branch, rest, predicates, collected)
      case cond.type
      when :begin
        split(cond.children.first, then_branch, else_branch, rest,
              predicates, collected)
      when :and
        left, right = cond.children
        split(right, then_branch, else_branch, rest,
              with(predicates, left, true), collected) +
          branch_paths(else_branch, rest, with(predicates, left, false),
                       collected)
      when :or
        left, right = cond.children
        branch_paths(then_branch, rest, with(predicates, left, true),
                     collected) +
          split(right, then_branch, else_branch, rest,
                with(predicates, left, false), collected)
      else
        branch_paths(then_branch, rest, with(predicates, cond, true),
                     collected) +
          branch_paths(else_branch, rest, with(predicates, cond, false),
                       collected)
      end
    end

    # Desugars case/when into equality predicates on the subject.
    def case_paths(subject, whens, else_body, rest, predicates, collected)
      if whens.empty?
        return branch_paths(else_body, rest, predicates, collected)
      end

      first, *remaining = whens
      *values, body = first.children

      matched = values.flat_map do |value|
        branch_paths(body, rest,
                     with(predicates, equality(subject, value), true),
                     collected)
      end
      unmatched = values.reduce(predicates) do |preds, value|
        with(preds, equality(subject, value), false)
      end

      matched + case_paths(subject, remaining, else_body, rest, unmatched,
                           collected)
    end

    def equality(subject, value)
      Parser::AST::Node.new(:send, [subject, :==, value])
    end

    def with(predicates, node, polarity)
      predicates + [Predicate.new(node, polarity)]
    end

    def branch_paths(branch, rest, predicates, collected)
      walk(statements(branch) + rest, predicates, collected)
    end
  end
end

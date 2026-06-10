module Buttress
  # Walks a method body and enumerates every execution path through it.
  # Each path carries the branch predicates that must hold to reach it and
  # the expression whose value the method returns on that path (nil when
  # the path falls off the end of the method).
  class PathEnumerator
    Path = Struct.new(:predicates, :return_node)

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

    def walk(stmts, predicates)
      stmt, *rest = stmts

      case stmt&.type
      when nil
        [Path.new(predicates, nil)]
      when :if
        cond, then_branch, else_branch = stmt.children
        branch_paths(then_branch, rest, predicates, cond, true) +
          branch_paths(else_branch, rest, predicates, cond, false)
      when :return
        [Path.new(predicates, stmt.children.first)]
      else
        rest.empty? ? [Path.new(predicates, stmt)] : walk(rest, predicates)
      end
    end

    def branch_paths(branch, rest, predicates, cond, polarity)
      extended = predicates + [Predicate.new(cond, polarity)]
      walk(statements(branch) + rest, extended)
    end
  end
end

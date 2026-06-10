module Buttress
  # A branch condition along an execution path, with the polarity needed
  # to take that path. Knows how to pick argument values that satisfy it.
  class Predicate
    attr_reader :node, :polarity

    def initialize(node, polarity)
      @node = node
      @polarity = polarity
    end

    def description
      "#{name} is #{polarity}"
    end

    def bindings
      { name => polarity }
    end

    private

    def name
      unless node.type == :lvar
        raise Error, "cannot solve predicate of type #{node.type}"
      end

      node.children.last
    end
  end
end

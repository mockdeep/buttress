module Buttress
  # A symbolic stand-in for a class or module named by a constant the
  # evaluator can't resolve to a value. Supports equality (by path) and
  # renders as its own source text; calling methods on it degrades to a
  # skip. Equality is textual, so two different paths naming the same
  # class compare unequal — a deliberate, conservative simplification.
  class ClassReference
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def ==(other)
      other.is_a?(ClassReference) && other.path == path
    end
    alias eql? ==

    def hash
      path.hash
    end

    def inspect
      path
    end
  end
end

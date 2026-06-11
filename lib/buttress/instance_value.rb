module Buttress
  # An interpreted instance of an analyzed class: the constructor
  # inputs that built it and the instance state interpretation
  # produced. Holds only plain values (no AST references), so it
  # survives the Marshal deep-dup at the replay boundary. Renders as
  # its own constructor call, so the generated test builds the same
  # instance the evaluator reasoned about.
  class InstanceValue
    attr_reader :class_path, :positional, :keywords, :ivars

    def initialize(class_path:, positional: [], keywords: {}, ivars: {})
      @class_path = class_path
      @positional = positional
      @keywords = keywords
      @ivars = ivars
    end

    def render
      args = positional.map { |value| Literal.render(value) } +
             keywords.map { |name, value| "#{name}: #{Literal.render(value)}" }
      return "#{class_path}.new" if args.empty?

      "#{class_path}.new(#{args.join(', ')})"
    end

    def inspect
      render
    end
  end
end

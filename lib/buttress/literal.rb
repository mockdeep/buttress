module Buttress
  # Renders a Ruby value as source code for the generated spec.
  module Literal
    def self.render(value)
      case value
      when String
        "'#{value}'"
      when Buttress::ClassReference
        value.path
      when Buttress::InstanceValue
        value.render
      when Buttress::CycleValue
        # No source expression rebuilds a cycle mid-iteration; a path
        # returning the enumerator itself degrades rather than render
        # something unfaithful.
        raise CannotEvaluate, 'rendering a cycle enumerator'
      else
        value.inspect
      end
    end
  end
end

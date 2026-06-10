module Buttress
  # Renders a Ruby value as source code for the generated spec.
  module Literal
    def self.render(value)
      case value
      when String
        "'#{value}'"
      when Buttress::ClassReference
        value.path
      else
        value.inspect
      end
    end
  end
end

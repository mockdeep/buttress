module Buttress
  # Renders a Ruby value as source code for the generated spec.
  module Literal
    def self.render(value)
      case value
      when String
        "'#{value}'"
      else
        value.inspect
      end
    end
  end
end

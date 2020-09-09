require 'active_support/core_ext/string'
require 'parser/ruby18'

module Buttress
  class Runner
    TEMPLATE = File.read(Pathname.new(__dir__).join('../templates/spec.erb'))

    def self.call(code)
      ast = Parser::Ruby18.parse(code)
      class_node = ast.children.detect { |child| child.type == :const }
      class_name = class_node.children.last

      method_node = ast.children.detect { |child| child && child.type == :def }
      method_name = method_node.children.first
      return_value = method_node.children.last.type
      instance_name = class_name.to_s.underscore

      ERB.new(TEMPLATE).result(binding)
    end
  end
end

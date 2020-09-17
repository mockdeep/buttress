require 'pathname'

module Buttress
  class Composer
    TEMPLATE = File.read(Pathname.new(__dir__).join('../templates/spec.erb'))

    def self.call(*args)
      new.call(*args)
    end

    def call(code, class_name, method_name)
      root_node = RootNode.new(Parser::Ruby18.parse(code))
      flow_tree = FlowTree.new(
        root_node,
        class_name: class_name,
        method_name: method_name,
      )

      ERB.new(TEMPLATE, nil, '-').result(binding)
    end
  end
end

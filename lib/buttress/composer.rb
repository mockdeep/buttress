require 'erb'
require 'pathname'

module Buttress
  class Composer
    TEMPLATE = File.read(Pathname.new(__dir__).join('../templates/spec.erb'))

    def self.call(*args, **kwargs)
      new.call(*args, **kwargs)
    end

    def call(code, class_name, method_name, target: Target.default)
      root_node = RootNode.new(target.parse(code))
      flow_tree = FlowTree.new(
        root_node,
        class_name: class_name,
        method_name: method_name,
      )

      ERB.new(TEMPLATE, trim_mode: '-').result(binding)
    end
  end
end

require 'erb'
require 'pathname'

module Buttress
  class Composer
    TEMPLATE = File.read(Pathname.new(__dir__).join('../templates/spec.erb'))
    CLASS_TEMPLATE =
      File.read(Pathname.new(__dir__).join('../templates/class_spec.erb'))

    def self.call(*args, **kwargs)
      new.call(*args, **kwargs)
    end

    # With a method name, generates a spec for that one method; without,
    # generates a spec covering every public instance method.
    def call(code, class_name, method_name = nil, target: Target.default,
             schema: nil)
      root_node = RootNode.new(target.parse(code))
      flow_trees = method_names(root_node, class_name, method_name).map do |name|
        FlowTree.new(
          root_node,
          class_name: class_name,
          method_name: name,
          target: target,
          schema: schema,
        )
      end

      if method_name
        flow_tree = flow_trees.first
        ERB.new(TEMPLATE, trim_mode: '-').result(binding)
      else
        ERB.new(CLASS_TEMPLATE, trim_mode: '-').result(binding)
      end
    end

    private

    def method_names(root_node, class_name, method_name)
      return [method_name] if method_name

      root_node.find_class(class_name).public_method_names
    end
  end
end

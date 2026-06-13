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

    # With a method name, generates a spec for that one method
    # (singleton: true for a class-level method); without, generates a
    # spec covering every public instance and singleton method.
    def call(code, class_name, method_name = nil, target: Target.default,
             schema: nil, sources: nil, singleton: false)
      root_node = RootNode.new(target.parse(code))
      entries = method_entries(root_node, class_name, method_name, singleton)
      flow_trees = entries.map do |name, singleton_method|
        FlowTree.new(
          root_node,
          class_name: class_name,
          method_name: name,
          target: target,
          schema: schema,
          sources: sources,
          singleton: singleton_method,
        )
      end

      if method_name
        flow_tree = flow_trees.first
        ERB.new(TEMPLATE, trim_mode: '-').result(binding)
      else
        # A def always yields at least one flow (a skipped path still
        # renders a skeleton), but a reader's flows are filtered — an
        # empty tree would render an empty describe block, and a class
        # with nothing left (a reader-only Data class whose members all
        # echo their inputs) has no spec worth writing.
        flow_trees = flow_trees.select { |tree| tree.flows.any? }
        if flow_trees.empty?
          raise Buttress::Error, "nothing to assert: #{class_name}"
        end

        ERB.new(CLASS_TEMPLATE, trim_mode: '-').result(binding)
      end
    end

    private

    # [name, singleton?] pairs to generate flows for: instance methods
    # and macro readers, then class-level methods. A module contributes
    # only its singleton methods — its instance methods have no
    # constructible receiver (they're reachable as mixins instead).
    def method_entries(root_node, class_name, method_name, singleton)
      return [[method_name, singleton]] if method_name

      class_node = root_node.find_class_or_module(class_name)
      singleton_entries =
        class_node.public_singleton_method_names.map { |name| [name, true] }
      return singleton_entries if class_node.module?

      instance_names =
        class_node.public_method_names + class_node.public_reader_names
      instance_names.map { |name| [name, false] } + singleton_entries
    end
  end
end

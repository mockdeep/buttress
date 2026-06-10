module Buttress
  class Flow
    attr_accessor :condition, :parent

    extend Forwardable
    delegate [:description, :method_call, :return_value, :skip_reason] =>
      :condition
    delegate [:class_name, :instance_name, :target] => :parent

    def initialize(condition, parent:)
      self.condition = condition
      self.parent = parent
    end

    def constructor_call
      args = constructor_arguments
      return "#{class_name}.new" if args.empty?

      "#{class_name}.new(#{args.join(', ')})"
    end

    private

    def constructor_arguments
      if condition.model?
        condition.constructor_attributes.map do |name, value|
          target.hash_pair(name, Buttress::Literal.render(value))
        end
      else
        condition.constructor_values.map do |value|
          Buttress::Literal.render(value)
        end
      end
    end
  end

  class FlowTree
    attr_accessor :root_node, :class_name, :method_name, :target, :schema

    extend Forwardable
    delegate [:instance_name] => :class_node

    def initialize(root_node, class_name:, method_name:, target:, schema: nil)
      self.root_node = root_node
      self.class_name = class_name
      self.method_name = method_name
      self.target = target
      self.schema = schema
    end

    def flows
      method_node.conditions(schema).map do |condition|
        Flow.new(condition, parent: self)
      end
    end

    def class_node
      @class_node ||= root_node.find_class(class_name)
    end

    def method_node
      @method_node ||= class_node.find_method(method_name)
    end
  end
end

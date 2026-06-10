module Buttress
  class Flow
    attr_accessor :condition, :parent

    extend Forwardable
    delegate [:description, :method_call, :return_value, :skip_reason] =>
      :condition
    delegate [:class_name, :instance_name] => :parent

    def initialize(condition, parent:)
      self.condition = condition
      self.parent = parent
    end

    def constructor_call
      args = condition.constructor_values
      return "#{class_name}.new" if args.empty?

      rendered = args.map { |value| Buttress::Literal.render(value) }
      "#{class_name}.new(#{rendered.join(', ')})"
    end
  end

  class FlowTree
    attr_accessor :root_node, :class_name, :method_name

    extend Forwardable
    delegate [:instance_name] => :class_node

    def initialize(root_node, class_name:, method_name:)
      self.root_node = root_node
      self.class_name = class_name
      self.method_name = method_name
    end

    def flows
      method_node.conditions.map do |condition|
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

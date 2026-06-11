module Buttress
  class Flow
    attr_accessor :condition, :parent

    extend Forwardable
    delegate [:description, :return_value, :skip_reason] => :condition
    delegate [:class_name, :instance_name, :target, :method_name] => :parent

    def initialize(condition, parent:)
      self.condition = condition
      self.parent = parent
    end

    def method_call
      arguments = method_arguments
      return method_name.to_s if arguments.empty?

      "#{method_name}(#{arguments.join(', ')})"
    end

    def constructor_call
      args = constructor_arguments
      return "#{class_name}.new" if args.empty?

      "#{class_name}.new(#{args.join(', ')})"
    end

    private

    def method_arguments
      positional = condition.method_positional_values.map do |value|
        Buttress::Literal.render(value)
      end
      positional + rendered_pairs(condition.method_keyword_values)
    end

    def constructor_arguments
      if condition.model?
        rendered_pairs(condition.constructor_attributes)
      else
        positional = condition.constructor_values.map do |value|
          Buttress::Literal.render(value)
        end
        positional + rendered_pairs(condition.constructor_keywords)
      end
    end

    def rendered_pairs(keywords)
      keywords.map do |name, value|
        target.hash_pair(name, Buttress::Literal.render(value))
      end
    end
  end

  class FlowTree
    attr_accessor :root_node, :class_name, :method_name, :target, :schema,
                  :sources

    extend Forwardable
    delegate [:instance_name] => :class_node

    def initialize(root_node, class_name:, method_name:, target:,
                   schema: nil, sources: nil)
      self.root_node = root_node
      self.class_name = class_name
      self.method_name = method_name
      self.target = target
      self.schema = schema
      self.sources = sources
    end

    def flows
      conditions = method_node.conditions(
        schema, sources: sources, class_name: class_name,
      )
      conditions.map { |condition| Flow.new(condition, parent: self) }
    end

    def class_node
      @class_node ||= root_node.find_class(class_name)
    end

    def method_node
      @method_node ||= class_node.find_method(method_name)
    end
  end
end

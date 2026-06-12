module Buttress
  class Flow
    attr_accessor :condition, :parent

    extend Forwardable
    delegate [:description, :return_value, :skip_reason,
              :type_assertion_class] => :condition
    delegate [:class_name, :instance_name, :target, :method_name,
              :singleton] => :parent

    def initialize(condition, parent:)
      self.condition = condition
      self.parent = parent
    end

    def method_call
      arguments = method_arguments
      return method_name.to_s if arguments.empty?

      "#{method_name}(#{arguments.join(', ')})"
    end

    # The expression under test: a singleton method is called on the
    # class itself, an instance method on the constructed instance.
    def subject
      receiver = singleton ? class_name : instance_name
      "#{receiver}.#{method_call}"
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
                  :sources, :singleton

    extend Forwardable
    delegate [:instance_name] => :class_node

    def initialize(root_node, class_name:, method_name:, target:,
                   schema: nil, sources: nil, singleton: false)
      self.root_node = root_node
      self.class_name = class_name
      self.method_name = method_name
      self.target = target
      self.schema = schema
      self.sources = sources
      self.singleton = singleton
    end

    def flows
      @flows ||= begin
        conditions = method_node.conditions(
          schema, sources: sources, class_name: class_name, target: target,
          singleton: singleton,
        )
        conditions = conditions.select(&:informative_reader?) if reader?
        conditions
          .flat_map(&:variants)
          .map { |condition| Flow.new(condition, parent: self) }
      end
    end

    # The describe label: '.method' for a singleton method, '#method'
    # for an instance method.
    def method_label
      "#{singleton ? '.' : '#'}#{method_name}"
    end

    def class_node
      @class_node ||= root_node.find_class(class_name)
    end

    def method_node
      @method_node ||=
        if singleton
          class_node.lookup_singleton_method(method_name) ||
            raise(Buttress::Error, "method not found: .#{method_name}")
        else
          class_node.lookup_method(method_name) ||
            reader_method_node ||
            raise(Buttress::Error, "method not found: ##{method_name}")
        end
    end

    private

    def reader?
      method_node
      @reader == true
    end

    # Macro readers (Data members, attr_reader) have no def to analyze,
    # but their post-initialize values are still testable: synthesize
    # the ivar read the macro defines and let the standard pipeline
    # solve and render it. Reader conditions are filtered rather than
    # skipped (see Condition#informative_reader?) — a reader is not a
    # source path, so an unemittable one gets no test, never a
    # skeleton.
    def reader_method_node
      return nil unless class_node.publicly_readable?(method_name.to_sym)

      @reader = true
      MethodNode.new(
        target.parse("def #{method_name}\n  @#{method_name}\nend"),
        parent_node: class_node,
      )
    end
  end
end

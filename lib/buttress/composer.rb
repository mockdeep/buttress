require 'pathname'

module Buttress
  class BaseNode
    attr_accessor :raw_node, :parent_node

    def initialize(raw_node, parent_node: nil)
      raise "missing node" unless raw_node
      self.raw_node = raw_node
      self.parent_node = parent_node
    end
  end

  class RootNode < BaseNode
    def find_class(class_name)
      ClassNode.new(find_class_node(raw_node, class_name))
    end

    def find_class_node(node, class_name)
      return unless node
      return node if node.type == :class &&
        node.children.first.children.last.to_s == class_name

      current_node = node
      class_name.split('::').each do |name_part|
        current_node = current_node.children.detect do |child|
          next unless child
          child.type == :class &&
          child.children.first.children.last.to_s == name_part
        end
      end
      current_node
    end
  end

  class ArgumentNode < BaseNode
    attr_accessor :position

    def initialize(raw_node, position)
      super(raw_node)
      self.position = position
    end

    def value
      "blah#{position}"
    end

    def name
      raw_node.children.last
    end
  end

  class MethodNode < BaseNode
    def method_call
      if args.any?
        "#{name}('#{args.map(&:value).join("', '")}')"
      else
        name
      end
    end

    def args
      raw_node.children[1].children.map.with_index do |arg, index|
        ArgumentNode.new(arg, index + 1)
      end
    end

    def name
      raw_node.children.first.to_s
    end

    def return_value
      return_expression = raw_node.children.last
      case return_expression.type
      when :true
        'true'
      when :str
        "'#{return_expression.children.last}'"
      when :int
        return_expression.children.last.to_s
      when :lvar
        "'#{find_arg(return_expression.children.last).value}'"
      when :send
        receiver, operator, param = return_expression.children
        arg = find_arg(receiver.children.last)
        "'#{arg.value.send(operator, param.children.last)}'"
      else
        binding.irb
        raise "unhandled type: #{return_expression.type}"
      end
    end

    def find_arg(name)
      args.detect { |arg| arg.name == name }
    end

    def return_name
      return_expression = raw_node.children.last
      case return_expression.type
      when :true
        'true'
      when :str
        "'#{return_expression.children.last}'"
      when :int
        return_expression.children.last.to_s
      when :lvar
        return_expression.children.last.to_s
      when :send
        receiver, operator, arg = return_expression.children
        "#{receiver.children.last} #{operator} #{arg.children.last}"
      else
        binding.irb
        raise "unhandled type: #{return_expression.type}"
      end
    end
  end

  class ClassNode < BaseNode
    def find_method(method_name)
      MethodNode.new(find_method_node(raw_node, method_name), parent_node: self)
    end

    def find_method_node(raw_node, method_name)
      raw_node.children.detect do |child_node|
        next unless child_node
        child_node.type == :def ||
          child_node.type == :begin && find_method_node(child_node, method_name)
      end
    end

    def name
      raw_node.children.first.children.last.to_s
    end

    def instance_name
      name.underscore.split('/').last
    end
  end

  class Composer
    TEMPLATE = File.read(Pathname.new(__dir__).join('../templates/spec.erb'))

    def self.call(*args)
      new.call(*args)
    end

    def call(code, class_name, method_name)
      root_node = RootNode.new(Parser::Ruby18.parse(code))
      class_node = root_node.find_class(class_name)
      method_node = class_node.find_method(method_name)

      ERB.new(TEMPLATE).result(binding)
    end

  end
end

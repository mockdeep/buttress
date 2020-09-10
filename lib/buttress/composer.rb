require 'pathname'

module Buttress
  class Composer
    TEMPLATE = File.read(Pathname.new(__dir__).join('../templates/spec.erb'))

    def self.call(*args)
      new.call(*args)
    end

    def call(code, class_name, method_name)
      ast = Parser::Ruby18.parse(code)
      class_node = find_class_node(ast, class_name)
      method_node = find_method_node(class_node, method_name)

      # need to get a better return value
      return_value = detect_return_value(method_node)
      instance_name = class_name.underscore.split('/').last

      ERB.new(TEMPLATE).result(binding)
    end

    def find_class_node(node, class_name)
      return unless node
      return node if node.type == :module || node.type == :class &&
        node.children.first.children.last.to_s == class_name

      current_node = node
      class_name.split('::').each do |name_part|
        current_node = current_node.children.detect do |child|
          next unless child
          (child.type == :module || child.type == :class) &&
          child.children.first.children.last.to_s == name_part
        end
      end
      current_node
    end

    def find_method_node(node, method_name)
      node.children.detect do |child|
        next unless child
        child.type == :def ||
          child.type == :begin && find_method_node(child, method_name)
      end
    end

    def detect_return_value(method_node)
      # binding.irb
      return_expression = method_node.children.last
      case return_expression.type
      when :true
        'true'
      when :str
        "'#{return_expression.children.last}'"
      else
        raise "unhandled type: #{return_expression.type}"
      end
    end
  end
end

require 'pathname'

module Buttress
  class Composer
    TEMPLATE = File.read(Pathname.new(__dir__).join('../templates/spec.erb'))

    def self.call(*args)
      new.call(*args)
    end

    def call(code, class_name, method_name)
      root_node = RootNode.new(Parser::Ruby18.parse(code))
      class_node = root_node.find_class(class_name)
      method_node = class_node.find_method(method_name)

      ERB.new(TEMPLATE, nil, '-').result(binding)
    end
  end
end

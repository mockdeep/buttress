module Buttress
  class Loader
    def self.call(path, class_and_method)
      code = File.read(path)
      class_name, method_name = class_and_method.split('#')
      [code, class_name, method_name]
    end
  end
end

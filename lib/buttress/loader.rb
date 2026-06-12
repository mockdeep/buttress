module Buttress
  class Loader
    # 'ClassName#method' names an instance method, 'ClassName.method' a
    # singleton method, bare 'ClassName' every public method. Class
    # paths never contain a dot, so the first one splits unambiguously.
    def self.call(path, class_and_method)
      code = File.read(path)
      if class_and_method.include?('#')
        class_name, method_name = class_and_method.split('#')
        [code, class_name, method_name, false]
      else
        class_name, method_name = class_and_method.split('.', 2)
        [code, class_name, method_name, !method_name.nil?]
      end
    end
  end
end

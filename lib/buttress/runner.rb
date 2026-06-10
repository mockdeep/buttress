module Buttress
  class Runner
    def self.call(path, class_and_method, target_version = nil)
      new.call(path, class_and_method, target_version)
    end

    def call(path, class_and_method, target_version = nil)
      target = Target.new(target_version)
      code, class_name, method_name = Loader.call(path, class_and_method)
      test_code = Composer.call(code, class_name, method_name, target: target)
      Writer.call(path, test_code)
    end
  end
end

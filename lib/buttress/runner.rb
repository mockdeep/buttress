require 'active_support/core_ext/string'
require 'parser/ruby18'

module Buttress
  class Runner
    def self.call(path, class_and_method)
      new.call(path, class_and_method)
    end

    def call(path, class_and_method)
      code, class_name, method_name = Loader.call(path, class_and_method)
      test_code = Composer.call(code, class_name, method_name)
      Writer.call(path, test_code)
    end
  end
end

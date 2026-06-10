module Buttress
  class Runner
    def self.call(path, class_and_method, target_version = nil)
      new.call(path, class_and_method, target_version)
    end

    def call(path, class_and_method, target_version = nil)
      target = Target.new(target_version)
      code, class_name, method_name = Loader.call(path, class_and_method)
      test_code = Composer.call(
        code, class_name, method_name,
        target: target, schema: find_schema(path)
      )
      Writer.call(path, test_code)
    end

    private

    # Walks up from the analyzed file looking for a Rails db/schema.rb.
    def find_schema(path)
      dir = File.expand_path(File.dirname(path))
      until dir == File.dirname(dir)
        candidate = File.join(dir, 'db', 'schema.rb')
        return Schema.from_file(candidate) if File.exist?(candidate)

        dir = File.dirname(dir)
      end
      nil
    end
  end
end

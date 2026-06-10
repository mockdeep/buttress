require 'fileutils'
require 'pathname'

module Buttress
  # Writes generated test code to the conventional spec location for the
  # analyzed file: app/models/user.rb becomes spec/models/user_spec.rb.
  class Writer
    PROJECT_MARKERS = ['Gemfile', 'spec', '.git'].freeze
    SOURCE_PREFIXES = %w[app lib].freeze

    def self.call(path, content)
      new.call(path, content)
    end

    def call(path, content)
      spec_path = spec_path_for(path)
      if File.exist?(spec_path)
        raise Error, "refusing to overwrite existing #{spec_path}"
      end

      FileUtils.mkdir_p(File.dirname(spec_path))
      File.write(spec_path, content)
      spec_path
    end

    def spec_path_for(path)
      file = File.expand_path(path)
      root = project_root(file)
      return file.sub(/\.rb\z/, '_spec.rb') unless root

      relative = Pathname.new(file).relative_path_from(Pathname.new(root))
      segments = relative.each_filename.to_a
      segments.shift if SOURCE_PREFIXES.include?(segments.first)

      File.join(root, 'spec', *segments).sub(/\.rb\z/, '_spec.rb')
    end

    private

    def project_root(file)
      dir = File.dirname(file)
      until dir == File.dirname(dir)
        markers = PROJECT_MARKERS.map { |marker| File.join(dir, marker) }
        return dir if markers.any? { |marker| File.exist?(marker) }

        dir = File.dirname(dir)
      end
      nil
    end
  end
end

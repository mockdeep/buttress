module Buttress
  # Resolves constants defined in sibling source files: walks up from
  # the analyzed file to the project root, then parses (never loads)
  # the project's lib/ and app/ trees. Files that don't parse under the
  # target version contribute nothing.
  class Sources
    ROOT_MARKERS = %w[Gemfile .git].freeze
    SOURCE_DIRS = %w[lib app].freeze

    def self.from_file(path, target: Target.default)
      root = find_root(File.expand_path(File.dirname(path)))
      root && new(root, target: target)
    end

    def self.find_root(dir)
      until dir == File.dirname(dir)
        if ROOT_MARKERS.any? { |marker| File.exist?(File.join(dir, marker)) }
          return dir
        end

        dir = File.dirname(dir)
      end
      nil
    end

    def initialize(root, target: Target.default)
      @root = root
      @target = target
    end

    # The named module as a ModuleNode, or nil. Matches the full
    # qualified name or a trailing segment of it, since an include
    # written inside a namespace omits the enclosing modules.
    def find_module(qualified_name)
      name = qualified_name.sub(/\A::/, '')
      node = module_index[name] ||
             module_index.find { |key, _| key.end_with?("::#{name}") }&.last
      node && ModuleNode.new(node)
    end

    private

    def module_index
      @module_index ||= {}.tap do |index|
        source_files.each do |file|
          ast = parse(file)
          collect_modules(ast, [], index) if ast
        end
      end
    end

    def source_files
      SOURCE_DIRS.flat_map do |dir|
        Dir.glob(File.join(@root, dir, '**', '*.rb'))
      end.sort
    end

    def parse(file)
      @target.parse(File.read(file))
    rescue StandardError
      nil
    end

    def collect_modules(node, namespace, index)
      return unless node.is_a?(Parser::AST::Node)

      case node.type
      when :module, :class
        qualified = namespace + const_segments(node.children.first)
        index[qualified.join('::')] ||= node if node.type == :module
        node.children.drop(1).each do |child|
          collect_modules(child, qualified, index)
        end
      else
        node.children.each do |child|
          collect_modules(child, namespace, index)
        end
      end
    end

    def const_segments(node)
      segments = []
      while node.is_a?(Parser::AST::Node) && node.type == :const
        segments.unshift(node.children.last.to_s)
        node = node.children.first
      end
      segments
    end
  end
end

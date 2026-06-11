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
    # qualified name or a trailing segment of it, since a reference
    # written inside a namespace omits the enclosing modules.
    def find_module(qualified_name)
      node = lookup(module_index, qualified_name)
      node && ModuleNode.new(node)
    end

    # The named class as a ClassNode, or nil. Built through the
    # defining file's own RootNode so the class's Data members,
    # constants, and includes resolve in their home context.
    def find_class(qualified_name)
      root = lookup(class_index, qualified_name)
      root && root.lookup_class(qualified_name.split('::').last)
    end

    private

    def lookup(index, qualified_name)
      name = qualified_name.sub(/\A::/, '')
      index[name] ||
        index.find { |key, _| key.end_with?("::#{name}") }&.last
    end

    def module_index
      indexes.first
    end

    def class_index
      indexes.last
    end

    def indexes
      @indexes ||= begin
        modules = {}
        classes = {}
        source_files.each do |file|
          ast = parse(file)
          collect(ast, [], modules, classes, RootNode.new(ast)) if ast
        end
        [modules, classes]
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

    def collect(node, namespace, modules, classes, root)
      return unless node.is_a?(Parser::AST::Node)

      case node.type
      when :module, :class
        qualified = namespace + const_segments(node.children.first)
        key = qualified.join('::')
        modules[key] ||= node if node.type == :module
        classes[key] ||= root if node.type == :class
        node.children.drop(1).each do |child|
          collect(child, qualified, modules, classes, root)
        end
      else
        node.children.each do |child|
          collect(child, namespace, modules, classes, root)
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

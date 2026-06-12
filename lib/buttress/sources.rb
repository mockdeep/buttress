module Buttress
  # Resolves constants defined in sibling source files: walks up from
  # the analyzed file to the project root, then parses (never loads)
  # the project's lib/ and app/ trees. Files that don't parse under the
  # target version contribute nothing.
  class Sources
    ROOT_MARKERS = %w[Gemfile .git].freeze
    SOURCE_DIRS = %w[lib app].freeze

    # One public definition of a method somewhere in the project: the
    # qualified path of the defining class or module, and whether the
    # definition is class-level (:singleton) or an instance method
    # (:instance).
    Definer = Struct.new(:path, :kind) do
      def singleton?
        kind == :singleton
      end
    end

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

    # Superclass names the named class declares across all of its
    # definitions in the project. Empty means no definition we can see
    # declares one — the class's superclass is implicitly Object, as
    # far as the project's own sources are concerned.
    def superclass_names(qualified_name)
      key = qualified_name.sub(/\A::/, '')
      names = superclass_index[key] ||
              superclass_index.find { |k, _| k.end_with?("::#{key}") }&.last
      (names || []).to_a
    end

    # Qualified paths of every class the project defines.
    def class_paths
      class_index.keys
    end

    # Whether exactly one indexed class has this basename. Unqualified
    # references are only trustworthy when the answer is unambiguous.
    def unique_class_basename?(basename)
      class_index.keys.count { |key| key.split('::').last == basename } == 1
    end

    # Every class and module in the project that publicly defines the
    # named method — the duck-type candidate pool for steering values
    # whose defaults don't respond to a method a path needs.
    def definers_of(method_name)
      method_index[method_name.to_sym] || []
    end

    private

    def lookup(index, qualified_name)
      name = qualified_name.sub(/\A::/, '')
      index[name] ||
        index.find { |key, _| key.end_with?("::#{name}") }&.last
    end

    def module_index
      indexes[0]
    end

    def class_index
      indexes[1]
    end

    def superclass_index
      indexes[2]
    end

    def method_index
      indexes[3]
    end

    def indexes
      @indexes ||= begin
        index = { modules: {}, classes: {}, superclasses: {}, methods: {} }
        source_files.each do |file|
          ast = parse(file)
          collect(ast, [], index, RootNode.new(ast)) if ast
        end
        index.values_at(:modules, :classes, :superclasses, :methods)
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

    def collect(node, namespace, index, root)
      return unless node.is_a?(Parser::AST::Node)

      case node.type
      when :module, :class
        qualified = namespace + const_segments(node.children.first)
        key = qualified.join('::')
        index[:modules][key] ||= node if node.type == :module
        if node.type == :class
          index[:classes][key] ||= root
          if node.children[1]
            segments = const_segments(node.children[1])
            # A non-const superclass expression (Struct.new(...)) still
            # disproves "no superclass"; record an unresolvable marker.
            name = segments.any? ? segments.join('::') : '(unresolved)'
            (index[:superclasses][key] ||= []) << name
            index[:superclasses][key].uniq!
          end
        end
        collect_methods(node, key, index)
        node.children.drop(1).each do |child|
          collect(child, qualified, index, root)
        end
      else
        node.children.each do |child|
          collect(child, namespace, index, root)
        end
      end
    end

    # Records the definition's public methods under their names. The
    # node wrappers honor visibility modifiers, so a private def is
    # never offered as a duck-type candidate — a generated test calling
    # it would raise NoMethodError for real.
    def collect_methods(node, key, index)
      wrapper = node.type == :class ? ClassNode.new(node) : ModuleNode.new(node)
      record = lambda do |name, kind|
        definer = Definer.new(key, kind)
        entries = (index[:methods][name] ||= [])
        entries << definer unless entries.include?(definer)
      end
      wrapper.public_method_names.each { |name| record.call(name, :instance) }
      wrapper.public_singleton_method_names.each do |name|
        record.call(name, :singleton)
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

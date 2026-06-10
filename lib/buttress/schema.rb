module Buttress
  # A statically-parsed db/schema.rb: maps table names to their columns
  # and column types, without ever loading Rails or a database.
  class Schema
    COLUMN_TYPES = %i[
      string text integer bigint float decimal boolean
      date datetime time timestamp binary json jsonb
    ].freeze

    def self.from_file(path)
      parse(File.read(path))
    end

    def self.parse(source)
      new(extract_tables(Target.default.parse(source)))
    end

    def self.extract_tables(node, tables = {})
      return tables unless node.is_a?(Parser::AST::Node)

      if node.type == :block && create_table?(node.children.first)
        table_name = node.children.first.children[2].children.last
        tables[table_name] = extract_columns(node.children.last)
      else
        node.children.each { |child| extract_tables(child, tables) }
      end
      tables
    end

    def self.create_table?(send_node)
      send_node.type == :send &&
        send_node.children[1] == :create_table &&
        send_node.children[2]&.type == :str
    end

    def self.extract_columns(body)
      statements = body.nil? ? [] : (body.type == :begin ? body.children : [body])

      statements.each_with_object({}) do |stmt, columns|
        next unless stmt.is_a?(Parser::AST::Node) && stmt.type == :send

        _receiver, message, name_node, *rest = stmt.children
        next unless name_node&.type == :str

        name = name_node.children.last.to_sym
        case message
        when :column
          # Rails 2-era dumps: t.column "name", :string
          type = rest.first
          columns[name] = type.children.last if type&.type == :sym
        when :references, :belongs_to
          columns[:"#{name}_id"] = :integer
        when *COLUMN_TYPES
          columns[name] = message
        end
      end
    end

    def initialize(tables)
      @tables = tables
    end

    def columns_for(class_name)
      @tables[Inflector.tableize(class_name)]
    end
  end
end

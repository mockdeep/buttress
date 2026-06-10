module Buttress
  # Backs ActiveRecord attribute reads and writes during evaluation, and
  # records which attributes the generated test must set at construction
  # time: any attribute the evaluation touches would otherwise be nil in
  # the real test and could steer execution down a different branch.
  class ModelAttributes
    DEFAULTS = {
      string: 'blah',
      text: 'blah',
      integer: 1,
      bigint: 1,
      float: 1.5,
      boolean: false,
    }.freeze

    attr_reader :constructor_values

    def initialize(columns)
      @columns = columns
      @constructor_values = {}
      @current = {}
    end

    def column?(name)
      @columns.key?(name)
    end

    def constrain(name, value)
      @constructor_values[name] = value
      @current[name] = value
    end

    def read(name)
      @current.fetch(name) do
        constrain(name, default_for(name))
        @current[name]
      end
    end

    def write(name, value)
      @current[name] = value
    end

    private

    def default_for(name)
      type = @columns.fetch(name)
      DEFAULTS.fetch(type) do
        raise CannotEvaluate, "no default for #{type} attribute #{name}"
      end
    end
  end
end

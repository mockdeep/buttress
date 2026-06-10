# One execution path through a method, ready to render as a test: the
# argument values that steer execution down the path, the call that
# exercises it, and the value it returns.
class Condition
  attr_accessor :method_node, :path, :schema

  def initialize(method_node, path, schema: nil)
    self.method_node = method_node
    self.path = path
    self.schema = schema
  end

  def description
    base = "returns #{return_name.gsub("'", '"')}"
    return base if path.predicates.empty?

    "#{base} when #{path.predicates.map(&:description).join(' and ')}"
  end

  def return_name
    path.return_node&.location&.expression&.source || 'nil'
  end

  def return_value
    @return_value ||= Buttress::Literal.render(
      evaluator.call(path.return_node || nil_node, env),
    )
  end

  # Values for the method call's required positional parameters.
  def method_positional_values
    method_node.args
      .select { |param| param.type == :arg }
      .map { |param| bindings.fetch(param.name) }
  end

  # Keyword arguments the method call must pass: required keywords
  # always, optional keywords only when a predicate constrains them
  # (otherwise the method's declared default applies).
  def method_keyword_values
    params = method_node.args.select do |param|
      param.type == :kwarg ||
        (param.type == :kwoptarg && constrained_names.include?(param.name))
    end
    params.to_h { |param| [param.name, bindings.fetch(param.name)] }
  end

  # Whether the class under test is a database-backed model.
  def model?
    !columns.nil?
  end

  # Values for initialize's required positional parameters.
  def constructor_values
    @constructor_values ||= constructor_params
      .select { |param| param.type == :arg }
      .map(&:value)
  end

  # Values for initialize's required keyword parameters.
  def constructor_keywords
    @constructor_keywords ||= constructor_params
      .select { |param| param.type == :kwarg }
      .to_h { |param| [param.name, param.value] }
  end

  # Attribute values for instantiating a model. Only meaningful after
  # evaluation has run (skip_reason forces it), since evaluation is what
  # discovers which attributes the test must set.
  def constructor_attributes
    attribute_store.constructor_values
  end

  # Why this path's test must be skipped, or nil when a concrete
  # assertion could be generated.
  def skip_reason
    return @skip_reason if defined?(@skip_reason)

    @skip_reason = compute_skip_reason
  end

  private

  def compute_skip_reason
    unsolved = path.predicates.reject(&:solvable?)
    if unsolved.any?
      return "Buttress cannot solve: #{unsolved.map(&:source).join(', ')}"
    end

    # A predicate on something that is neither a settable argument nor a
    # model attribute can't be steered from the outside, and pretending
    # otherwise would assert the wrong branch.
    foreign = path.predicates.reject do |predicate|
      controllable_names.include?(predicate.variable_name)
    end
    if foreign.any?
      return "Buttress cannot control: #{foreign.map(&:source).join(', ')}"
    end

    unsatisfied = path.predicates.reject do |predicate|
      predicate.satisfied_by?(bindings, evaluator: evaluator)
    end
    if unsatisfied.any?
      return "Buttress cannot satisfy: #{unsatisfied.map(&:source).join(', ')}"
    end

    return_value
    nil
  rescue Buttress::CannotEvaluate => error
    "Buttress cannot yet evaluate: #{error.message}"
  end

  def constrained_names
    @constrained_names ||=
      path.predicates.select(&:solvable?).map(&:variable_name)
  end

  # Optional positional parameters are excluded: constraining one means
  # rendering every preceding optional too, which isn't supported yet.
  def controllable_names
    settable = method_node.args.select do |param|
      %i[arg kwarg kwoptarg].include?(param.type)
    end
    settable.map(&:name) + (columns ? columns.keys : [])
  end

  # Argument values for this path: declared or generated defaults,
  # overridden by whatever the path's predicates require of the
  # method's parameters.
  def bindings
    @bindings ||= begin
      defaults = {}
      method_node.args.each { |param| assign_default(defaults, param) }

      constraints = path.predicates
        .select(&:solvable?)
        .select { |predicate| defaults.key?(predicate.variable_name) }
        .map(&:bindings)
      defaults.merge(*constraints)
    end
  end

  # A parameter whose declared default can't be evaluated gets no
  # binding at all, so reading it degrades to a skip instead of using a
  # wrong value.
  def assign_default(defaults, param)
    case param.type
    when :arg, :kwarg
      defaults[param.name] = param.value
    when :optarg, :kwoptarg
      # Evaluated through the class-aware evaluator so defaults
      # referencing class constants resolve to their values.
      defaults[param.name] = evaluator.call(param.children.last, defaults)
    when :restarg
      defaults[param.name] = [] if param.name
    when :kwrestarg
      defaults[param.name] = {} if param.name
    end
  rescue Buttress::CannotEvaluate
    nil
  end

  # The environment at the end of the path: argument values plus the
  # effects of the statements executed along the way.
  def env
    @env ||= path.statements.each_with_object(bindings.dup) do |stmt, env|
      evaluator.call(stmt, env)
    end
  end

  def class_node
    method_node.parent_node
  end

  def columns
    return @columns if defined?(@columns)

    @columns = schema&.columns_for(class_node.name)
  end

  # The model's attribute values for this path, seeded with whatever the
  # path's predicates require. Evaluation adds defaults for attributes
  # it reads along the way.
  def attribute_store
    @attribute_store ||=
      Buttress::ModelAttributes.new(columns || {}).tap do |store|
        path.predicates.select(&:solvable?).each do |predicate|
          next unless columns&.key?(predicate.variable_name)

          predicate.bindings.each { |name, value| store.constrain(name, value) }
        end
      end
  end

  def constructor_params
    init = class_node.lookup_method(:initialize)
    init ? init.args : []
  end

  # A class-aware evaluator with instance state populated by
  # interpreting initialize (or backed by model attributes).
  def evaluator
    @evaluator ||= Buttress::Evaluator.new(
      class_node: class_node,
      model_attributes: model? ? attribute_store : nil,
    ).tap do |evaluator|
      unless model?
        evaluator.run_initialize(constructor_values, constructor_keywords)
      end
    end
  end

  def nil_node
    Parser::AST::Node.new(:nil)
  end
end

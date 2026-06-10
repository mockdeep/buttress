# One execution path through a method, ready to render as a test: the
# argument values that steer execution down the path, the call that
# exercises it, and the value it returns.
class Condition
  extend Forwardable

  delegate [:return_value, :return_name] => :return_expression

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

  def method_call
    return method_node.name unless method_node.args.any?

    rendered_args = method_node.args.map do |arg|
      Buttress::Literal.render(bindings.fetch(arg.name))
    end
    "#{method_node.name}(#{rendered_args.join(', ')})"
  end

  def return_expression
    @return_expression ||= ReturnExpression.new(
      path.return_node || nil_node,
      parent_node: method_node,
      bindings: env,
      evaluator: evaluator,
    )
  end

  # Whether the class under test is a database-backed model.
  def model?
    !columns.nil?
  end

  # Positional argument values for instantiating a plain class.
  def constructor_values
    @constructor_values ||= constructor_params.map(&:value)
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

    # A predicate on something that is neither an argument nor a model
    # attribute can't be steered from the outside, and pretending
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

  def arg_names
    @arg_names ||= method_node.args.map(&:name)
  end

  def controllable_names
    arg_names + (columns ? columns.keys : [])
  end

  # Argument values for this path: defaults, overridden by whatever the
  # path's predicates require of the method's arguments.
  def bindings
    @bindings ||= begin
      defaults = method_node.args.to_h { |arg| [arg.name, arg.value] }
      constraints = path.predicates
        .select(&:solvable?)
        .select { |predicate| defaults.key?(predicate.variable_name) }
        .map(&:bindings)
      defaults.merge(*constraints)
    end
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
      evaluator.run_initialize(constructor_values) unless model?
    end
  end

  def nil_node
    Parser::AST::Node.new(:nil)
  end
end

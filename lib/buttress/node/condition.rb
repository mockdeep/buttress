# One execution path through a method, ready to render as a test: the
# argument values that steer execution down the path, the call that
# exercises it, and the value it returns.
class Condition
  # Total candidate constructor assignments the tier-2 search may try
  # for one path.
  ATTEMPT_BUDGET = 100

  # Literal node types harvested as candidate values.
  LITERAL_TYPES = %i[str sym int].freeze

  # A coherent solved world for one path: the constructor inputs, the
  # evaluator whose instance state they produced, the method argument
  # bindings, and the environment after replaying the path's steps.
  Attempt = Struct.new(
    :evaluator, :bindings, :env,
    :constructor_positional, :constructor_keywords
  )

  attr_accessor :method_node, :path, :schema, :sources, :class_name,
                :target

  def initialize(method_node, path, schema: nil, sources: nil,
                 class_name: nil, target: nil)
    self.method_node = method_node
    self.path = path
    self.schema = schema
    self.sources = sources
    self.class_name = class_name
    self.target = target
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
      solved.evaluator.call(path.return_node || nil_node, solved.env),
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
    return default_constructor_inputs.first if solution.is_a?(Buttress::Error)

    solution.constructor_positional
  end

  # Values for initialize's required keyword parameters.
  def constructor_keywords
    return default_constructor_inputs.last if solution.is_a?(Buttress::Error)

    solution.constructor_keywords
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
    return_value
    nil
  rescue Buttress::UnsatisfiablePath => error
    "Buttress cannot satisfy: #{error.message}"
  rescue Buttress::CannotEvaluate => error
    "Buttress cannot yet evaluate: #{error.message}"
  end

  # The solved world for this path, or the error explaining why none
  # exists. Default inputs are tried first; when the replay fails on a
  # branch, the tier-2 search tries harvested constructor inputs. The
  # replay itself is the oracle, so any found assignment is verified by
  # construction.
  def solution
    @solution ||= begin
      solve
    rescue Buttress::Error => error
      error
    end
  end

  def solved
    raise solution if solution.is_a?(Buttress::Error)

    solution
  end

  def solve
    attempt(*default_constructor_inputs)
  rescue Buttress::UnsatisfiablePath => error
    search_constructor_inputs || raise(error)
  end

  # Tier-2: retries the replay with mutated constructor inputs, looking
  # for values that steer every branch its required way. Failed
  # attempts — wrong branch or unevaluable under those inputs — are
  # discarded; exhaustion falls back to the original failure.
  def search_constructor_inputs
    return nil if model?

    candidate_overrides.each do |overrides|
      return attempt(*constructor_inputs(overrides))
    rescue Buttress::UnsatisfiablePath, Buttress::CannotEvaluate
      next
    end
    nil
  end

  # Constructor assignments to try: each parameter alone, then pairs,
  # drawing values from the literals the class compares against.
  def candidate_overrides
    params = constructor_params
      .select { |param| %i[arg kwarg].include?(param.type) }
      .map(&:name)
    values = comparison_literals
    return [] if params.empty? || values.empty?

    singles = params.flat_map do |name|
      values.map { |value| { name => value } }
    end
    pairs = params.combination(2).flat_map do |first, second|
      values.product(values).map do |first_value, second_value|
        { first => first_value, second => second_value }
      end
    end
    (singles + pairs).first(ATTEMPT_BUDGET)
  end

  # Literal values the class's own code compares against — the
  # candidate pool for steering instance-state predicates.
  def comparison_literals
    harvest_literals(class_node.raw_node).uniq
  end

  def harvest_literals(node, found = [])
    return found unless node.is_a?(Parser::AST::Node)

    comparison_operands(node).each do |operand|
      found << operand.children.last if LITERAL_TYPES.include?(operand.type)
    end

    node.children.each { |child| harvest_literals(child, found) }
    found
  end

  # Operand nodes of equality comparisons and case/when clauses.
  def comparison_operands(node)
    operands =
      case node.type
      when :send
        %i[== !=].include?(node.children[1]) ? node.children.values_at(0, 2) : []
      when :when
        node.children[0..-2]
      else
        []
      end
    operands.select { |operand| operand.is_a?(Parser::AST::Node) }
  end

  # Builds one coherent world from the given constructor inputs:
  # construct the instance, derive argument bindings, then replay the
  # path's steps in execution order — evaluating statements and
  # concretely checking each predicate against the environment at its
  # branch point. Bindings are deep-duped so evaluation can mutate
  # values (list << x) without corrupting the rendered call.
  def attempt(positional, keywords)
    evaluator = build_evaluator(positional, keywords)
    bindings = build_bindings(evaluator)
    env = replay(evaluator, deep_dup(bindings))
    Attempt.new(evaluator, bindings, env, positional, keywords)
  end

  def build_evaluator(positional, keywords)
    Buttress::Evaluator.new(
      class_node: class_node,
      model_attributes: model? ? attribute_store : nil,
      sources: sources,
      class_path: class_name,
      target: target,
    ).tap do |evaluator|
      unless model?
        evaluator.run_initialize(deep_dup(positional), deep_dup(keywords))
      end
    end
  end

  # Argument values for this path: declared or generated defaults,
  # overridden by whatever the path's predicates require of the
  # method's parameters.
  def build_bindings(evaluator)
    defaults = {}
    method_node.args.each do |param|
      assign_default(defaults, param, evaluator)
    end

    constraints = path.predicates
      .select(&:solvable?)
      .select { |predicate| defaults.key?(predicate.variable_name) }
      .map(&:bindings)
    defaults.merge(*constraints)
  end

  # A parameter whose declared default can't be evaluated gets no
  # binding at all, so reading it degrades to a skip instead of using a
  # wrong value.
  def assign_default(defaults, param, evaluator)
    case param.type
    when :arg
      defaults[param.name] =
        (param.name == :other && synthesized_instance) || param.value
    when :kwarg
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

  def replay(evaluator, env)
    path.steps.each_with_object(env) do |step, acc|
      case step
      when Buttress::Predicate
        taken = evaluator.call(step.node, acc) ? true : false
        raise Buttress::UnsatisfiablePath, step.source unless
          taken == step.polarity
      else
        evaluator.call(step, acc)
      end
    end
  end

  # Method argument bindings for rendering. A skipped path renders the
  # default world's bindings.
  def bindings
    return fallback_bindings if solution.is_a?(Buttress::Error)

    solution.bindings
  end

  def fallback_bindings
    @fallback_bindings ||= build_bindings(quiet_evaluator)
  end

  # For rendering a skipped path's call: instance state from default
  # inputs, with an unevaluable initialize contributing nothing.
  def quiet_evaluator
    build_evaluator(*default_constructor_inputs)
  rescue Buttress::CannotEvaluate
    Buttress::Evaluator.new(
      class_node: class_node,
      model_attributes: model? ? attribute_store : nil,
      sources: sources,
    )
  end

  # Ruby's comparison/equality protocol: a parameter named `other` is
  # idiomatically an instance of the same class. Synthesize one from
  # default constructor inputs; anything that doesn't hold up degrades
  # through the usual paths.
  def synthesized_instance
    return @synthesized_instance if defined?(@synthesized_instance)

    @synthesized_instance = build_instance
  end

  def build_instance
    return nil unless synthesizable?

    positional, keywords = default_constructor_inputs
    evaluator = build_evaluator(positional, keywords)
    Buttress::InstanceValue.new(
      class_path: class_name || class_node.name,
      positional: positional,
      keywords: keywords,
      ivars: evaluator.ivars,
    )
  rescue Buttress::CannotEvaluate
    nil
  end

  # A class with its own initialize is always constructible from
  # solved inputs. Without one, Class.new is only safe when no
  # definition declares a superclass (an inherited initialize could
  # require arguments) and there are no Data members to populate.
  def synthesizable?
    return false if model?
    return true if class_node.lookup_method(:initialize)
    return false if class_node.data_members.any?

    class_node.superclass_name.nil? &&
      (sources.nil? ||
       sources.superclass_names(class_name || class_node.name).empty?)
  end

  def constructor_inputs(overrides = {})
    positional = constructor_params
      .select { |param| param.type == :arg }
      .map { |param| overrides.fetch(param.name, param.value) }
    keywords = constructor_params
      .select { |param| param.type == :kwarg }
      .to_h { |param| [param.name, overrides.fetch(param.name, param.value)] }
    [positional, keywords]
  end

  def default_constructor_inputs
    constructor_inputs
  end

  def deep_dup(value)
    Marshal.load(Marshal.dump(value))
  end

  def constrained_names
    @constrained_names ||=
      path.predicates.select(&:solvable?).map(&:variable_name)
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

  def nil_node
    Parser::AST::Node.new(:nil)
  end
end

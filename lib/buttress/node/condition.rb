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
  # bindings, the environment after replaying the path's steps, and the
  # value the path returns under them. The return value is computed
  # once, inside the attempt — the return expression may mutate state,
  # so evaluating it again at render time could assert a wrong value.
  Attempt = Struct.new(
    :evaluator, :bindings, :env,
    :constructor_positional, :constructor_keywords, :return_value
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
    @return_value ||= Buttress::Literal.render(solved.return_value)
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
    search_inputs || raise(error)
  rescue Buttress::CannotEvaluate => error
    repair_inputs(error) || raise(error)
  end

  # Tier-2: retries the replay with mutated inputs, looking for values
  # that steer every branch its required way. Failed attempts — wrong
  # branch or unevaluable under those inputs — are discarded;
  # exhaustion falls back to the original failure.
  def search_inputs
    return nil if model?

    candidate_assignments.each do |constructor_overrides, binding_overrides|
      return attempt(
        *constructor_inputs(constructor_overrides),
        binding_overrides: binding_overrides,
      )
    rescue Buttress::UnsatisfiablePath, Buttress::CannotEvaluate
      next
    end
    nil
  end

  # Core classes a generated default could be; an evaluation failure
  # naming any other receiver isn't steerable by swapping inputs.
  RECEIVER_CLASSES = {
    'String' => String, 'Integer' => Integer, 'Float' => Float,
    'Symbol' => Symbol, 'NilClass' => NilClass, 'TrueClass' => TrueClass,
    'FalseClass' => FalseClass, 'Array' => Array, 'Hash' => Hash,
  }.freeze

  # Tier-2b: failure-driven repair. A CannotEvaluate from the replay
  # names the method some default-valued input can't answer; values
  # that do answer it — project collaborators that define it, or a
  # core container — are tried in its place, one parameter at a time.
  # Each retry either succeeds, dead-ends, or names the next missing
  # method, steering a depth-first search. The replay is the oracle,
  # so a found assignment is verified by construction.
  def repair_inputs(error)
    return nil if model?

    @repair_attempts = 0
    @repair_seen = []
    repair_search({}, {}, error)
  end

  def repair_search(constructor_overrides, binding_overrides, failure)
    expansions(constructor_overrides, binding_overrides, failure)
      .each do |ctor, bindings|
      next if @repair_seen.include?([ctor, bindings])
      return nil if @repair_attempts >= ATTEMPT_BUDGET

      @repair_seen << [ctor, bindings]
      @repair_attempts += 1
      begin
        return attempt(
          *constructor_inputs(ctor), binding_overrides: bindings,
        )
      rescue Buttress::CannotEvaluate => deeper
        found = repair_search(ctor, bindings, deeper)
        return found if found
      rescue Buttress::UnsatisfiablePath
        next
      end
    end
    nil
  end

  # One-override extensions of the current world, ranked so candidates
  # whose constant path echoes the parameter's name come first
  # (filter: => Filters::None before unrelated definers of #call).
  def expansions(constructor_overrides, binding_overrides, failure)
    receiver_class, method_name = parse_failure(failure.message)
    return [] unless receiver_class

    values = repair_candidates(method_name)
    targets = repair_targets(
      failure, receiver_class, constructor_overrides, binding_overrides,
    )
    pairs = targets.flat_map do |kind, name, current|
      values.reject { |value| value == current }
        .map { |value| [kind, name, value] }
    end
    pairs
      .sort_by.with_index { |(_, name, value), i| [-affinity(name, value), i] }
      .map do |kind, name, value|
        if kind == :constructor
          [constructor_overrides.merge(name => value), binding_overrides]
        else
          [constructor_overrides, binding_overrides.merge(name => value)]
        end
      end
  end

  # The receiver class and method named by an evaluation failure, when
  # the receiver is a core class an input default could be.
  def parse_failure(message)
    match = /\A(\w+(?:::\w+)*)#(\w+[?!=]?)/.match(message)
    return [] unless match

    [RECEIVER_CLASSES[match[1]], match[2].to_sym]
  end

  # Values plausibly standing in for an input that must answer the
  # named method. Memoized so retried candidates compare equal across
  # search steps.
  def repair_candidates(method_name)
    @repair_candidates ||= {}
    @repair_candidates[method_name] ||= begin
      values = definer_values(method_name)
      values << [] if [].respond_to?(method_name)
      values << {} if {}.respond_to?(method_name)
      values
    end
  end

  # Project classes and modules defining the method: a module or
  # class-level definition is the constant itself; an instance
  # definition is a synthesized instance, when one can be built.
  def definer_values(method_name)
    return [] unless sources

    sources.definers_of(method_name).filter_map do |definer|
      if definer.singleton?
        Buttress::ClassReference.new(definer.path)
      else
        foreign_instance(definer.path)
      end
    end
  end

  # An interpreted instance of another project class, built from
  # default constructor inputs the same way the class under test is.
  def foreign_instance(path)
    foreign = sources.find_class(path)
    init = foreign&.lookup_method(:initialize)
    return nil unless init

    positional = init.args.select { |param| param.type == :arg }.map(&:value)
    keywords = init.args
      .select { |param| param.type == :kwarg }
      .to_h { |param| [param.name, param.value] }
    evaluator = Buttress::Evaluator.new(
      class_node: foreign, sources: sources, class_path: path, target: target,
    )
    evaluator.run_initialize(positional.dup, keywords.dup)
    Buttress::InstanceValue.new(
      class_path: path, positional: positional, keywords: keywords,
      ivars: deep_dup(evaluator.ivars),
    )
  rescue Buttress::CannotEvaluate
    nil
  end

  # Parameters the failing receiver could have come from, as
  # [kind, name, current value]. Generated defaults are unique per
  # position, so when the failure carries its receiver, parameters
  # currently bound to that exact value are the only plausible origins
  # — without it, any parameter holding a value of the receiver's
  # class could be the source. Constructor inputs and method arguments
  # both count.
  def repair_targets(failure, receiver_class, constructor_overrides,
                     binding_overrides)
    targets = constructor_params
      .select { |param| %i[arg kwarg].include?(param.type) }
      .map do |param|
        current = constructor_overrides.fetch(param.name, param.value)
        [:constructor, param.name, current]
      end
    targets += method_node.args
      .select { |param| %i[arg kwarg].include?(param.type) }
      .map do |param|
        current = binding_overrides.fetch(param.name, param.value)
        [:binding, param.name, current]
      end

    if failure.is_a?(Buttress::CannotEvaluate) && failure.receiver_known?
      exact = targets.select { |_, _, value| value == failure.receiver }
      return exact if exact.any?
    end

    targets.select { |_, _, value| value.is_a?(receiver_class) }
  end

  # Whether the candidate's constant path echoes the parameter name
  # (filter and Filters::None, sort and Sorts::First).
  def affinity(name, value)
    path =
      case value
      when Buttress::ClassReference then value.path
      when Buttress::InstanceValue then value.class_path
      end
    return 0 unless path

    stem = name.to_s.downcase
    echoes = path.downcase.split('::').any? do |segment|
      segment.start_with?(stem) || stem.start_with?(segment)
    end
    echoes ? 1 : 0
  end

  # All candidate worlds: constructor-input mutations crossed with
  # argument-type alternatives, minus the all-default world already
  # tried.
  def candidate_assignments
    constructor_options = [{}] + candidate_overrides
    binding_options = [{}] + binding_alternatives
    constructor_options.product(binding_options).drop(1)
      .first(ATTEMPT_BUDGET)
  end

  # A synthesized `other` instance may steer type-guard branches the
  # wrong way for paths reachable with plain values; offer the
  # generated string default as the alternative.
  def binding_alternatives
    method_node.args
      .select { |param| param.type == :arg && param.name == :other }
      .select { synthesized_instance }
      .map { |param| { param.name => param.value } }
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

  # String-content predicates whose literal argument is itself a value
  # satisfying them: "@".start_with?("@"), "x".include?("x"). Harvested
  # so inputs flowing into content checks (split words, substrings)
  # have a candidate that steers the check true.
  CONTENT_PREDICATES = %i[start_with? end_with? include?].freeze

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

  # Operand nodes of equality comparisons, case/when clauses, and
  # content-predicate arguments.
  def comparison_operands(node)
    operands =
      case node.type
      when :send
        operator = node.children[1]
        if %i[== !=].include?(operator)
          node.children.values_at(0, 2)
        elsif CONTENT_PREDICATES.include?(operator)
          node.children.drop(2)
        else
          []
        end
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
  def attempt(positional, keywords, binding_overrides: {})
    evaluator = build_evaluator(positional, keywords)
    bindings = build_bindings(evaluator, binding_overrides)
    env = replay(evaluator, deep_dup(bindings))
    value = evaluator.call(path.return_node || nil_node, env)
    Attempt.new(evaluator, bindings, env, positional, keywords, value)
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
  def build_bindings(evaluator, binding_overrides = {})
    defaults = {}
    method_node.args.each do |param|
      assign_default(defaults, param, evaluator)
    end
    defaults.merge!(binding_overrides)

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
      # deep_dup doubles as a marshalability check: interpreted state
      # holding an unmarshalable value (an Enumerator, say) would break
      # the replay boundary for every path the instance appears on, so
      # the synthesis degrades to nil instead.
      ivars: deep_dup(evaluator.ivars),
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

  # Unmarshalable values (Enumerators and friends) can't cross the
  # replay boundary; degrading beats asserting from corrupt state.
  def deep_dup(value)
    Marshal.load(Marshal.dump(value))
  rescue TypeError
    raise Buttress::CannotEvaluate, 'unmarshalable instance state'
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

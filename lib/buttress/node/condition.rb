# One execution path through a method, ready to render as a test: the
# argument values that steer execution down the path, the call that
# exercises it, and the value it returns.
class Condition
  # Total candidate worlds the tier searches may try for one path.
  SEARCH_BUDGET = 100

  # Literal node types collected as seed values.
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
                :target, :singleton

  def initialize(method_node, path, schema: nil, sources: nil,
                 class_name: nil, target: nil, singleton: false)
    self.method_node = method_node
    self.path = path
    self.schema = schema
    self.sources = sources
    self.class_name = class_name
    self.target = target
    self.singleton = singleton
  end

  def description
    base = "returns #{return_name.gsub("'", '"')}"
    base = "#{base} (#{Buttress::Literal.render(@outcome)})" if defined?(@outcome)
    return base if path.predicates.empty?

    "#{base} when #{path.predicates.map(&:description).join(' and ')}"
  end

  def return_name
    path.return_node&.location&.expression&.source || 'nil'
  end

  # The rendered expected value for an eq assertion. A value holding
  # an interpreted instance without provable value equality can't
  # assert by eq: a bare one falls back to the type assertion (see
  # #type_assertion_class), and a container of them degrades the path
  # to a skip.
  def return_value
    @return_value ||= begin
      value = solved.return_value
      unless equality_renderable?(value) ||
             value.is_a?(Buttress::InstanceValue)
        raise Buttress::CannotEvaluate,
              "instance equality not provable for #{return_name}"
      end
      Buttress::Literal.render(value)
    end
  end

  # The class to assert with be_an_instance_of when the return value
  # is an interpreted instance whose equality isn't provable —
  # rendering eq(Klass.new(...)) would compare by identity at test
  # runtime and fail. nil when the value asserts by eq.
  def type_assertion_class
    return nil if skip_reason

    value = solved.return_value
    return nil unless value.is_a?(Buttress::InstanceValue)

    value.class_path unless equality_renderable?(value)
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

  # The tests this path yields: the solved condition itself, plus
  # outcome variants (tier-3b) when the return expression is a
  # comparison-family send. A single satisfied world witnesses only one
  # point of such a return value's domain (-1/0/1 for <=>, true/false
  # for the equality and query selectors); each uncovered outcome gets
  # its own search for a world that produces it, and each world found
  # becomes its own test. The replay stays the oracle — a variant is
  # emitted only when the path still satisfies and the return value
  # concretely equals the target — and an outcome no candidate world
  # reaches simply gets no test.
  def variants
    return [self] if skip_reason

    [self] + outcome_variants
  end

  # Whether a synthesized reader path is worth emitting: the world
  # solved and asserts safely (skip_reason covers containers of
  # unprovable instances; a bare one falls back to the type
  # assertion), and the member doesn't just echo the constructor
  # input passed under the same name (true, but trivial).
  def informative_reader?
    return false if skip_reason

    !echoes_input?(solved.return_value)
  end

  protected

  # Locks a copy of this condition to one found world: rendering reads
  # the pinned attempt, and the description carries the outcome that
  # distinguishes the variant from its siblings.
  def pin(attempt, target)
    @solution = attempt
    @outcome = target
    @return_value = nil
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
  # branch, the tier-2 search tries seeded constructor inputs. The
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
    enrich(base_solution)
  end

  def base_solution
    attempt(*default_constructor_inputs)
  rescue Buttress::UnsatisfiablePath => error
    search_inputs || failure_search(error) || raise(error)
  rescue Buttress::CannotEvaluate => error
    failure_search(error) || raise(error)
  end

  # Tier-3: a satisfied world can still be degenerate — blocks along
  # the path walked empty collections zero times, so the test would
  # assert only the vacuous outcome. Enrichment hill-climbs: swap one
  # collection-shaped input for a one-element collection of a
  # synthesized project instance (matched by name affinity: cards ->
  # Card), keeping the world only when the path still satisfies and
  # strictly more block iterations ran. The replay stays the oracle —
  # a satisfied world is never traded for a failing one, and each
  # accepted step consumes a slot, so the climb terminates.
  def enrich(best)
    return best unless best.evaluator.trace.vacuous?

    @search_attempts ||= 0
    improved = enrichment_step(best)
    improved ? enrich(improved) : best
  end

  def enrichment_step(best)
    enrichment_candidates(best).each do |positional, keywords, bindings|
      return nil if @search_attempts >= SEARCH_BUDGET

      @search_attempts += 1
      begin
        candidate = attempt(positional, keywords, binding_overrides: bindings)
      rescue Buttress::CannotEvaluate, Buttress::UnsatisfiablePath
        next
      end
      return candidate if candidate.evaluator.trace.iterations >
                          best.evaluator.trace.iterations
    end
    nil
  end

  # One-swap variants of the solved world: each constructor parameter
  # and method argument whose name echoes a project class gets a
  # one-element collection of that class's synthesized instance.
  # Already-enriched slots are skipped, which is what bounds the climb.
  def enrichment_candidates(best)
    enrichment_slots(best).flat_map do |kind, name, key, current|
      next [] if enriched?(current)

      enrichment_values(name).map do |value|
        swap_slot(best, kind, name, key, value)
      end
    end
  end

  # One world derived from a solved attempt with a single slot swapped.
  def swap_slot(best, kind, name, key, value)
    case kind
    when :positional
      swapped = best.constructor_positional.dup
      swapped[key] = value
      [swapped, best.constructor_keywords, best.bindings]
    when :keyword
      [best.constructor_positional,
       best.constructor_keywords.merge(name => value), best.bindings]
    when :binding
      [best.constructor_positional, best.constructor_keywords,
       best.bindings.merge(name => value)]
    end
  end

  # Return-expression selectors with enumerable outcome domains.
  ORDERING_OUTCOMES = [-1, 0, 1].freeze
  BOOLEAN_OUTCOMES = [true, false].freeze
  EQUALITY_SELECTORS = %i[== != eql? equal?].freeze

  # The outcome domain of this path's return expression, or empty when
  # outcome splitting doesn't apply.
  def outcome_targets
    return [] if model?

    node = path.return_node
    return [] unless node.is_a?(Parser::AST::Node) && node.type == :send
    # A return node that is itself a checked predicate has its polarity
    # pinned (a short-circuit return path) — the other outcome is
    # unreachable by construction, so searching for it would only burn
    # the budget.
    return [] if path.predicates.any? { |predicate| predicate.node.equal?(node) }

    selector = node.children[1]
    return ORDERING_OUTCOMES if selector == :<=>
    return BOOLEAN_OUTCOMES if EQUALITY_SELECTORS.include?(selector) ||
                               selector.to_s.end_with?('?')

    []
  end

  def outcome_variants
    targets = outcome_targets - [solved.return_value]
    return [] if targets.empty?

    @search_attempts ||= 0
    targets.filter_map { |target| outcome_variant(target) }
  end

  # Tier-3b: searches one-swap mutations of the solved world for one
  # whose replay still satisfies every branch and returns the target
  # outcome.
  def outcome_variant(target)
    outcome_candidates(solved).each do |positional, keywords, bindings|
      return nil if @search_attempts >= SEARCH_BUDGET

      @search_attempts += 1
      begin
        candidate = attempt(positional, keywords, binding_overrides: bindings)
      rescue Buttress::CannotEvaluate, Buttress::UnsatisfiablePath
        next
      end
      return dup.tap { |v| v.pin(candidate, target) } if
        candidate.return_value == target
    end
    nil
  end

  def outcome_candidates(best)
    slots = enrichment_slots(best)
    siblings = slots.map(&:last)
    slots.flat_map do |kind, name, key, current|
      outcome_values(kind, name, current, siblings).map do |value|
        swap_slot(best, kind, name, key, value)
      end
    end
  end

  # Mutation values for one slot: ordered neighbors and sibling-slot
  # values for scalars, one-input mutations for a synthesized
  # instance — and, for an instance bound to a method argument, the
  # plain generated default, which steers type-guard outcomes (a core
  # value provably fails is_a?/respond_to? against a project class).
  def outcome_values(kind, name, current, siblings)
    unless current.is_a?(Buttress::InstanceValue)
      return (scalar_neighbors(current) +
              cross_slot_values(current, siblings)).uniq
    end

    values = mutated_instances(current)
    if kind == :binding
      plain = method_node.args.find { |param| param.name == name }
      values += [plain.value] if plain
    end
    values
  end

  # The current values of sibling slots with the same class — the move
  # that makes one input equal another, which equality outcomes need
  # now that generated defaults never collide on their own.
  def cross_slot_values(current, siblings)
    siblings.select { |value| value.instance_of?(current.class) } -
      [current]
  end

  # Values adjacent to a scalar in its ordering — an empty string sorts
  # before any generated default and a suffixed copy sorts after, so a
  # comparison against the unmutated side can land on either side of
  # equal — plus the literals the class compares against, which cover
  # equality with specific values (state == "complete").
  def scalar_neighbors(current)
    case current
    when String
      (['', "#{current}x"] + seed_literals.grep(String) - [current])
        .uniq
    when Integer
      ([current - 1, current + 1] + seed_literals.grep(Integer) -
        [current]).uniq
    else
      []
    end
  end

  # One-input mutations of a synthesized instance, rebuilt through the
  # same constructor machinery that built it.
  def mutated_instances(instance)
    instance_input_pairs(instance).flat_map do |name, current|
      scalar_neighbors(current).filter_map do |value|
        rebuild_instance(instance, name => value)
      end
    end
  end

  def instance_input_pairs(instance)
    names = instance_constructor_params(instance)
      .select { |param| param.type == :arg }
      .map(&:name)
    names.zip(instance.positional) + instance.keywords.to_a
  end

  def instance_constructor_params(instance)
    return constructor_params if same_class?(instance)

    init = resolve_foreign_class(instance.class_path)
      &.lookup_method(:initialize)
    init ? init.args : []
  end

  def rebuild_instance(instance, overrides)
    if same_class?(instance)
      build_instance(overrides)
    else
      foreign_instance(instance.class_path, overrides)
    end
  end

  def same_class?(instance)
    instance.class_path == (class_name || class_node.name)
  end

  # Value classes whose rendered form provably asserts at test
  # runtime: plain literals compare by value, a ClassReference renders
  # as the constant (eq is class identity), and a SubjectCall
  # re-derives both sides in the test's own process by construction.
  PLAIN_RENDERABLE = [
    NilClass, TrueClass, FalseClass, String, Symbol, Integer, Float,
    Buttress::ClassReference, Buttress::SubjectCall
  ].freeze

  # Whether a rendered eq assertion on the value provably holds at
  # test runtime: plain values compare by value, containers recurse,
  # and interpreted instances need provable value equality.
  def equality_renderable?(value)
    case value
    when Array
      value.all? { |element| equality_renderable?(element) }
    when Hash
      value.all? do |key, element|
        equality_renderable?(key) && equality_renderable?(element)
      end
    when Buttress::InstanceValue
      provable_instance_equality?(value)
    else
      PLAIN_RENDERABLE.any? { |klass| value.is_a?(klass) }
    end
  end

  # A class defining its own == is probed concolically: the evaluator
  # interprets `value == <copy of value>`, and only a concrete true
  # proves the rendered pair equal. A Data class without its own ==
  # compares member-wise, so the pair is provably equal when the
  # members are. Anything else falls to Object#==, which compares
  # identity — the rendered assertion would fail.
  def provable_instance_equality?(instance)
    foreign = resolve_foreign_class(instance.class_path)
    return false unless foreign

    if foreign.lookup_method(:==)
      equality_probe(instance)
    elsif foreign.data_members.any?
      instance.ivars.values.all? { |value| equality_renderable?(value) }
    else
      false
    end
  end

  def equality_probe(instance)
    node = Parser::AST::Node.new(
      :send,
      [Parser::AST::Node.new(:lvar, [:__buttress_left]), :==,
       Parser::AST::Node.new(:lvar, [:__buttress_right])],
    )
    env = {
      __buttress_left: deep_dup(instance),
      __buttress_right: deep_dup(instance),
    }
    solved.evaluator.call(node, env) == true
  rescue Buttress::CannotEvaluate
    false
  end

  # Whether the value is, as rendered, exactly what the constructor
  # call passes under this member's name — the generated test would
  # assert an input back at itself.
  def echoes_input?(value)
    member = method_node.name.to_sym
    passed = passed_constructor_inputs
    return false unless passed.key?(member)

    Buttress::Literal.render(passed[member]) ==
      Buttress::Literal.render(value)
  rescue Buttress::CannotEvaluate
    false
  end

  def passed_constructor_inputs
    names = constructor_params
      .select { |param| param.type == :arg }
      .map(&:name)
    names.zip(constructor_values).to_h.merge(constructor_keywords)
  end

  def enrichment_slots(best)
    positional_params = constructor_params.select { |p| p.type == :arg }
    slots = positional_params.each_with_index.map do |param, index|
      [:positional, param.name, index, best.constructor_positional[index]]
    end
    slots += constructor_params
      .select { |param| %i[kwarg kwoptarg].include?(param.type) }
      .map do |param|
        current = best.constructor_keywords
          .fetch(param.name) { declared_keyword_default(param) }
        [:keyword, param.name, param.name, current]
      end
    slots + method_node.args
      .select { |param| %i[arg kwarg].include?(param.type) }
      .map { |param| [:binding, param.name, param.name, best.bindings[param.name]] }
  end

  # The value an unpassed optional keyword actually holds: its declared
  # default, evaluated through a class-scoped evaluator so constants
  # resolve. nil when unevaluable — that slot then offers the searches
  # nothing, and a swap into it is still replay-verified like any other.
  def declared_keyword_default(param)
    return nil unless param.type == :kwoptarg

    @declared_keyword_defaults ||= {}
    return @declared_keyword_defaults[param.name] if
      @declared_keyword_defaults.key?(param.name)

    @declared_keyword_defaults[param.name] =
      begin
        Buttress::Evaluator.new(
          class_node: class_node, sources: sources,
          class_path: class_name, target: target,
        ).call(param.children.last, {})
      rescue Buttress::CannotEvaluate
        nil
      end
  end

  def enriched?(value)
    value.is_a?(Array) &&
      value.any? { |element| element.is_a?(Buttress::InstanceValue) }
  end

  # Synthesized one-element collections for a slot, drawn from project
  # classes whose name echoes the slot's: the plain default-input
  # instance, and a variant with its own collection-named inputs
  # emptied (a Card whose checklists: [] constructs even when the
  # default string would not).
  def enrichment_values(name)
    candidate_class_paths
      .select { |path| name_echoes?(name, path) }
      .flat_map do |path|
        [foreign_instance(path), emptied_collections_instance(path)]
      end
      .compact
      .map { |instance| [instance] }
  end

  def candidate_class_paths
    @candidate_class_paths ||=
      ((sources&.class_paths || []) + class_node.parent_node.class_names)
      .uniq
  end

  def emptied_collections_instance(path)
    init = resolve_foreign_class(path)&.lookup_method(:initialize)
    return nil unless init

    overrides = init.args
      .select { |param| %i[arg kwarg].include?(param.type) }
      .select { |param| collection_named?(param.name) }
      .to_h { |param| [param.name, []] }
    return nil if overrides.empty?

    foreign_instance(path, overrides)
  end

  def collection_named?(name)
    name.to_s.end_with?('s') &&
      candidate_class_paths.any? { |path| name_echoes?(name, path) }
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

  # Tier-2b/2c: failure-driven search. Each replay failure names what
  # to mutate: a CannotEvaluate names the method some default-valued
  # input can't answer (repaired with values that do answer it —
  # project collaborators that define it, or a core container); an
  # UnsatisfiablePath names the input its predicate tested (satisfied
  # with the collection emptiness polarities). Each retry either
  # succeeds, dead-ends, or names the next failure, steering a
  # depth-first search. The replay is the oracle, so a found
  # assignment is verified by construction.
  def failure_search(error)
    return nil if model?

    @search_attempts = 0
    @search_seen = []
    search_step({}, {}, error)
  end

  def search_step(constructor_overrides, binding_overrides, failure)
    expansions(constructor_overrides, binding_overrides, failure)
      .each do |ctor, bindings|
      next if @search_seen.include?([ctor, bindings])
      return nil if @search_attempts >= SEARCH_BUDGET

      @search_seen << [ctor, bindings]
      @search_attempts += 1
      begin
        return attempt(
          *constructor_inputs(ctor), binding_overrides: bindings,
        )
      rescue Buttress::CannotEvaluate, Buttress::UnsatisfiablePath => deeper
        found = search_step(ctor, bindings, deeper)
        return found if found
      end
    end
    nil
  end

  # One-override extensions of the current world, sourced from the
  # failure's kind.
  def expansions(constructor_overrides, binding_overrides, failure)
    if failure.is_a?(Buttress::UnsatisfiablePath)
      return satisfaction_expansions(
        constructor_overrides, binding_overrides, failure,
      )
    end

    repair_expansions(constructor_overrides, binding_overrides, failure)
  end

  # Collection values offered when an unsatisfiable predicate names a
  # constructor input — a declared keyword, or a key the kwrest can
  # carry (an args.fetch(:items) idiom). Both emptiness polarities are
  # tried; the replay rejects the wrong one. The member string is
  # distinct from the 'blahN' parameter defaults so receiver-traced
  # repairs stay unambiguous.
  SATISFACTION_CANDIDATES = [['item1'], []].freeze

  def satisfaction_expansions(constructor_overrides, binding_overrides,
                              failure)
    name = failure.predicate&.variable_name
    return [] unless name && constructor_assignable?(name)

    SATISFACTION_CANDIDATES.map do |value|
      [constructor_overrides.merge(name => value), binding_overrides]
    end
  end

  # Whether a constructor call can set the named input: a declared
  # (possibly optional) keyword binds directly, and a kwrest carries
  # any key at all.
  def constructor_assignable?(name)
    constructor_params.any? do |param|
      %i[arg kwarg kwoptarg kwrestarg].include?(param.type) &&
        (param.type == :kwrestarg || param.name == name)
    end
  end

  # One-override extensions ranked so candidates whose constant path
  # echoes the parameter's name come first (filter: => Filters::None
  # before unrelated definers of #call).
  def repair_expansions(constructor_overrides, binding_overrides, failure)
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
  # default constructor inputs the same way the class under test is
  # (with optional per-parameter overrides).
  def foreign_instance(path, overrides = {})
    foreign = resolve_foreign_class(path)
    init = foreign&.lookup_method(:initialize)
    return nil unless init

    positional = init.args
      .select { |param| param.type == :arg }
      .map { |param| overrides.fetch(param.name, param.value) }
    keywords = init.args
      .select { |param| param.type == :kwarg }
      .to_h { |param| [param.name, overrides.fetch(param.name, param.value)] }
    evaluator = Buttress::Evaluator.new(
      class_node: foreign, sources: sources, class_path: path, target: target,
    )
    evaluator.run_initialize(deep_dup(positional), deep_dup(keywords))
    Buttress::InstanceValue.new(
      class_path: path, positional: positional, keywords: keywords,
      ivars: deep_dup(evaluator.ivars),
    )
  rescue Buttress::CannotEvaluate
    nil
  end

  # Sibling classes resolve through Sources; classes defined in the
  # analyzed file itself resolve through its own root.
  def resolve_foreign_class(path)
    sources&.find_class(path) ||
      class_node.parent_node.lookup_class(path.split('::').last)
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
      .select { |param| %i[arg kwarg kwoptarg].include?(param.type) }
      .map do |param|
        current = constructor_overrides.fetch(param.name) do
          # An unpassed kwoptarg holds its declared default, not a
          # generated one — value-tracing must match what the replay saw.
          param.type == :kwoptarg ? declared_keyword_default(param) : param.value
        end
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
    path && name_echoes?(name, path) ? 1 : 0
  end

  def name_echoes?(name, path)
    stem = name.to_s.downcase
    path.downcase.split('::').any? do |segment|
      segment.start_with?(stem) || stem.start_with?(segment)
    end
  end

  # All candidate worlds: constructor-input mutations crossed with
  # argument-type alternatives, minus the all-default world already
  # tried.
  def candidate_assignments
    constructor_options = [{}] + candidate_overrides
    binding_options = [{}] + binding_alternatives
    constructor_options.product(binding_options).drop(1)
      .first(SEARCH_BUDGET)
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
  # Optional keywords count — an unpassed kwoptarg silently holds its
  # declared default, which may steer a branch the wrong way.
  def candidate_overrides
    params = constructor_params
      .select { |param| %i[arg kwarg kwoptarg].include?(param.type) }
      .map(&:name)
    values = seed_literals
    return [] if params.empty? || values.empty?

    singles = params.flat_map do |name|
      values.map { |value| { name => value } }
    end
    pairs = params.combination(2).flat_map do |first, second|
      values.product(values).map do |first_value, second_value|
        { first => first_value, second => second_value }
      end
    end
    (singles + pairs).first(SEARCH_BUDGET)
  end

  # String-content predicates whose literal argument is itself a value
  # satisfying them: "@".start_with?("@"), "x".include?("x"). Collected
  # as seeds so inputs flowing into content checks (split words,
  # substrings) have a candidate that steers the check true.
  CONTENT_PREDICATES = %i[start_with? end_with? include?].freeze

  # Constant seeding: literal values the class's own code compares
  # against — the candidate pool for steering instance-state predicates.
  def seed_literals
    collect_seed_literals(class_node.raw_node).uniq
  end

  def collect_seed_literals(node, found = [])
    return found unless node.is_a?(Parser::AST::Node)

    comparison_operands(node).each do |operand|
      found << operand.children.last if LITERAL_TYPES.include?(operand.type)
    end

    node.children.each { |child| collect_seed_literals(child, found) }
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
    env = deep_dup(bindings)
    predicate_values = replay(evaluator, env)
    value = return_value_for(evaluator, env, predicate_values)
    Attempt.new(evaluator, bindings, env, positional, keywords, value)
  end

  # A short-circuit return path ends with a predicate on the very node
  # it returns (see PathEnumerator#return_paths); reusing the value the
  # polarity check evaluated keeps a mutating operand from running
  # twice — the test asserts exactly what the check saw.
  def return_value_for(evaluator, env, predicate_values)
    node = path.return_node || nil_node
    return predicate_values[node] if predicate_values.key?(node)

    evaluator.call(node, env)
  rescue Buttress::CannotEvaluate => error
    subject_hash_call(error) || raise
  end

  # The hash-delegation idiom (def hash; id.hash; end). The return
  # value is process-seeded, so no statically computed literal would
  # hold at test time — but the expected side can re-derive it at
  # runtime: a public macro reader returns the very object the method
  # hashed, so subject.id.hash equals the return value under any hash
  # semantics, identity included, with the seed cancelling in-process.
  # Only provably-public plain ivar reads qualify (an interpreted
  # reader body could mutate between the method's read and the
  # assertion's).
  def subject_hash_call(error)
    # The SubjectCall renders a chain on the constructed instance;
    # a singleton flow has none.
    return nil if singleton
    return nil unless error.message.end_with?('#hash')

    node = path.return_node
    return nil unless node&.type == :send && node.children[1] == :hash &&
                      node.children.size == 2

    receiver = node.children.first
    return nil unless receiver&.type == :send &&
                      receiver.children.first.nil? &&
                      receiver.children.size == 2

    reader = receiver.children[1]
    return nil unless class_node.publicly_readable?(reader)

    Buttress::SubjectCall.new(
      subject: class_node.instance_name, messages: [reader, :hash],
    )
  end

  def build_evaluator(positional, keywords)
    Buttress::Evaluator.new(
      class_node: class_node,
      model_attributes: model? ? attribute_store : nil,
      sources: sources,
      class_path: class_name,
      target: target,
      singleton: singleton,
    ).tap do |evaluator|
      unless model? || singleton
        unless constructible?
          raise Buttress::CannotEvaluate,
                "cannot prove construction of #{class_name || class_node.name}"
        end
        evaluator.run_initialize(deep_dup(positional), deep_dup(keywords))
      end
    end
  end

  # Whether the rendered `Klass.new(...)` provably constructs: an own
  # initialize is interpretable, and without one a bare new is only
  # valid for an argless class with no Data members (Data.new raises
  # for missing members) and no declared superclass (an inherited
  # initialize could require arguments). The same rule synthesizable?
  # applies to collaborators, applied to the class under test.
  def constructible?
    return true if class_node.lookup_method(:initialize)
    return false if class_node.data_members.any?

    class_node.superclass_name.nil? &&
      (sources.nil? ||
       sources.superclass_names(class_name || class_node.name).empty?)
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

  # Replays the path's steps against env (mutated in place), returning
  # the value each predicate evaluated to, keyed by node identity —
  # return_value_for reuses these for short-circuit return paths.
  def replay(evaluator, env)
    path.steps.each_with_object({}.compare_by_identity) do |step, values|
      case step
      when Buttress::Predicate
        value = evaluator.call(step.node, env)
        values[step.node] = value
        unless (value ? true : false) == step.polarity
          error = Buttress::UnsatisfiablePath.new(step.source)
          error.predicate = step
          raise error
        end
      else
        evaluator.call(step, env)
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
      singleton: singleton,
    )
  end

  # Ruby's comparison/equality protocol: a parameter named `other` is
  # idiomatically an instance of the same class. Synthesize one from
  # default constructor inputs; anything that doesn't hold up degrades
  # through the usual paths.
  def synthesized_instance
    return @synthesized_instance if defined?(@synthesized_instance)

    # A singleton method's `other` is not the comparison protocol —
    # there's no instance to be same-class with.
    @synthesized_instance = singleton ? nil : build_instance
  end

  def build_instance(overrides = {})
    return nil unless synthesizable?

    positional, keywords = constructor_inputs(overrides)
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

  def synthesizable?
    !model? && constructible?
  end

  # Required parameters always get a value; optional keywords only
  # when overridden (otherwise the declared default applies). Override
  # keys naming no parameter ride through the kwrest, when there is
  # one — the args.fetch(:items) escape hatch.
  def constructor_inputs(overrides = {})
    positional = constructor_params
      .select { |param| param.type == :arg }
      .map { |param| overrides.fetch(param.name, param.value) }
    keywords = constructor_params
      .select do |param|
        param.type == :kwarg ||
          (param.type == :kwoptarg && overrides.key?(param.name))
      end
      .to_h { |param| [param.name, overrides.fetch(param.name, param.value)] }
    [positional, keywords.merge(kwrest_extras(overrides))]
  end

  def kwrest_extras(overrides)
    return {} unless constructor_params.any? do |param|
      param.type == :kwrestarg
    end

    declared = constructor_params.map(&:name)
    overrides.reject { |name, _| declared.include?(name) }
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

  # A singleton method has no constructor world: the receiver is the
  # class itself, so every constructor-input concern (defaults,
  # search slots, rendering) reduces to nothing.
  def constructor_params
    return [] if singleton

    init = class_node.lookup_method(:initialize)
    init ? init.args : []
  end

  def nil_node
    Parser::AST::Node.new(:nil)
  end
end

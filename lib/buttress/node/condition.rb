# One execution path through a method, ready to render as a test: the
# argument values that steer execution down the path, the call that
# exercises it, and the value it returns.
class Condition
  extend Forwardable

  delegate [:return_value, :return_name] => :return_expression

  attr_accessor :method_node, :path

  def initialize(method_node, path)
    self.method_node = method_node
    self.path = path
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
    )
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

    # A predicate on a computed local can't be steered through the
    # method's arguments, and pretending otherwise would assert the
    # wrong branch.
    arg_names = method_node.args.map(&:name)
    foreign = path.predicates.reject do |predicate|
      arg_names.include?(predicate.variable_name)
    end
    if foreign.any?
      return "Buttress cannot control: #{foreign.map(&:source).join(', ')}"
    end

    unsatisfied = path.predicates.reject do |predicate|
      predicate.satisfied_by?(bindings)
    end
    if unsatisfied.any?
      return "Buttress cannot satisfy: #{unsatisfied.map(&:source).join(', ')}"
    end

    return_value
    nil
  rescue Buttress::CannotEvaluate => error
    "Buttress cannot yet evaluate: #{error.message}"
  end

  # Argument values for this path: defaults, overridden by whatever the
  # path's predicates require.
  def bindings
    @bindings ||= method_node.args
      .to_h { |arg| [arg.name, arg.value] }
      .merge(*path.predicates.map(&:bindings))
  end

  # The environment at the end of the path: argument values plus the
  # effects of the statements executed along the way.
  def env
    @env ||= path.statements.each_with_object(bindings.dup) do |stmt, env|
      Buttress::Evaluator.call(stmt, env)
    end
  end

  def nil_node
    Parser::AST::Node.new(:nil)
  end
end

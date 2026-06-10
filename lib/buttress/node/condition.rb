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
      bindings: bindings,
    )
  end

  private

  # Argument values for this path: defaults, overridden by whatever the
  # path's predicates require.
  def bindings
    @bindings ||= method_node.args
      .to_h { |arg| [arg.name, arg.value] }
      .merge(*path.predicates.map(&:bindings))
  end

  def nil_node
    Parser::AST::Node.new(:nil)
  end
end

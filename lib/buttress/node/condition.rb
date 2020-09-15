class Condition
  extend Forwardable

  delegate [:return_name, :return_value, :method_call] => :return_expression

  attr_accessor :return_expression

  def initialize(return_expression)
    self.return_expression = return_expression
  end

  def description
    "returns #{return_name.gsub("'", '"')}"
  end
end

class Condition
  attr_accessor :return_expression

  def initialize(return_expression)
    self.return_expression = return_expression
  end

  def description
    "returns #{return_expression.return_name.gsub("'", '"')}"
  end

  def return_value
    return_expression.return_value
  end

  def method_call
    return_expression.method_call
  end
end

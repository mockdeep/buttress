class MethodNode < BaseNode
  def conditions(schema = nil)
    Buttress::PathEnumerator.call(children.last).map do |path|
      Condition.new(self, path, schema: schema)
    end
  end

  def args
    children[1].children.map.with_index do |arg, index|
      ArgumentNode.new(arg, index + 1)
    end
  end

  def name
    children.first.to_s
  end
end

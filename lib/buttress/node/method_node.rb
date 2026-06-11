class MethodNode < BaseNode
  def conditions(schema = nil, sources: nil, class_name: nil, target: nil)
    Buttress::PathEnumerator.call(children.last).map do |path|
      Condition.new(
        self, path, schema: schema, sources: sources,
        class_name: class_name, target: target,
      )
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

class MethodNode < BaseNode
  def conditions(schema = nil, sources: nil, class_name: nil, target: nil,
                 singleton: false)
    Buttress::PathEnumerator.call(children.last).map do |path|
      Condition.new(
        self, path, schema: schema, sources: sources,
        class_name: class_name, target: target, singleton: singleton,
      )
    end
  end

  # Parameter positions continue after the class's initialize
  # parameters (initialize itself starts at 1), so generated defaults
  # never collide across the constructor + method pair and a replay
  # failure's receiver names exactly one input.
  def args
    children[1].children.map.with_index do |arg, index|
      ArgumentNode.new(arg, index + 1 + position_offset)
    end
  end

  def name
    children.first.to_s
  end

  private

  def position_offset
    return @position_offset if defined?(@position_offset)

    @position_offset =
      if name == 'initialize' || !parent_node.respond_to?(:lookup_method)
        0
      else
        init = parent_node.lookup_method(:initialize)
        init ? init.children[1].children.size : 0
      end
  end
end

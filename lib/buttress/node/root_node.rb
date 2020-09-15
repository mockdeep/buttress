class RootNode < BaseNode
  def find_class(class_name)
    ClassNode.new(find_class_node(raw_node, class_name))
  end

  def find_class_node(node, class_name)
    return unless node
    return node if node.type == :class &&
      node.children.first.children.last.to_s == class_name

    current_node = node
    class_name.split('::').each do |name_part|
      current_node = current_node.children.detect do |child|
        next unless child
        child.type == :class &&
        child.children.first.children.last.to_s == name_part
      end
    end
    current_node
  end
end

# A module definition, wrapped for method lookup when resolving
# included helpers. Shares ClassNode's body conventions; the AST just
# has no superclass slot.
class ModuleNode < ClassNode
  def superclass_name
    nil
  end

  private

  def body_statements
    body = children[1]
    return [] if body.nil?

    body.type == :begin ? body.children : [body]
  end
end

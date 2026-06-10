require 'forwardable'

module Buttress
  class Error < StandardError; end
end

require_relative "buttress/version"
require_relative "buttress/inflector"
require_relative "buttress/literal"
require_relative "buttress/evaluator"
require_relative "buttress/model_attributes"
require_relative "buttress/schema"
require_relative "buttress/predicate"
require_relative "buttress/path_enumerator"
require_relative "buttress/node/base_node"
require_relative "buttress/node/argument_node"
require_relative "buttress/node/class_node"
require_relative "buttress/node/condition"
require_relative "buttress/node/method_node"
require_relative "buttress/node/root_node"
require_relative "buttress/flow_tree"
require_relative "buttress/target"
require_relative "buttress/composer"
require_relative "buttress/loader"
require_relative "buttress/writer"
require_relative "buttress/runner"

require 'parser'

RSpec.describe Buttress::Evaluator do
  def call(node, env = {})
    described_class.call(node, env)
  end

  def n(type, *children)
    Parser::AST::Node.new(type, children)
  end

  def lvar(name)
    n(:lvar, name)
  end

  def str(value)
    n(:str, value)
  end

  def int(value)
    n(:int, value)
  end

  def send_node(receiver, operator, *args)
    n(:send, receiver, operator, *args)
  end

  it 'evaluates literals' do
    expect(call(n(:true))).to eq(true)
    expect(call(n(:false))).to eq(false)
    expect(call(n(:nil))).to eq(nil)
    expect(call(int(5))).to eq(5)
    expect(call(n(:float, 1.5))).to eq(1.5)
    expect(call(str('hi'))).to eq('hi')
    expect(call(n(:sym, :hi))).to eq(:hi)
  end

  it 'looks up local variables in the environment' do
    expect(call(lvar(:value), value: 'abc')).to eq('abc')
  end

  it 'evaluates whitelisted methods on core types' do
    expect(call(send_node(lvar(:value), :upcase), value: 'abc')).to eq('ABC')
    expect(call(send_node(str('abc'), :*, int(2)))).to eq('abcabc')
    expect(call(send_node(int(5), :+, int(2)))).to eq(7)
  end

  it 'evaluates chained calls' do
    node = send_node(send_node(str('abc'), :upcase), :reverse)

    expect(call(node)).to eq('CBA')
  end

  it 'evaluates parenthesized expressions' do
    node = send_node(n(:begin, send_node(int(2), :+, int(3))), :*, int(2))

    expect(call(node)).to eq(10)
  end

  it 'evaluates string interpolation' do
    node = n(:dstr, str('Dear '), n(:begin, lvar(:name)))

    expect(call(node, name: 'Bob')).to eq('Dear Bob')
  end

  it 'evaluates local assignment, mutating the environment' do
    env = { value: 3 }
    node = n(:lvasgn, :doubled, send_node(lvar(:value), :*, int(2)))

    expect(call(node, env)).to eq(6)
    expect(env[:doubled]).to eq(6)
  end

  it 'evaluates && and || with short-circuit semantics' do
    expect(call(n(:and, n(:true), n(:false)))).to eq(false)
    expect(call(n(:or, n(:false), str('fallback')))).to eq('fallback')
    expect { call(n(:or, n(:true), n(:ivar, :@unreachable))) }
      .not_to raise_error
  end

  it 'evaluates if expressions concretely' do
    node = n(:if, n(:true), str('yes'), str('no'))

    expect(call(node)).to eq('yes')
    expect(call(n(:if, n(:false), str('yes'), nil))).to eq(nil)
  end

  def class_node_for(code)
    RootNode.new(Buttress::Target.default.parse(code)).find_class('MyClass')
  end

  it 'invokes sibling methods by interpreting their bodies' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        def double(number)
          number * 2
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    node = send_node(nil, :double, lvar(:value))

    expect(evaluator.call(node, value: 3)).to eq(6)
  end

  it 'handles early returns inside interpreted bodies' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        def classify(number)
          return 'negative' if number < 0
          'positive'
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(send_node(nil, :classify, int(-1)), {}))
      .to eq('negative')
    expect(evaluator.call(send_node(nil, :classify, int(1)), {}))
      .to eq('positive')
  end

  it 'populates instance variables by interpreting initialize' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        def initialize(name)
          @name = name
        end

        def shout
          @name.upcase
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    evaluator.run_initialize(['bob'])

    expect(evaluator.call(send_node(nil, :shout), {})).to eq('BOB')
  end

  it 'reads attributes declared with attr_reader' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        attr_reader :name

        def initialize(name)
          @name = name
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    evaluator.run_initialize(['bob'])

    expect(evaluator.call(send_node(nil, :name), {})).to eq('bob')
  end

  it 'writes attributes declared with attr_accessor' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        attr_accessor :name
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    writer = send_node(n(:self), :name=, str('bob'))

    expect(evaluator.call(writer, {})).to eq('bob')
    expect(evaluator.call(send_node(nil, :name), {})).to eq('bob')
  end

  it 'supports the legacy attr macro with a writable flag' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        attr :name, true
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    evaluator.call(send_node(n(:self), :name=, str('bob')), {})

    expect(evaluator.call(send_node(nil, :name), {})).to eq('bob')
  end

  it 'does not write attributes that only declare a reader' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        attr_reader :name
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(send_node(n(:self), :name=, str('bob')), {}) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'raises CannotEvaluate for runaway recursion' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        def forever(number)
          forever(number + 1)
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(send_node(nil, :forever, int(1)), {}) }
      .to raise_error(Buttress::CannotEvaluate, /recursion in #forever/)
  end

  it 'raises CannotEvaluate for ivars without a class context' do
    expect { call(n(:ivar, :@value)) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'raises CannotEvaluate for non-whitelisted methods' do
    expect { call(send_node(str('abc'), :object_id)) }
      .to raise_error(Buttress::CannotEvaluate, /String#object_id/)
  end

  it 'raises CannotEvaluate for receiverless calls' do
    expect { call(send_node(nil, :helper)) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'raises CannotEvaluate for unknown node types' do
    expect { call(n(:ivar, :@value)) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'raises CannotEvaluate for unbound local variables' do
    expect { call(lvar(:missing)) }
      .to raise_error(Buttress::CannotEvaluate, /unbound variable missing/)
  end

  it 'converts runtime errors into CannotEvaluate' do
    expect { call(send_node(int(5), :/, int(0))) }
      .to raise_error(Buttress::CannotEvaluate, /ZeroDivisionError/)
  end
end

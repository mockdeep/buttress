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

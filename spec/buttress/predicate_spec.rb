require 'parser'

RSpec.describe Buttress::Predicate do
  def lvar(name)
    Parser::AST::Node.new(:lvar, [name])
  end

  def literal(value)
    type = value.is_a?(Integer) ? :int : :str
    Parser::AST::Node.new(type, [value])
  end

  def comparison(operator, value)
    Parser::AST::Node.new(:send, [lvar(:value), operator, literal(value)])
  end

  def query(operator)
    Parser::AST::Node.new(:send, [lvar(:value), operator])
  end

  describe '#bindings' do
    it 'solves truthiness on a bare argument' do
      expect(described_class.new(lvar(:value), true).bindings)
        .to eq(value: true)
      expect(described_class.new(lvar(:value), false).bindings)
        .to eq(value: false)
    end

    it 'solves ordered comparisons with boundary values' do
      expect(described_class.new(comparison(:>, 5), true).bindings)
        .to eq(value: 6)
      expect(described_class.new(comparison(:>, 5), false).bindings)
        .to eq(value: 5)
      expect(described_class.new(comparison(:>=, 5), true).bindings)
        .to eq(value: 5)
      expect(described_class.new(comparison(:>=, 5), false).bindings)
        .to eq(value: 4)
      expect(described_class.new(comparison(:<, 5), true).bindings)
        .to eq(value: 4)
      expect(described_class.new(comparison(:<, 5), false).bindings)
        .to eq(value: 5)
      expect(described_class.new(comparison(:<=, 5), true).bindings)
        .to eq(value: 5)
      expect(described_class.new(comparison(:<=, 5), false).bindings)
        .to eq(value: 6)
    end

    it 'solves equality against integer and string literals' do
      expect(described_class.new(comparison(:==, 5), true).bindings)
        .to eq(value: 5)
      expect(described_class.new(comparison(:==, 5), false).bindings)
        .to eq(value: 6)
      expect(described_class.new(comparison(:==, 'admin'), true).bindings)
        .to eq(value: 'admin')
      expect(described_class.new(comparison(:==, 'admin'), false).bindings)
        .to eq(value: 'not admin')
      expect(described_class.new(comparison(:'!=', 'admin'), true).bindings)
        .to eq(value: 'not admin')
      expect(described_class.new(comparison(:'!=', 'admin'), false).bindings)
        .to eq(value: 'admin')
    end

    it 'solves empty? and nil? queries' do
      expect(described_class.new(query(:empty?), true).bindings)
        .to eq(value: '')
      expect(described_class.new(query(:empty?), false).bindings).to eq({})
      expect(described_class.new(query(:nil?), true).bindings)
        .to eq(value: nil)
      expect(described_class.new(query(:nil?), false).bindings).to eq({})
    end

    it 'raises for ordered comparison against a string literal' do
      expect { described_class.new(comparison(:>, 'abc'), true).bindings }
        .to raise_error(Buttress::Error, /cannot solve predicate/)
    end

    it 'raises for an unsupported predicate form' do
      node = Parser::AST::Node.new(:ivar, [:@value])

      expect { described_class.new(node, true).bindings }
        .to raise_error(Buttress::Error, /cannot solve predicate/)
    end
  end

  describe '#description' do
    it 'describes truthiness' do
      expect(described_class.new(lvar(:value), true).description)
        .to eq('value is true')
    end

    it 'describes comparisons, negating the operator for the else branch' do
      expect(described_class.new(comparison(:>, 5), true).description)
        .to eq('value > 5')
      expect(described_class.new(comparison(:>, 5), false).description)
        .to eq('value <= 5')
      expect(described_class.new(comparison(:==, 'admin'), false).description)
        .to eq('value != "admin"')
    end

    it 'describes queries' do
      expect(described_class.new(query(:empty?), true).description)
        .to eq('value is empty')
      expect(described_class.new(query(:nil?), false).description)
        .to eq('value is not nil')
    end
  end
end

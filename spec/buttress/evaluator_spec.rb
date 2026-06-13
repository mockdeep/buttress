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

  def expr(code)
    Buttress::Target.default.parse(code)
  end

  it 'evaluates blocks over arrays, ranges, and integers' do
    expect(call(expr('[1, 2, 3].map { |x| x * 2 }'))).to eq([2, 4, 6])
    expect(call(expr('[3, 1, 2].select { |x| x > 1 }'))).to eq([3, 2])
    expect(call(expr('(1..4).sum { |x| x * 10 }'))).to eq(100)
    expect(call(expr('[1, 2].map { _1 * 3 }'))).to eq([3, 6])
  end

  it 'evaluates hash fetch with a fallback block' do
    expect(call(expr('{ a: 1 }.fetch(:b) { "fallback" }'))).to eq('fallback')
    expect(call(expr('{ a: 1 }.fetch(:a) { "fallback" }'))).to eq(1)
  end

  it 'evaluates array fetch with a default' do
    expect(call(expr('[10, 20].fetch(0)'))).to eq(10)
    expect(call(expr('[10, 20].fetch(5, "default")'))).to eq('default')
  end

  it 'evaluates each_slice through to_a' do
    expect(call(expr('[1, 2, 3].each_slice(2).to_a'))).to eq([[1, 2], [3]])
  end

  it 'evaluates freeze on values the evaluator built' do
    expect(call(expr("['a', 'b'].freeze"))).to eq(%w[a b])
    expect(call(expr("'ab'.freeze"))).to eq('ab')
    expect(call(expr('{ a: 1 }.freeze'))).to eq({ a: 1 })
  end

  it 'degrades mutation of a frozen value' do
    expect { call(expr("['a'].freeze << 'b'")) }
      .to raise_error(Buttress::CannotEvaluate, /FrozenError/)
  end

  it 'interprets Array#cycle as a deterministic enumerator' do
    expect(call(expr("['a', 'b'].cycle.next"))).to eq('a')
    expect(call(expr("e = ['a', 'b'].cycle\ne.next\ne.next"))).to eq('b')
    expect(call(expr("e = ['a', 'b'].cycle\ne.next\ne.next\ne.next")))
      .to eq('a')
  end

  it 'degrades cycle on an empty array' do
    expect { call(expr('[].cycle.next')) }
      .to raise_error(Buttress::CannotEvaluate, /Array#cycle/)
  end

  it 'degrades the block form of cycle' do
    expect { call(expr('[1].cycle { |x| x }')) }
      .to raise_error(Buttress::CannotEvaluate, /Array#cycle with a block/)
  end

  it 'evaluates regexp literals and the methods that take them' do
    expect(call(expr('"go to https://x.io now".scan(%r{https?://\S+})')))
      .to eq(['https://x.io'])
    expect(call(expr('"ABC" =~ /b/i'))).to eq(1)
    expect(call(expr('/b/.match?("abc")'))).to eq(true)
    expect(call(expr('"a-b".split(/-/)'))).to eq(%w[a b])
  end

  it 'evaluates interpolated regexps when the parts evaluate' do
    expect(call(expr('"abc" =~ /#{"b"}c/'))).to eq(1)
    expect { call(expr('"x" =~ /#{boom}/')) }
      .to raise_error(Buttress::CannotEvaluate, /boom/)
  end

  it 'degrades regexp flags without stable semantics' do
    expect { call(expr('"x".scan(/y/o)')) }
      .to raise_error(Buttress::CannotEvaluate, %r{/y/o})
  end

  it 'traces block iterations and vacuous walks' do
    evaluator = described_class.new

    evaluator.call(expr('[1, 2].map { |x| x }'), {})
    expect(evaluator.trace.iterations).to eq(2)
    expect(evaluator.trace.vacuous?).to eq(false)

    evaluator.call(expr('[].map { |x| x }'), {})
    expect(evaluator.trace.vacuous?).to eq(true)
  end

  it 'does not mark zero-run walks over non-empty receivers vacuous' do
    evaluator = described_class.new

    evaluator.call(expr('[1, 2].find { |x| x > 5 }'), {})
    evaluator.call(expr('{ a: 1 }.fetch(:a) { "fallback" }'), {})

    expect(evaluator.trace.vacuous?).to eq(false)
  end

  it 'evaluates the map.with_index idiom' do
    node = expr('["a", "b"].map.with_index { |x, i| "#{i}#{x}" }')

    expect(call(node)).to eq(%w[0a 1b])
  end

  it 'evaluates each_with_object with contained mutation' do
    node = expr('[1, 2].each_with_object([]) { |x, memo| memo << x * 2 }')

    expect(call(node)).to eq([2, 4])
  end

  it 'destructures hash iteration into block parameters' do
    node = expr('{ a: 1, b: 2 }.map { |key, value| "#{key}=#{value}" }')

    expect(call(node)).to eq(['a=1', 'b=2'])
  end

  it 'evaluates the &:symbol block form' do
    expect(call(expr("['a', 'b'].map(&:upcase)"))).to eq(%w[A B])
  end

  it 'binds a rightward hash destructure from the value members' do
    env = {}
    node = expr(
      'state = { filter: "none", sort: "first", extra: "x" }; ' \
      'state => { filter:, sort: }',
    )

    call(node, env)
    expect(env[:filter]).to eq('none')
    expect(env[:sort]).to eq('first')
  end

  it 'degrades a destructure pattern that is not a bare match-var hash' do
    expect { call(expr('state = { mode: "x" }; state => { mode: "x" }')) }
      .to raise_error(Buttress::CannotEvaluate)
    expect { call(expr('state = [1, 2]; state => [first, second]')) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'honors next and break inside blocks' do
    skip_evens = expr('[1, 2, 3].map { |x| next 0 if x == 2; x }')
    first_big = expr('[1, 2, 3].each { |x| break x * 10 if x > 1 }')

    expect(call(skip_evens)).to eq([1, 0, 3])
    expect(call(first_big)).to eq(20)
  end

  it 'raises CannotEvaluate for blocks on non-whitelisted methods' do
    expect { call(expr('[1].instance_exec { 2 }')) }
      .to raise_error(Buttress::CannotEvaluate, /Array#instance_exec/)
  end

  it 'propagates CannotEvaluate from inside block bodies' do
    expect { call(expr('[1].map { |x| helper(x) }')) }
      .to raise_error(Buttress::CannotEvaluate, /helper/)
  end

  it 'evaluates range literals' do
    expect(call(expr('(1..3).to_a'))).to eq([1, 2, 3])
    expect(call(expr('(1...3).to_a'))).to eq([1, 2])
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

  it 'invokes methods from modules included in the same file' do
    class_node = class_node_for(<<~RUBY)
      module Helpers
        def shout(word)
          word.upcase
        end
      end

      class MyClass
        include Helpers
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(send_node(nil, :shout, str('hi')), {})).to eq('HI')
  end

  it 'lets module methods read the including instance state' do
    class_node = class_node_for(<<~'RUBY')
      module Helpers
        def label
          "#{prefix}!"
        end
      end

      class MyClass
        include Helpers
        attr_reader :prefix

        def initialize(prefix)
          @prefix = prefix
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    evaluator.run_initialize(['hi'])

    expect(evaluator.call(send_node(nil, :label), {})).to eq('hi!')
  end

  it 'prefers methods defined on the class over included modules' do
    class_node = class_node_for(<<~RUBY)
      module Helpers
        def label
          'module'
        end
      end

      class MyClass
        include Helpers

        def label
          'class'
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(send_node(nil, :label), {})).to eq('class')
  end

  it 'prefers attr_reader accessors over included module methods' do
    class_node = class_node_for(<<~RUBY)
      module Helpers
        def label
          'module'
        end
      end

      class MyClass
        include Helpers
        attr_reader :label

        def initialize(label)
          @label = label
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    evaluator.run_initialize(['attr'])

    expect(evaluator.call(send_node(nil, :label), {})).to eq('attr')
  end

  it 'prefers included module methods over model attributes' do
    class_node = class_node_for(<<~RUBY)
      module Helpers
        def name
          'module'
        end
      end

      class MyClass
        include Helpers
      end
    RUBY
    store = Buttress::ModelAttributes.new(name: :string)
    evaluator = described_class.new(
      class_node: class_node, model_attributes: store,
    )

    expect(evaluator.call(send_node(nil, :name), {})).to eq('module')
  end

  it 'degrades when an included module cannot be resolved' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        include Comparable
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(send_node(nil, :clamp_me), {}) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'invokes def self singleton methods on same-file classes' do
    class_node = class_node_for(<<~RUBY)
      class Builder
        def self.build(word)
          word.upcase
        end
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(expr('Builder.build("hi")'), {})).to eq('HI')
  end

  it 'invokes class << self singleton methods on same-file classes' do
    class_node = class_node_for(<<~RUBY)
      class Builder
        class << self
          def build(word, suffix:)
            word + suffix
          end
        end
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(expr('Builder.build("hi", suffix: "!")'), {}))
      .to eq('hi!')
  end

  it 'does not treat singleton defs as instance methods' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        class << self
          def helper
            'singleton'
          end
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(send_node(nil, :helper), {}) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'does not treat nested-class defs as instance methods' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        class Inner
          def helper
            'inner'
          end
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(send_node(nil, :helper), {}) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'binds trailing hash literals to keyword parameters of siblings' do
    class_node = class_node_for(<<~'RUBY')
      class MyClass
        def greet(name, punct:)
          "#{name}#{punct}"
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(expr('greet("hi", punct: "!")'), {})).to eq('hi!')
  end

  it 'degrades for class references with no known definition' do
    class_node = class_node_for("class MyClass\nend")
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(expr('Missing.build(1)'), {}) }
      .to raise_error(Buttress::CannotEvaluate, /ClassReference#build/)
  end

  it 'stops mutual recursion across classes at the depth limit' do
    class_node = class_node_for(<<~RUBY)
      class AClass
        def self.ping(number)
          BClass.pong(number)
        end
      end

      class BClass
        def self.pong(number)
          AClass.ping(number)
        end
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(expr('AClass.ping(1)'), {}) }
      .to raise_error(Buttress::CannotEvaluate, /recursion/)
  end

  it 'refuses keywords the interpreted method does not declare' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        def greet(punct:)
          punct
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(expr('greet(punct: "!", extra: 1)'), {}) }
      .to raise_error(Buttress::CannotEvaluate, /cannot bind/)
  end

  it 'collects undeclared keywords into a keyword rest parameter' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        def greet(punct:, **rest)
          rest.keys
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(expr('greet(punct: "!", extra: 1)'), {}))
      .to eq([:extra])
  end

  it 'dispatches sends on instance values to their class' do
    class_node = class_node_for(<<~RUBY)
      class Widget
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def shout
          name.upcase
        end
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    instance = Buttress::InstanceValue.new(
      class_path: 'Widget', positional: ['bob'], ivars: { :@name => 'bob' },
    )

    expect(evaluator.call(send_node(lvar(:other), :shout), other: instance))
      .to eq('BOB')
  end

  it 'interprets singleton methods on project modules' do
    class_node = class_node_for(<<~RUBY)
      module Pipeline
        class << self
          def call(input)
            input.upcase
          end
        end
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(expr('Pipeline.call("hi")'), {})).to eq('HI')
  end

  it 'constructs project-class instances by interpreting initialize' do
    class_node = class_node_for(<<~RUBY)
      class Widget
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def shout
          name.upcase
        end
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    value = evaluator.call(expr('Widget.new("bob")'), {})

    expect(value).to be_a(Buttress::InstanceValue)
    expect(value.class_path).to eq('Widget')
    expect(value.positional).to eq(['bob'])
    expect(value.ivars).to eq(:@name => 'bob')
    expect(evaluator.call(expr('Widget.new("bob").shout'), {})).to eq('BOB')
  end

  it 'constructs instances through keyword initializers' do
    class_node = class_node_for(<<~RUBY)
      class Widget
        def initialize(name:)
          @name = name
        end
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    value = evaluator.call(expr('Widget.new(name: "bob")'), {})

    expect(value.keywords).to eq(name: 'bob')
    expect(value.ivars).to eq(:@name => 'bob')
  end

  it 'constructs argless instances of classes without an initialize' do
    class_node = class_node_for(<<~RUBY)
      class NullThing
        def name
          '<none>'
        end
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(expr('NullThing.new.name'), {})).to eq('<none>')
  end

  it 'degrades construction when an inherited initialize could exist' do
    class_node = class_node_for(<<~RUBY)
      class Child < Base
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(expr('Child.new'), {}) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'degrades construction when arguments hit no initialize' do
    class_node = class_node_for(<<~RUBY)
      class NullThing
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(expr('NullThing.new("arg")'), {}) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'names the class when instance dispatch finds no method' do
    class_node = class_node_for(<<~RUBY)
      class Widget
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    instance = Buttress::InstanceValue.new(class_path: 'Widget')

    expect { evaluator.call(send_node(lvar(:other), :missing), other: instance) }
      .to raise_error(Buttress::CannotEvaluate, /Widget#missing/)
  end

  it 'answers type checks on host values from stable class identity' do
    expect(call(expr('"hi".is_a?(String)'))).to eq(true)
    expect(call(expr('"hi".is_a?(Integer)'))).to eq(false)
    expect(call(expr('5.kind_of?(Numeric)'))).to eq(true)
    expect(call(expr('"hi".instance_of?(Comparable)'))).to eq(false)
  end

  it 'answers respond_to? false on host values for modern targets' do
    evaluator = described_class.new(target: Buttress::Target.default)

    expect(evaluator.call(expr('"hi".respond_to?(:tag_name)'), {}))
      .to eq(false)
  end

  it 'leaves host respond_to? unanswered for 1.8 targets' do
    evaluator = described_class.new(target: Buttress::Target.new('1.8'))

    expect { evaluator.call(expr('"hi".respond_to?(:tag_name)'), {}) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'never answers respond_to? true from the host' do
    evaluator = described_class.new(target: Buttress::Target.default)

    expect { evaluator.call(expr('"hi".respond_to?(:upcase)'), {}) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'leaves removal-history names unanswered on host values' do
    evaluator = described_class.new(target: Buttress::Target.default)

    expect { evaluator.call(expr('"hi".respond_to?(:taint)'), {}) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'proves is_a? false against core classes for project instances' do
    class_node = class_node_for(<<~RUBY)
      class Widget
        def initialize(name)
          @name = name
        end
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    instance = Buttress::InstanceValue.new(class_path: 'Widget')
    node = send_node(lvar(:other), :is_a?, expr('String'))

    expect(evaluator.call(node, other: instance)).to eq(false)
  end

  it 'proves is_a? true through declared superclasses' do
    class_node = class_node_for(<<~RUBY)
      class Base
      end

      class Widget < Base
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    instance = Buttress::InstanceValue.new(class_path: 'Widget')

    expect(evaluator.call(send_node(lvar(:other), :is_a?, expr('Base')),
                          other: instance)).to eq(true)
    expect(evaluator.call(send_node(lvar(:other), :is_a?, expr('String')),
                          other: instance)).to eq(false)
  end

  it 'leaves is_a? unanswered when the superclass chain breaks' do
    class_node = class_node_for(<<~RUBY)
      class Widget < ActiveRecord::Base
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    instance = Buttress::InstanceValue.new(class_path: 'Widget')

    expect(evaluator.call(
      send_node(lvar(:other), :is_a?, expr('ActiveRecord::Base')),
      other: instance,
    )).to eq(true)
    expect do
      evaluator.call(send_node(lvar(:other), :is_a?, expr('String')),
                     other: instance)
    end.to raise_error(Buttress::CannotEvaluate)
  end

  it 'answers respond_to? true for methods the instance class defines' do
    class_node = class_node_for(<<~RUBY)
      class Widget
        attr_reader :name
      end

      class MyClass
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    instance = Buttress::InstanceValue.new(class_path: 'Widget')

    expect(evaluator.call(
      send_node(lvar(:other), :respond_to?, n(:sym, :name)),
      other: instance,
    )).to eq(true)
    expect do
      evaluator.call(send_node(lvar(:other), :respond_to?, n(:sym, :nope)),
                     other: instance)
    end.to raise_error(Buttress::CannotEvaluate)
  end

  it 'evaluates self.class to a class reference' do
    class_node = class_node_for("class MyClass\nend")
    evaluator = described_class.new(
      class_node: class_node, class_path: 'Foo::MyClass',
    )

    expect(evaluator.call(send_node(n(:self), :class), {}))
      .to eq(Buttress::ClassReference.new('Foo::MyClass'))
  end

  it 'populates Data members through super in initialize' do
    class_node = class_node_for(<<~RUBY)
      MyClass = Data.define(:name, :state)

      class MyClass
        def initialize(name:, state:)
          super(name: name, state: state)
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)
    evaluator.run_initialize([], { name: 'bob', state: 'complete' })

    expect(evaluator.call(send_node(nil, :name), {})).to eq('bob')
    expect(evaluator.call(send_node(nil, :state), {})).to eq('complete')
  end

  it 'raises CannotEvaluate for super outside a Data subclass' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        def initialize(name)
          super(name)
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.run_initialize(['bob']) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'raises CannotEvaluate when super omits a Data member' do
    class_node = class_node_for(<<~RUBY)
      MyClass = Data.define(:name, :state)

      class MyClass
        def initialize(name:)
          super(name: name)
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.run_initialize([], { name: 'bob' }) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'raises CannotEvaluate for positional super in a Data subclass' do
    class_node = class_node_for(<<~RUBY)
      MyClass = Data.define(:name)

      class MyClass
        def initialize(name)
          super(name)
        end
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.run_initialize(['bob']) }
      .to raise_error(Buttress::CannotEvaluate)
  end

  it 'reads and writes schema-declared model attributes' do
    class_node = class_node_for("class MyClass\nend")
    store = Buttress::ModelAttributes.new(name: :string)
    evaluator = described_class.new(
      class_node: class_node, model_attributes: store,
    )

    expect(evaluator.call(send_node(nil, :name), {})).to eq('blah')
    expect(store.constructor_values).to eq(name: 'blah')

    evaluator.call(send_node(n(:self), :name=, str('bob')), {})

    expect(evaluator.call(send_node(nil, :name), {})).to eq('bob')
    expect(store.constructor_values).to eq(name: 'blah')
  end

  it 'raises CannotEvaluate for model attributes of unsupported types' do
    class_node = class_node_for("class MyClass\nend")
    store = Buttress::ModelAttributes.new(created_at: :datetime)
    evaluator = described_class.new(
      class_node: class_node, model_attributes: store,
    )

    expect { evaluator.call(send_node(nil, :created_at), {}) }
      .to raise_error(Buttress::CannotEvaluate, /datetime/)
  end

  it 'resolves constants assigned in the class body' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        MAX = 5
        GREETING = 'hi'
        ALIASED = GREETING
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect(evaluator.call(n(:const, nil, :MAX), {})).to eq(5)
    expect(evaluator.call(n(:const, nil, :ALIASED), {})).to eq('hi')
  end

  it 'treats unresolvable constants as class references' do
    qualified = n(:const, n(:const, nil, :Foo), :Bar)

    expect(call(qualified))
      .to eq(Buttress::ClassReference.new('Foo::Bar'))
    expect(call(qualified)).not_to eq(Buttress::ClassReference.new('Foo'))
  end

  it 'compares class references by equality in evaluation' do
    node = send_node(n(:const, n(:const, nil, :Foo), :Bar),
                     :==,
                     n(:const, n(:const, nil, :Foo), :Bar))

    expect(call(node)).to eq(true)
  end

  it 'raises CannotEvaluate for circular constants' do
    class_node = class_node_for(<<~RUBY)
      class MyClass
        FIRST = SECOND
        SECOND = FIRST
      end
    RUBY
    evaluator = described_class.new(class_node: class_node)

    expect { evaluator.call(n(:const, nil, :FIRST), {}) }
      .to raise_error(Buttress::CannotEvaluate, /circular constant/)
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

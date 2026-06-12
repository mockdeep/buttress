RSpec.describe Buttress::Composer, '#call' do

  it 'returns test code for when method returns true' do
    code = <<~RUBY
      class MyClass
        def call_me
          true
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns true' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq(true)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'generates should-syntax assertions under a Ruby 1.8 target' do
    code = <<~RUBY
      class MyClass
        def call_me
          true
        end
      end
    RUBY

    expected_tests = <<~RUBY
      describe MyClass, '#call_me' do
        it 'returns true' do
          my_class = MyClass.new

          my_class.call_me.should == true
        end
      end
    RUBY

    target = Buttress::Target.new('1.8')
    result = described_class.call(code, 'MyClass', 'call_me', target: target)
    expect(result).to eq(expected_tests)
  end

  it 'returns test code for when method returns string' do
    code = <<~RUBY
      class MyClass
        def call_me
          'blah'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "blah"' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq('blah')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns test code for when method returns a number' do
    code = <<~RUBY
      class MyClass
        def call_me
          5
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns 5' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq(5)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns test code for when method returns given value' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          value
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns value' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('blah1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns test code for when method takes 2 arguments' do
    code = <<~RUBY
      class MyClass
        def call_me(value1, value2)
          value1
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns value1' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1', 'blah2')).to eq('blah1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns test code for when method returns new value' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          value * 2
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns value * 2' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('blah1blah1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns test code for when method returns new value for second argument' do
    code = <<~RUBY
      class MyClass
        def call_me(value1, value2)
          value2 * 2
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns value2 * 2' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1', 'blah2')).to eq('blah2blah2')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns a test per branch for an if/else' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          if value
            'yes'
          else
            'no'
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "yes" when value is true' do
          my_class = MyClass.new

          expect(my_class.call_me(true)).to eq('yes')
        end

        it 'returns "no" when value is false' do
          my_class = MyClass.new

          expect(my_class.call_me(false)).to eq('no')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns a test per branch for a guard clause' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          return 'yes' if value
          'no'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "yes" when value is true' do
          my_class = MyClass.new

          expect(my_class.call_me(true)).to eq('yes')
        end

        it 'returns "no" when value is false' do
          my_class = MyClass.new

          expect(my_class.call_me(false)).to eq('no')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns a test per branch for a ternary' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          value ? 'yes' : 'no'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "yes" when value is true' do
          my_class = MyClass.new

          expect(my_class.call_me(true)).to eq('yes')
        end

        it 'returns "no" when value is false' do
          my_class = MyClass.new

          expect(my_class.call_me(false)).to eq('no')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns a test per branch for an elsif chain' do
    code = <<~RUBY
      class MyClass
        def call_me(first, second)
          if first
            'one'
          elsif second
            'two'
          else
            'three'
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "one" when first is true' do
          my_class = MyClass.new

          expect(my_class.call_me(true, 'blah2')).to eq('one')
        end

        it 'returns "two" when first is false and second is true' do
          my_class = MyClass.new

          expect(my_class.call_me(false, true)).to eq('two')
        end

        it 'returns "three" when first is false and second is false' do
          my_class = MyClass.new

          expect(my_class.call_me(false, false)).to eq('three')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns a nil test for a guard clause with no fallthrough' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          return 'yes' if value
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "yes" when value is true' do
          my_class = MyClass.new

          expect(my_class.call_me(true)).to eq('yes')
        end

        it 'returns nil when value is false' do
          my_class = MyClass.new

          expect(my_class.call_me(false)).to eq(nil)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'solves comparison predicates with boundary values' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          if value > 5
            'big'
          else
            'small'
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "big" when value > 5' do
          my_class = MyClass.new

          expect(my_class.call_me(6)).to eq('big')
        end

        it 'returns "small" when value <= 5' do
          my_class = MyClass.new

          expect(my_class.call_me(5)).to eq('small')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'solves string equality predicates' do
    code = <<~RUBY
      class MyClass
        def call_me(name)
          return 'admin' if name == 'admin'
          'guest'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "admin" when name == "admin"' do
          my_class = MyClass.new

          expect(my_class.call_me('admin')).to eq('admin')
        end

        it 'returns "guest" when name != "admin"' do
          my_class = MyClass.new

          expect(my_class.call_me('not admin')).to eq('guest')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'solves empty? predicates' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          return 'nothing' if value.empty?
          'something'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "nothing" when value is empty' do
          my_class = MyClass.new

          expect(my_class.call_me('')).to eq('nothing')
        end

        it 'returns "something" when value is not empty' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('something')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'solves nil? predicates' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          return 'missing' if value.nil?
          'present'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "missing" when value is nil' do
          my_class = MyClass.new

          expect(my_class.call_me(nil)).to eq('missing')
        end

        it 'returns "present" when value is not nil' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('present')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'threads solved values through to computed return values' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          return 0 if value <= 5
          value * 2
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns 0 when value <= 5' do
          my_class = MyClass.new

          expect(my_class.call_me(5)).to eq(0)
        end

        it 'returns value * 2 when value > 5' do
          my_class = MyClass.new

          expect(my_class.call_me(6)).to eq(12)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'evaluates whitelisted core methods in return values' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          value.upcase
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns value.upcase' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('BLAH1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'generates a skipped skeleton when the return value cannot be evaluated' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          helper(value)
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns helper(value)' do
          skip 'Buttress cannot yet evaluate: helper(value)'

          my_class = MyClass.new

          my_class.call_me('blah1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'generates skipped skeletons when a predicate cannot be evaluated' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          if value.even?
            'even'
          else
            'odd'
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "even" when value.even?' do
          skip 'Buttress cannot yet evaluate: String#even?'

          my_class = MyClass.new

          my_class.call_me('blah1')
        end

        it 'returns "odd" when !(value.even?)' do
          skip 'Buttress cannot yet evaluate: String#even?'

          my_class = MyClass.new

          my_class.call_me('blah1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'finds the requested method among several in a class' do
    code = <<~RUBY
      class MyClass
        def other_method
          'other'
        end

        def call_me
          'mine'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "mine"' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq('mine')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'evaluates string interpolation in return values' do
    code = <<~'RUBY'
      class MyClass
        def call_me(name)
          "Hello, #{name}!"
        end
      end
    RUBY

    expected_tests = <<~'RUBY'
      RSpec.describe MyClass, '#call_me' do
        it 'returns "Hello, #{name}!"' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('Hello, blah1!')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'threads local assignments into the return value' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          doubled = value * 2
          doubled.upcase
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns doubled.upcase' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('BLAH1BLAH1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'splits && conditions by short-circuit semantics' do
    code = <<~RUBY
      class MyClass
        def call_me(first, second)
          if first && second
            'both'
          else
            'not both'
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "both" when first is true and second is true' do
          my_class = MyClass.new

          expect(my_class.call_me(true, true)).to eq('both')
        end

        it 'returns "not both" when first is true and second is false' do
          my_class = MyClass.new

          expect(my_class.call_me(true, false)).to eq('not both')
        end

        it 'returns "not both" when first is false' do
          my_class = MyClass.new

          expect(my_class.call_me(false, 'blah2')).to eq('not both')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'splits || conditions by short-circuit semantics' do
    code = <<~RUBY
      class MyClass
        def call_me(first, second)
          if first || second
            'either'
          else
            'neither'
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "either" when first is true' do
          my_class = MyClass.new

          expect(my_class.call_me(true, 'blah2')).to eq('either')
        end

        it 'returns "either" when first is false and second is true' do
          my_class = MyClass.new

          expect(my_class.call_me(false, true)).to eq('either')
        end

        it 'returns "neither" when first is false and second is false' do
          my_class = MyClass.new

          expect(my_class.call_me(false, false)).to eq('neither')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'desugars case/when into equality predicates' do
    code = <<~RUBY
      class MyClass
        def call_me(status)
          case status
          when 'active'
            'running'
          when 'paused'
            'waiting'
          else
            'unknown'
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "running" when status == "active"' do
          my_class = MyClass.new

          expect(my_class.call_me('active')).to eq('running')
        end

        it 'returns "waiting" when status != "active" and status == "paused"' do
          my_class = MyClass.new

          expect(my_class.call_me('paused')).to eq('waiting')
        end

        it 'returns "unknown" when status != "active" and status != "paused"' do
          my_class = MyClass.new

          expect(my_class.call_me('not paused')).to eq('unknown')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'concretely follows branches on computed locals' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          half = value.length / 2
          if half > 2
            'long'
          else
            'short'
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "long" when half > 2' do
          skip 'Buttress cannot satisfy: half > 2'

          my_class = MyClass.new

          my_class.call_me('blah1')
        end

        it 'returns "short" when half <= 2' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('short')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'concretely follows branches on helper methods' do
    code = <<~RUBY
      class MyClass
        def call_me
          if ready?
            'go'
          else
            'wait'
          end
        end

        def ready?
          true
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "go" when ready? is true' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq('go')
        end

        it 'returns "wait" when ready? is false' do
          skip 'Buttress cannot satisfy: ready?'

          my_class = MyClass.new

          my_class.call_me
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'follows guarded mutations of computed locals' do
    code = <<~RUBY
      class MyClass
        def call_me(name)
          names = name.split.select { |word| word.start_with?('@') }
          names << '<none>' if names.empty?
          names
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns names when names is empty' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq(["<none>"])
        end

        it 'returns names when names is not empty' do
          skip 'Buttress cannot satisfy: names.empty?'

          my_class = MyClass.new

          my_class.call_me('blah1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'skips paths whose combined predicates cannot be satisfied' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          if value > 10
            if value < 7
              'impossible'
            else
              'big'
            end
          else
            'small'
          end
        end
      end
    RUBY

    result = described_class.call(code, 'MyClass', 'call_me')

    expect(result).to include(
      "it 'returns \"impossible\" when value > 10 and value < 7' do\n" \
      "    skip 'Buttress cannot satisfy: value > 10'",
    )
    expect(result).to include("expect(my_class.call_me(10)).to eq('small')")
  end

  it 'evaluates calls to sibling methods' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          helper(value)
        end

        def helper(value)
          value.upcase
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns helper(value)' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('BLAH1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'instantiates through initialize and reads instance variables' do
    code = <<~'RUBY'
      class MyClass
        def initialize(name)
          @name = name
        end

        def call_me
          "Hello, #{@name}!"
        end
      end
    RUBY

    expected_tests = <<~'RUBY'
      RSpec.describe MyClass, '#call_me' do
        it 'returns "Hello, #{@name}!"' do
          my_class = MyClass.new('blah1')

          expect(my_class.call_me).to eq('Hello, blah1!')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'evaluates attr_reader accessors' do
    code = <<~'RUBY'
      class MyClass
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def call_me
          "Hi, #{name}!"
        end
      end
    RUBY

    expected_tests = <<~'RUBY'
      RSpec.describe MyClass, '#call_me' do
        it 'returns "Hi, #{name}!"' do
          my_class = MyClass.new('blah1')

          expect(my_class.call_me).to eq('Hi, blah1!')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'evaluates attr_accessor writes through self' do
    code = <<~RUBY
      class MyClass
        attr_accessor :name

        def call_me(value)
          self.name = value.upcase
          name
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns name' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('BLAH1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  def user_schema
    Buttress::Schema.parse(<<~RUBY)
      ActiveRecord::Schema.define(version: 1) do
        create_table "users" do |t|
          t.string "name"
          t.integer "age"
          t.boolean "admin"
        end
      end
    RUBY
  end

  it 'generates model tests with schema-backed attributes' do
    code = <<~RUBY
      class User < ApplicationRecord
        def call_me
          if admin
            'administrator'
          else
            name
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe User, '#call_me' do
        it 'returns "administrator" when admin is true' do
          user = User.new(admin: true)

          expect(user.call_me).to eq('administrator')
        end

        it 'returns name when admin is false' do
          user = User.new(admin: false, name: 'blah')

          expect(user.call_me).to eq('blah')
        end
      end
    RUBY

    result = described_class.call(
      code, 'User', 'call_me', schema: user_schema,
    )
    expect(result).to eq(expected_tests)
  end

  it 'solves comparison predicates on model attributes' do
    code = <<~RUBY
      class User < ApplicationRecord
        def call_me
          return 'minor' if age < 18
          'adult'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe User, '#call_me' do
        it 'returns "minor" when age < 18' do
          user = User.new(age: 17)

          expect(user.call_me).to eq('minor')
        end

        it 'returns "adult" when age >= 18' do
          user = User.new(age: 18)

          expect(user.call_me).to eq('adult')
        end
      end
    RUBY

    result = described_class.call(
      code, 'User', 'call_me', schema: user_schema,
    )
    expect(result).to eq(expected_tests)
  end

  it 'renders model constructors with hash rockets for a 1.8 target' do
    code = <<~RUBY
      class User < ActiveRecord::Base
        def call_me
          return 'minor' if age < 18
          'adult'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      describe User, '#call_me' do
        it 'returns "minor" when age < 18' do
          user = User.new(:age => 17)

          user.call_me.should == 'minor'
        end

        it 'returns "adult" when age >= 18' do
          user = User.new(:age => 18)

          user.call_me.should == 'adult'
        end
      end
    RUBY

    result = described_class.call(
      code, 'User', 'call_me',
      target: Buttress::Target.new('1.8'), schema: user_schema,
    )
    expect(result).to eq(expected_tests)
  end

  it 'skips model paths reading attributes of unsupported types' do
    code = <<~RUBY
      class User < ApplicationRecord
        def call_me
          created_at
        end
      end
    RUBY

    schema = Buttress::Schema.parse(<<~RUBY)
      ActiveRecord::Schema.define(version: 1) do
        create_table "users" do |t|
          t.datetime "created_at"
        end
      end
    RUBY

    result = described_class.call(code, 'User', 'call_me', schema: schema)

    expect(result).to include(
      "skip 'Buttress cannot yet evaluate: no default for datetime attribute created_at'",
    )
  end

  it 'generates a spec for every public method when no method is given' do
    code = <<~RUBY
      class MyClass
        def initialize(name)
          @name = name
        end

        def shout
          @name.upcase
        end

        def whisper(value)
          if value
            'psst'
          else
            'nothing'
          end
        end

        private

        def hidden
          'secret'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass do
        describe '#shout' do
          it 'returns @name.upcase' do
            my_class = MyClass.new('blah1')

            expect(my_class.shout).to eq('BLAH1')
          end
        end

        describe '#whisper' do
          it 'returns "psst" when value is true' do
            my_class = MyClass.new('blah1')

            expect(my_class.whisper(true)).to eq('psst')
          end

          it 'returns "nothing" when value is false' do
            my_class = MyClass.new('blah1')

            expect(my_class.whisper(false)).to eq('nothing')
          end
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass')).to eq(expected_tests)
  end

  it 'excludes methods marked private inline or by name' do
    code = <<~RUBY
      class MyClass
        def visible
          'yes'
        end

        private def tucked_away
          'no'
        end

        def listed
          'no'
        end

        private :listed
      end
    RUBY

    result = described_class.call(code, 'MyClass')

    expect(result).to include("describe '#visible' do")
    expect(result).not_to include('tucked_away')
    expect(result).not_to include("describe '#listed' do")
  end

  it 'handles optional keyword parameters in initialize' do
    code = <<~'RUBY'
      class MyClass
        def initialize(name, items: [])
          @name = name
          @items = items
        end

        def call_me
          "#{@name}: #{@items.size}"
        end
      end
    RUBY

    expected_tests = <<~'RUBY'
      RSpec.describe MyClass do
        describe '#call_me' do
          it 'returns "#{@name}: #{@items.size}"' do
            my_class = MyClass.new('blah1')

            expect(my_class.call_me).to eq('blah1: 0')
          end
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass')).to eq(expected_tests)
  end

  it 'renders required keywords in the constructor' do
    code = <<~'RUBY'
      class MyClass
        def initialize(card_id:, name:)
          @card_id = card_id
          @name = name
        end

        def call_me
          "#{@card_id}/#{@name}"
        end
      end
    RUBY

    expected_tests = <<~'RUBY'
      RSpec.describe MyClass, '#call_me' do
        it 'returns "#{@card_id}/#{@name}"' do
          my_class = MyClass.new(card_id: 'blah1', name: 'blah2')

          expect(my_class.call_me).to eq('blah1/blah2')
        end
      end
    RUBY

    result = described_class.call(code, 'MyClass', 'call_me')
    expect(result).to eq(expected_tests)
  end

  it 'solves predicates on optional keyword parameters' do
    code = <<~RUBY
      class MyClass
        def call_me(value, upcase: false)
          if upcase
            value.upcase
          else
            value
          end
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns value.upcase when upcase is true' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1', upcase: true)).to eq('BLAH1')
        end

        it 'returns value when upcase is false' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1', upcase: false)).to eq('blah1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'degrades to a skip when initialize cannot be evaluated' do
    code = <<~RUBY
      class MyClass
        def initialize(data)
          @data = process(data)
        end

        def call_me
          @data
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns @data' do
          skip 'Buttress cannot yet evaluate: process(data)'

          my_class = MyClass.new('blah1')

          my_class.call_me
        end
      end
    RUBY

    result = described_class.call(code, 'MyClass', 'call_me')
    expect(result).to eq(expected_tests)
  end

  it 'evaluates Data subclasses whose initialize assigns members via super' do
    code = <<~'RUBY'
      MyClass = Data.define(:icon, :name, :state)

      class MyClass
        def initialize(name:, state:, **_data)
          icon = state == "complete" ? "x" : "o"
          super(icon:, name:, state:)
        end

        def call_me
          "#{icon} #{name}"
        end
      end
    RUBY

    expected_tests = <<~'RUBY'
      RSpec.describe MyClass, '#call_me' do
        it 'returns "#{icon} #{name}"' do
          my_class = MyClass.new(name: 'blah1', state: 'blah2')

          expect(my_class.call_me).to eq('o blah1')
        end
      end
    RUBY

    result = described_class.call(code, 'MyClass', 'call_me')
    expect(result).to eq(expected_tests)
  end

  it 'evaluates methods from an included module' do
    code = <<~RUBY
      module Helpers
        def shout(word)
          word.upcase
        end
      end

      class MyClass
        include Helpers

        def call_me(name)
          shout(name)
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns shout(name)' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('BLAH1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'searches constructor keywords to satisfy instance-state predicates' do
    code = <<~RUBY
      MyClass = Data.define(:state)

      class MyClass
        def initialize(state:)
          super(state:)
        end

        def call_me
          if checked?
            'done'
          else
            'todo'
          end
        end

        def checked?
          state == "complete"
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "done" when checked? is true' do
          my_class = MyClass.new(state: 'complete')

          expect(my_class.call_me).to eq('done')
        end

        it 'returns "todo" when checked? is false' do
          my_class = MyClass.new(state: 'blah1')

          expect(my_class.call_me).to eq('todo')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'searches positional constructor inputs to satisfy predicates' do
    code = <<~RUBY
      class MyClass
        attr_reader :mode

        def initialize(mode)
          @mode = mode
        end

        def call_me
          if admin?
            'admin'
          else
            'guest'
          end
        end

        def admin?
          mode == "admin"
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "admin" when admin? is true' do
          my_class = MyClass.new('admin')

          expect(my_class.call_me).to eq('admin')
        end

        it 'returns "guest" when admin? is false' do
          my_class = MyClass.new('blah1')

          expect(my_class.call_me).to eq('guest')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'still skips when no constructor input satisfies the branch' do
    code = <<~RUBY
      class MyClass
        attr_reader :mode

        def initialize(mode)
          @mode = mode
        end

        def call_me
          if locked?
            'locked'
          else
            'open'
          end
        end

        def locked?
          mode.length > 100
        end
      end
    RUBY

    result = described_class.call(code, 'MyClass', 'call_me')

    expect(result).to include("skip 'Buttress cannot satisfy: locked?'")
    expect(result).to include("expect(my_class.call_me).to eq('open')")
  end

  it 'evaluates class-method calls on other classes' do
    code = <<~'RUBY'
      class Builder
        class << self
          def build(items, prefix:)
            items.map { |item| "#{prefix}#{item}" }
          end
        end
      end

      class MyClass
        def call_me
          Builder.build([], prefix: "x")
        end
      end
    RUBY

    expected_tests = <<~'RUBY'
      RSpec.describe MyClass, '#call_me' do
        it 'returns Builder.build([], prefix: "x")' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq([])
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'synthesizes same-class instances for parameters named other' do
    code = <<~RUBY
      class MyClass
        attr_reader :pos

        def initialize(pos)
          @pos = pos
        end

        def call_me(other)
          pos <=> other.pos
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns pos <=> other.pos' do
          my_class = MyClass.new('blah1')

          expect(my_class.call_me(MyClass.new('blah1'))).to eq(0)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'renders synthesized Data instances with their keyword inputs' do
    code = <<~RUBY
      MyClass = Data.define(:pos)

      class MyClass
        def initialize(pos:)
          super(pos:)
        end

        def call_me(other)
          pos <=> other.pos
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns pos <=> other.pos' do
          my_class = MyClass.new(pos: 'blah1')

          expect(my_class.call_me(MyClass.new(pos: 'blah1'))).to eq(0)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'generates both branches of a type-guarded equality method' do
    code = <<~RUBY
      class MyClass
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def call_me(other)
          other.is_a?(String) ? name == other : other.name == name
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns name == other when other.is_a?(String)' do
          my_class = MyClass.new('blah1')

          expect(my_class.call_me('blah1')).to eq(true)
        end

        it 'returns other.name == name when !(other.is_a?(String))' do
          my_class = MyClass.new('blah1')

          expect(my_class.call_me(MyClass.new('blah1'))).to eq(true)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'evaluates is_a?(self.class) for classes without initialize' do
    code = <<~RUBY
      class MyClass
        def call_me(other)
          other.is_a?(self.class)
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns other.is_a?(self.class)' do
          my_class = MyClass.new

          expect(my_class.call_me(MyClass.new)).to eq(true)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'finds classes nested inside modules and compact names' do
    code = <<~RUBY
      module Outer
        module Inner
          class MyClass
            def call_me
              'nested'
            end
          end
        end
      end
    RUBY

    result = described_class.call(code, 'Outer::Inner::MyClass', 'call_me')

    expect(result).to include("RSpec.describe Outer::Inner::MyClass, '#call_me' do")
    expect(result).to include("expect(my_class.call_me).to eq('nested')")
  end

  it 'resolves class constants in return values' do
    code = <<~'RUBY'
      class MyClass
        GREETING = 'Hello'

        def call_me(name)
          "#{GREETING}, #{name}!"
        end
      end
    RUBY

    expected_tests = <<~'RUBY'
      RSpec.describe MyClass, '#call_me' do
        it 'returns "#{GREETING}, #{name}!"' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('Hello, blah1!')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'resolves constants used as keyword defaults in initialize' do
    code = <<~RUBY
      class MyClass
        DEFAULT_MODE = 'normal'

        def initialize(mode: DEFAULT_MODE)
          @mode = mode
        end

        def call_me
          @mode.upcase
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns @mode.upcase' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq('NORMAL')
        end
      end
    RUBY

    result = described_class.call(code, 'MyClass', 'call_me')
    expect(result).to eq(expected_tests)
  end

  it 'renders class-reference constants by their path' do
    code = <<~RUBY
      class MyClass
        DEFAULT = Other::Thing

        def call_me
          DEFAULT
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns DEFAULT' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq(Other::Thing)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'evaluates blocks in return values' do
    code = <<~RUBY
      class MyClass
        def call_me
          [3, 1, 2].select { |n| n > 1 }.sort
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns [3, 1, 2].select { |n| n > 1 }.sort' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq([2, 3])
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'evaluates blocks over method arguments' do
    code = <<~RUBY
      class MyClass
        def call_me(name)
          name.split.map(&:capitalize).join(' ')
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns name.split.map(&:capitalize).join(" ")' do
          my_class = MyClass.new

          expect(my_class.call_me('blah1')).to eq('Blah1')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'returns a test per branch for an unless guard' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          return 'no' unless value
          'yes'
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns "yes" when value is true' do
          my_class = MyClass.new

          expect(my_class.call_me(true)).to eq('yes')
        end

        it 'returns "no" when value is false' do
          my_class = MyClass.new

          expect(my_class.call_me(false)).to eq('no')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'falls back to plain defaults when instance state cannot marshal' do
    code = <<~RUBY
      class MyClass
        def initialize(items = [1, 2])
          @pages = items.each_slice(2)
        end

        def same?(other)
          true
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#same?' do
        it 'returns true' do
          my_class = MyClass.new

          expect(my_class.same?('blah1')).to eq(true)
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'same?')).to eq(expected_tests)
  end

  it 'interprets singleton methods on modules in the same file' do
    code = <<~RUBY
      module Pipeline
        class << self
          def call(input)
            input.upcase
          end
        end
      end

      class MyClass
        def call_me
          Pipeline.call('hi')
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns Pipeline.call("hi")' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq('HI')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

  it 'constructs instances of other classes in return values' do
    code = <<~RUBY
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
        def call_me
          Widget.new('bob').shout
        end
      end
    RUBY

    expected_tests = <<~RUBY
      RSpec.describe MyClass, '#call_me' do
        it 'returns Widget.new("bob").shout' do
          my_class = MyClass.new

          expect(my_class.call_me).to eq('BOB')
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end
end

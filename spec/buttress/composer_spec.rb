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
end

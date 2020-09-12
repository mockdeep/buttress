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
      describe MyClass, '#call_me' do
        it 'returns true' do
          my_class = MyClass.new

          my_class.call_me.should == true
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
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
      describe MyClass, '#call_me' do
        it 'returns "blah"' do
          my_class = MyClass.new

          my_class.call_me.should == 'blah'
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
      describe MyClass, '#call_me' do
        it 'returns 5' do
          my_class = MyClass.new

          my_class.call_me.should == 5
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
      describe MyClass, '#call_me' do
        it 'returns value' do
          my_class = MyClass.new

          my_class.call_me('blah1').should == 'blah1'
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
      describe MyClass, '#call_me' do
        it 'returns value1' do
          my_class = MyClass.new

          my_class.call_me('blah1', 'blah2').should == 'blah1'
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
      describe MyClass, '#call_me' do
        it 'returns value * 2' do
          my_class = MyClass.new

          my_class.call_me('blah1').should == 'blah1blah1'
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
      describe MyClass, '#call_me' do
        it 'returns value2 * 2' do
          my_class = MyClass.new

          my_class.call_me('blah1', 'blah2').should == 'blah2blah2'
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

end

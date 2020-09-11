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

  xit 'returns test code for when method returns given value' do
    code = <<~RUBY
      class MyClass
        def call_me(value)
          value
        end
      end
    RUBY

    expected_tests = <<~RUBY
      describe MyClass, '#call_me' do
        it 'returns the given value' do
          my_class = MyClass.new

          my_class.call_me('blah').should == 'blah'
        end
      end
    RUBY

    expect(described_class.call(code, 'MyClass', 'call_me')).to eq(expected_tests)
  end

end

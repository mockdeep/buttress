RSpec.describe Buttress::Runner, '#call' do

  it 'returns test code for when method returns true' do
    code = <<-RUBY
      class MyClass
        def call_me
          true
        end
      end
    RUBY

    expected_tests = <<-RUBY
      describe MyClass, '#call_me' do
        it 'returns true' do
          my_class = MyClass.new

          my_class.call_me.should be true
        end
      end
    RUBY

    expect(described_class.call(code)).to eq(expected_tests)
  end

end

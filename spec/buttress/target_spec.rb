RSpec.describe Buttress::Target do
  # `if cond : body end` is valid only in Ruby 1.8; the colon-as-then
  # syntax was removed in 1.9.
  RUBY_18_ONLY_CODE = "if true : 'a' end".freeze

  it 'parses 1.8-only syntax with the 1.8 target' do
    target = described_class.new('1.8')

    expect(target.parse(RUBY_18_ONLY_CODE)).to be_a(Parser::AST::Node)
  end

  it 'rejects 1.8-only syntax with the default target' do
    target = described_class.default

    expect { target.parse(RUBY_18_ONLY_CODE) }
      .to raise_error(Parser::SyntaxError)
  end

  it 'renders the legacy dialect for a 1.8 target' do
    target = described_class.new('1.8')

    expect(target.describe).to eq('describe')
    expect(target.assertion('foo.bar', "'baz'"))
      .to eq("foo.bar.should == 'baz'")
  end

  it 'renders the modern dialect for the default target' do
    target = described_class.default

    expect(target.describe).to eq('RSpec.describe')
    expect(target.assertion('foo.bar', "'baz'"))
      .to eq("expect(foo.bar).to eq('baz')")
  end

  it 'raises a Buttress::Error for an unsupported version' do
    expect { described_class.new('0.9') }
      .to raise_error(Buttress::Error, /unsupported target Ruby version/)
  end

  it 'defaults to the newest supported version when given nil' do
    expect(described_class.new(nil).version)
      .to eq(described_class::DEFAULT_VERSION)
  end
end

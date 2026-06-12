require 'parser'

RSpec.describe RootNode do
  it 'collects qualified class names however they are written' do
    code = <<~RUBY
      module Outer
        class Alpha; end

        module Inner
          class Beta; end
        end
      end

      class Outer::Gamma; end

      module Helpers; end
    RUBY

    root = described_class.new(Buttress::Target.default.parse(code))

    expect(root.class_names)
      .to eq(%w[Outer::Alpha Outer::Inner::Beta Outer::Gamma])
  end
end

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

  it 'collects qualified module names however they are written' do
    code = <<~RUBY
      module Outer
        class Alpha; end

        module Inner
          class Beta; end
        end
      end

      module Outer::Helpers; end
    RUBY

    root = described_class.new(Buttress::Target.default.parse(code))

    expect(root.module_names)
      .to eq(%w[Outer Outer::Inner Outer::Helpers])
  end

  it 'finds a module as a generation subject' do
    code = <<~RUBY
      module Outer
        module Helpers; end
      end
    RUBY

    root = described_class.new(Buttress::Target.default.parse(code))

    expect(root.find_class_or_module('Outer::Helpers').module?).to eq(true)
    expect { root.find_class_or_module('Missing') }
      .to raise_error(Buttress::Error, 'class or module not found: Missing')
  end
end

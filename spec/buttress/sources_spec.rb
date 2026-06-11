require 'fileutils'

RSpec.describe Buttress::Sources do
  let(:root) { File.expand_path('../../tmp/sources_project', __dir__) }

  before do
    FileUtils.mkdir_p(File.join(root, 'lib/fake'))
    File.write(File.join(root, 'Gemfile'), "source 'https://rubygems.org'\n")
    File.write(File.join(root, 'lib/fake/helpers.rb'), <<~RUBY)
      module Fake
        module Helpers
          def shout(word)
            word.upcase
          end
        end
      end
    RUBY
  end

  after { FileUtils.rm_rf(root) }

  def sources
    described_class.from_file(File.join(root, 'lib/fake/thing.rb'))
  end

  it 'finds the project root from the analyzed file' do
    expect(sources).not_to be_nil
  end

  it 'resolves modules defined in sibling files by qualified name' do
    module_node = sources.find_module('Fake::Helpers')

    expect(module_node).not_to be_nil
    expect(module_node.lookup_method(:shout)).not_to be_nil
  end

  it 'resolves modules by a trailing segment of their qualified name' do
    expect(sources.find_module('Helpers')).not_to be_nil
  end

  it 'returns nil for modules defined nowhere in the project' do
    expect(sources.find_module('Comparable')).to be_nil
  end

  it 'lets the composer evaluate includes from sibling files' do
    code = <<~RUBY
      class MyClass
        include Fake::Helpers

        def call_me(name)
          shout(name)
        end
      end
    RUBY

    result = Buttress::Composer.call(
      code, 'MyClass', 'call_me', sources: sources,
    )

    expect(result).to include("expect(my_class.call_me('blah1')).to eq('BLAH1')")
  end
end

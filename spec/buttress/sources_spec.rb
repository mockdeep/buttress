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

  it 'resolves classes defined in sibling files' do
    File.write(File.join(root, 'lib/fake/builder.rb'), <<~RUBY)
      module Fake
        class Builder
          def self.build(word)
            word.upcase
          end
        end
      end
    RUBY

    class_node = sources.find_class('Fake::Builder')

    expect(class_node).not_to be_nil
    expect(class_node.lookup_singleton_method(:build)).not_to be_nil
  end

  it 'resolves sibling-file classes with their Data members' do
    File.write(File.join(root, 'lib/fake/item.rb'), <<~RUBY)
      Fake::Item = Data.define(:name, :state)

      class Fake::Item
        def initialize(name:, state:)
          super(name:, state:)
        end
      end
    RUBY

    expect(sources.find_class('Fake::Item').data_members)
      .to eq(%i[name state])
  end

  it 'indexes public method definitions across the project' do
    File.write(File.join(root, 'lib/fake/worker.rb'), <<~RUBY)
      module Fake
        class Worker
          def call(input)
            input
          end
        end

        module Pipeline
          class << self
            def call(input)
              input
            end
          end
        end

        class Builder
          def self.call(input)
            input
          end
        end
      end
    RUBY

    expect(sources.definers_of(:call)).to contain_exactly(
      Buttress::Sources::Definer.new('Fake::Worker', :instance),
      Buttress::Sources::Definer.new('Fake::Pipeline', :singleton),
      Buttress::Sources::Definer.new('Fake::Builder', :singleton),
    )
  end

  it 'never offers private definitions as definers' do
    File.write(File.join(root, 'lib/fake/worker.rb'), <<~RUBY)
      module Fake
        class Worker
          def initialize(seed)
            @seed = seed
          end

          private

          def call(input)
            input
          end
        end

        module Pipeline
          class << self
            private

            def call(input)
              input
            end
          end
        end
      end
    RUBY

    expect(sources.definers_of(:call)).to be_empty
    expect(sources.definers_of(:initialize)).to be_empty
  end

  it 'records one definer for a method defined across reopens' do
    File.write(File.join(root, 'lib/fake/worker.rb'), <<~RUBY)
      class Fake::Worker
        def call(input)
          input
        end
      end
    RUBY
    File.write(File.join(root, 'lib/fake/worker_extras.rb'), <<~RUBY)
      class Fake::Worker
        def call(input)
          input.to_s
        end
      end
    RUBY

    expect(sources.definers_of(:call)).to contain_exactly(
      Buttress::Sources::Definer.new('Fake::Worker', :instance),
    )
  end

  it 'lets the composer evaluate class methods from sibling files' do
    File.write(File.join(root, 'lib/fake/builder.rb'), <<~RUBY)
      module Fake
        class Builder
          def self.build(items, prefix:)
            items.map { |item| prefix + item }
          end
        end
      end
    RUBY
    code = <<~RUBY
      class MyClass
        def call_me
          Fake::Builder.build([], prefix: "x")
        end
      end
    RUBY

    result = Buttress::Composer.call(
      code, 'MyClass', 'call_me', sources: sources,
    )

    expect(result).to include('expect(my_class.call_me).to eq([])')
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

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

  it 'indexes macro readers and Data#with as instance definers' do
    File.write(File.join(root, 'lib/fake/record.rb'), <<~RUBY)
      Fake::Record = Data.define(:slug, :count)

      class Fake::Record
        def initialize(slug:, count: 0)
          super(slug:, count:)
        end
      end
    RUBY
    File.write(File.join(root, 'lib/fake/holder.rb'), <<~RUBY)
      module Fake
        class Holder
          attr_reader :label

          def initialize(label)
            @label = label
          end
        end
      end
    RUBY

    expect(sources.definers_of(:slug))
      .to include(Buttress::Sources::Definer.new('Fake::Record', :instance))
    expect(sources.definers_of(:with))
      .to contain_exactly(Buttress::Sources::Definer.new('Fake::Record', :instance))
    expect(sources.definers_of(:label))
      .to contain_exactly(Buttress::Sources::Definer.new('Fake::Holder', :instance))
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

  it 'repairs a collaborator input with a module that defines the method' do
    FileUtils.mkdir_p(File.join(root, 'lib/fake/filters'))
    File.write(File.join(root, 'lib/fake/filters/none.rb'), <<~RUBY)
      module Fake
        module Filters
          module None
            class << self
              def call(items)
                items
              end
            end
          end
        end
      end
    RUBY
    code = <<~RUBY
      class MyClass
        def initialize(filter:)
          @filter = filter
        end

        def filtered
          @filter.call(['x'])
        end
      end
    RUBY

    result = Buttress::Composer.call(code, 'MyClass', 'filtered', sources: sources)

    expect(result).to include('MyClass.new(filter: Fake::Filters::None)')
    expect(result).to include('expect(my_class.filtered).to eq(["x"])')
  end

  it 'repairs a collaborator input with a synthesized instance' do
    File.write(File.join(root, 'lib/fake/upcaser.rb'), <<~RUBY)
      module Fake
        class Upcaser
          def initialize(prefix)
            @prefix = prefix
          end

          def call(word)
            (@prefix + word).upcase
          end
        end
      end
    RUBY
    code = <<~RUBY
      class MyClass
        def initialize(transform:)
          @transform = transform
        end

        def shout
          @transform.call('hi')
        end
      end
    RUBY

    result = Buttress::Composer.call(code, 'MyClass', 'shout', sources: sources)

    expect(result)
      .to include("MyClass.new(transform: Fake::Upcaser.new('blah1'))")
    expect(result).to include("expect(my_class.shout).to eq('BLAH1HI')")
  end

  it 'chains repairs across collaborators named like their parameters' do
    FileUtils.mkdir_p(File.join(root, 'lib/fake/filters'))
    File.write(File.join(root, 'lib/fake/filters/none.rb'), <<~RUBY)
      module Fake
        module Filters
          module None
            class << self
              def call(items)
                items
              end
            end
          end
        end
      end
    RUBY
    FileUtils.mkdir_p(File.join(root, 'lib/fake/sorts'))
    File.write(File.join(root, 'lib/fake/sorts/first.rb'), <<~RUBY)
      module Fake
        module Sorts
          module First
            class << self
              def call(items)
                items.first
              end
            end
          end
        end
      end
    RUBY
    code = <<~RUBY
      class MyClass
        def initialize(filter:, sort:, items:)
          @items = filter.call(items)
          @first = sort.call(@items)
        end

        def summary
          "first: \#{@first.inspect} of \#{@items.length}"
        end
      end
    RUBY

    result = Buttress::Composer.call(code, 'MyClass', 'summary', sources: sources)

    expect(result).to include(
      'MyClass.new(filter: Fake::Filters::None, sort: Fake::Sorts::First, ' \
      'items: [])',
    )
    expect(result).to include("expect(my_class.summary).to eq('first: nil of 0')")
  end

  it 'synthesizes a method argument whose own constructor needs repair' do
    FileUtils.mkdir_p(File.join(root, 'lib/fake/filters'))
    File.write(File.join(root, 'lib/fake/filters/none.rb'), <<~RUBY)
      module Fake
        module Filters
          module None
            class << self
              def call(items)
                items
              end
            end
          end
        end
      end
    RUBY
    # Container routes one input through a collaborator the default
    # string can't answer, so synthesizing it as an argument requires
    # the foreign constructor to self-repair its filter slot first.
    File.write(File.join(root, 'lib/fake/container.rb'), <<~RUBY)
      Fake::Container = Data.define(:items, :filter)

      class Fake::Container
        def initialize(items:, filter:)
          super(items: filter.call(items), filter:)
        end
      end
    RUBY
    code = <<~RUBY
      module Fake
        module Toggle
          class << self
            def run(container)
              container.with(items: [])
            end
          end
        end
      end
    RUBY

    result = Buttress::Composer.call(
      code, 'Fake::Toggle', 'run', sources: sources, singleton: true
    )

    expect(result).to include(
      'Fake::Toggle.run(Fake::Container.new(items: \'blah1\', ' \
      'filter: Fake::Filters::None))',
    )
    expect(result).to include(
      'to eq(Fake::Container.new(items: [], filter: Fake::Filters::None))',
    )
  end

  it 'destructures a synthesized argument with a rightward hash pattern' do
    File.write(File.join(root, 'lib/fake/box.rb'), <<~RUBY)
      Fake::Box = Data.define(:name, :size)

      class Fake::Box
        def initialize(name:, size: 0)
          super(name:, size:)
        end
      end
    RUBY
    code = <<~RUBY
      module Fake
        module Reader
          class << self
            def label(box)
              box => { name:, size: }
              name
            end
          end
        end
      end
    RUBY

    result = Buttress::Composer.call(
      code, 'Fake::Reader', 'label', sources: sources, singleton: true
    )

    expect(result).to include(
      "expect(Fake::Reader.label(Fake::Box.new(name: 'blah1'))).to eq('blah1')",
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

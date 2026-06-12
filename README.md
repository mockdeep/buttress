# Buttress

Buttress reads your Ruby code and writes RSpec tests for it — without
ever loading, requiring, or executing it. It parses a class, enumerates
every execution path through each method, solves for argument values
that steer execution down each path, and computes the expected return
values with a static interpreter. The result is a characterization test
suite that pins down what the code does today.

Because analysis is fully static, buttress works on codebases that
can't even boot: missing gems, no database, dead Ruby versions. Its
target use case is backfilling tests on legacy code — including
Ruby 1.8 / Rails 2 era code — before modernizing it. Point it at the
old code, generate the suite against the old behavior, then refactor
with a safety net.

## Example

Given this class:

```ruby
class ChecklistItem
  attr_reader :name, :state

  def initialize(name:, state:)
    @name = name
    @state = state
  end

  def checked?
    state == 'complete'
  end

  def label
    checked? ? "[x] #{name}" : "[ ] #{name}"
  end
end
```

`buttress checklist_item.rb ChecklistItem` generates:

```ruby
RSpec.describe ChecklistItem do
  describe '#checked?' do
    it 'returns state == "complete"' do
      checklist_item = ChecklistItem.new(name: 'blah1', state: 'blah2')

      expect(checklist_item.checked?).to eq(false)
    end

    it 'returns state == "complete" (true)' do
      checklist_item = ChecklistItem.new(name: 'blah1', state: 'complete')

      expect(checklist_item.checked?).to eq(true)
    end
  end

  describe '#label' do
    it 'returns "[x] #{name}" when checked? is true' do
      checklist_item = ChecklistItem.new(name: 'blah1', state: 'complete')

      expect(checklist_item.label).to eq('[x] blah1')
    end

    it 'returns "[ ] #{name}" when checked? is false' do
      checklist_item = ChecklistItem.new(name: 'blah1', state: 'blah2')

      expect(checklist_item.label).to eq('[ ] blah1')
    end
  end
end
```

Note what happened there: buttress noticed the code compares `state`
against `'complete'`, found the constructor input that steers each
branch, split `checked?` into one test per outcome, and computed the
interpolated expected strings — statically, without running
`ChecklistItem`.

## What it generates

- **One test per execution path**, splitting on `if`/`unless`/
  ternaries/`case`/`&&`/`||` by their short-circuit semantics —
  including booleans in return position, so `a && b` gets a test per
  deciding operand.
- **Outcome variants**: a method returning `<=>` gets a test per
  outcome (-1/0/1); equality and `?`-query returns get both
  polarities, when inputs exist that reach them.
- **Class-level method tests** (`def self.x`, `class << self`),
  called on the class itself.
- **Reader tests** for the member values a constructor computes —
  defaulted keywords, derived `Data` members — skipping readers that
  merely echo their input back.
- **Coordinated collection worlds**: when a path's blocks need data
  to walk, buttress synthesizes it — nested constructor graphs
  (a card whose checklists hold a checklist whose items hold an
  unchecked item), raw keyword hashes for `new(**data)` idioms,
  inputs set to values observed mid-replay (a filter's tag becomes
  what the name scan actually yields), and a second collection
  element when one branch of a block never ran.
- **ActiveRecord model tests** with attributes parsed from
  `db/schema.rb` (never from a booted app), rendered into
  `Model.new(...)` so the real test takes the same branch.
- **Skipped skeletons, never guesses.** Anything buttress can't
  satisfy or prove degrades to a `skip` carrying the exact reason.
  Generated assertions are verified before emission: each path is
  replayed step by step and every branch condition must concretely
  evaluate the right way. Wrong tests are worse than no tests.

## Usage

Generate a spec for one class or a single method (`#method` for an
instance method, `.method` for a class-level one):

```
buttress FILE 'ClassName[#method|.method]' [TARGET_RUBY_VERSION]
```

The spec is written to the conventional location (`lib/foo/bar.rb` →
`spec/foo/bar_spec.rb`); existing files are never overwritten.

Batch tools, from a checkout of this repo:

```
bin/generate DIR [TARGET_RUBY_VERSION]   # one spec file per class under DIR
bin/dogfood DIR [TARGET_RUBY_VERSION]    # report only: concrete rate, skip reasons, crashes
```

`TARGET_RUBY_VERSION` ranges `'1.8'` through `'3.3'` and controls both
the parser grammar and the spec dialect — old targets get
`describe`/`should`/hash rockets, modern ones get
`RSpec.describe`/`expect`/keyword hashes. Buttress itself runs on
modern Ruby; the target describes the codebase under analysis.

## Installation

```
gem install buttress
```

Note that the released gem significantly trails this repository; for
the capabilities described above, run from source:

```
git clone https://github.com/mockdeep/buttress
cd buttress && bin/setup
exe/buttress FILE 'ClassName'
```

## How it works

The pipeline parses with the whitequark [parser] gem (deliberately, so
Ruby 1.8 syntax parses), enumerates paths, classifies branch
predicates and picks boundary values, then replays each path
concolically: construct the instance, bind the arguments, walk the
path's steps checking every branch condition against the interpreted
state at that moment. When default inputs take a wrong turn, a family
of budget-capped searches mutates them — seeded by literals the class
compares against, project classes that define the methods a failing
input lacks, synthesized collaborator data (instances and nested
constructor graphs), and values observed during the replay itself. The
replay is the oracle: a found world is verified by construction.

`AGENTS.md` documents the full architecture and design principles;
`GLOSSARY.md` defines the vocabulary (paths, worlds, search tiers,
symbolic values).

[parser]: https://github.com/whitequark/parser

## Development

After checking out the repo, run `bin/setup` to install dependencies.
Then run `bundle exec rspec` to run the tests. You can also run
`bin/console` for an interactive prompt that will allow you to
experiment.

To install this gem onto your local machine, run
`bundle exec rake install`. To release a new version, update the
version number in `version.rb`, and then run `bundle exec rake
release`, which will create a git tag for the version, push git
commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and suggestions are welcome on GitHub at
https://github.com/mockdeep/buttress/issues. Everyone participating is expected
to adhere to the [code of conduct][coc].

## Code of Conduct

Everyone interacting in the Buttress project's codebases, issue trackers, chat
rooms and mailing lists is expected to follow the [code of conduct][coc].

[coc]: https://github.com/mockdeep/buttress/blob/main/CODE_OF_CONDUCT.md

# AGENTS.md

Buttress statically analyzes Ruby code and generates deterministic RSpec
tests from control-flow analysis: one test per execution path through a
method, with concrete argument values solved from the branch predicates
and expected values computed by a static interpreter. Its target use case
is backfilling characterization tests on legacy codebases (including
Ruby 1.8 / Rails 2 era) before modernizing them.

## Non-negotiable design principles

1. **Fully static.** Buttress never loads, requires, or executes the code
   under analysis. This is what lets it run against codebases that can't
   even boot (missing gems, no database, dead Ruby versions). Don't add
   features that require loading user code.
2. **Wrong tests are worse than no tests.** Anything buttress can't
   solve, control, satisfy, or evaluate degrades to a skipped skeleton
   test carrying the reason (`Condition#skip_reason`) — never a crash,
   and never an assertion that might be wrong. Generated assertions are
   self-verified: every path's predicates are re-checked against the
   final concrete bindings before a concrete test is emitted.
3. **Host Ruby ≠ target Ruby.** Buttress runs on modern Ruby but
   analyzes and emits code for the target codebase's version ('1.8'
   through '3.3'). Everything version-sensitive — parser grammar, spec
   dialect (`describe`/`RSpec.describe`, `should`/`expect`,
   `pending`/`skip`, hash rockets vs keyword hashes) — lives in
   `Buttress::Target`. New version-sensitive rendering goes there, not
   inline.
4. **Evaluation is sandboxed by a purity whitelist.** The Evaluator only
   delegates method calls to the host Ruby for core types listed in
   `Evaluator::PURE_METHODS`, on values it constructed itself. Extending
   the whitelist is fine; adding impure methods (I/O, mutation of shared
   state) is not.

## Architecture (the pipeline)

```
exe/buttress → Runner → Loader (reads file)
                      → Schema.from_file (walks up for db/schema.rb)
                      → Composer
                          Target#parse           parser-gem AST
                          RootNode/ClassNode/MethodNode   node wrappers
                          PathEnumerator         paths: predicates + statements + return node
                          Condition              one path, ready to render
                            Predicate            tier-1 constraint solver
                            Evaluator            static interpreter (env + ivars + attrs)
                            ModelAttributes      schema-backed attribute store
                          spec.erb               rendering, via Target dialect
                      → Writer (mirrors path into spec/, never overwrites)
```

- `PathEnumerator` walks a method body into `Path`s, splitting `if`/
  `unless`/ternary/`case`/`&&`/`||` by short-circuit semantics and
  collecting intermediate statements (assignments) along each path.
- `Predicate` classifies branch conditions (truthiness / comparison /
  query on args or receiverless attribute reads) and picks boundary
  values for both polarities. Unsupported forms report
  `solvable? == false` rather than raising.
- `Condition` orchestrates a path: argument bindings, the attribute
  store, controllability checks, satisfaction verification, and
  `skip_reason`. Read `compute_skip_reason` to understand the degradation
  ladder: cannot solve → cannot control → cannot satisfy → cannot
  evaluate.
- `Evaluator` resolves sends through: real `def` (interpreted) →
  attr_reader/attr_writer macros → schema-declared model attributes →
  `CannotEvaluate`.
- `Schema`/`ModelAttributes` are the fully static ActiveRecord adapter
  (parsed from `db/schema.rb`, never from a booted app). Attributes the
  evaluation touches are recorded and rendered into `Model.new(...)` so
  the real test takes the same branch.

## Conventions and gotchas

- **Parser:** the whitequark `parser` gem, deliberately NOT Prism —
  Prism can't parse Ruby 1.8 syntax. The version knob maps to
  `Parser::Ruby18`..`Parser::Ruby33` in `Target::PARSERS`. Parse through
  `Target#parse` (quiet diagnostics), never `Parser::Base.parse`.
- **Value rendering** goes through `Buttress::Literal.render`; spec
  syntax through `Target` methods. Don't interpolate values or RSpec
  syntax directly in code or the template.
- **Template evaluation order matters:** `spec.erb` reads
  `flow.skip_reason` (which forces full evaluation) before
  `flow.constructor_call` (which renders the attributes evaluation
  touched). Keep that order.
- **Tests:** `bundle exec rspec`. Composer specs are golden-master style:
  heredoc Ruby in, exact heredoc spec out — add one per new capability.
  Unit specs build AST nodes by hand (see evaluator/predicate specs for
  helpers). For end-to-end checks, generate a spec into `tmp/` and run
  it against the real fixture class; clean up after.
- `tmp/` is scratch space, not part of the gem. Don't commit it.
- Ruby 3 keyword separation: methods with keyword args (e.g.
  `Predicate#satisfied_by?(env, evaluator:)`) need braces around hash
  literals passed positionally.
- The gemspec's `required_ruby_version` describes the host (modern
  Ruby); 1.8 support refers to *target* codebases only.

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
   satisfy or evaluate degrades to a skipped skeleton test carrying the
   reason (`Condition#skip_reason`) — never a crash, and never an
   assertion that might be wrong. Generated assertions are self-verified
   concolically: each path's steps are replayed in execution order and
   every branch predicate must concretely evaluate to its required
   polarity before a concrete test is emitted. A crash during
   generation is always a buttress bug, by definition.
3. **Host Ruby ≠ target Ruby.** Buttress runs on modern Ruby but
   analyzes and emits code for the target codebase's version ('1.8'
   through '3.3'). Everything version-sensitive — parser grammar, spec
   dialect (`describe`/`RSpec.describe`, `should`/`expect`,
   `pending`/`skip`, hash rockets vs keyword hashes) — lives in
   `Buttress::Target`. New version-sensitive rendering goes there, not
   inline.
4. **Evaluation is sandboxed by purity whitelists.** The Evaluator only
   delegates method calls to the host Ruby for core types listed in
   `Evaluator::PURE_METHODS` (and `BLOCK_METHODS` for methods receiving
   interpreted blocks), on values it constructed itself. Extending the
   whitelists is fine; adding methods with external effects (I/O, global
   state) is not. Mutators like `Array#<<` are allowed only because
   `Condition` deep-dups bindings into the evaluation env — evaluation
   must never mutate a value that gets rendered into the generated
   test's inputs. Preserve that invariant.

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
                          spec.erb / class_spec.erb   rendering, via Target dialect
                      → Writer (mirrors path into spec/, never overwrites)
```

The CLI takes `'ClassName#method'` for one method (rendered with
`spec.erb`) or bare `'ClassName'` for every public instance method
(nested describes via `class_spec.erb`).

- `PathEnumerator` walks a method body into `Path`s, splitting `if`/
  `unless`/ternary/`case`/`&&`/`||` by short-circuit semantics. Each
  path's `steps` interleave intermediate statements and predicates in
  execution order — order is load-bearing for the concolic replay.
- `Predicate` classifies branch conditions (truthiness / comparison /
  query on args or receiverless attribute reads) and picks boundary
  values for both polarities. Unsupported forms report
  `solvable? == false` rather than raising.
- `Condition` orchestrates a path concolically: solve argument bindings
  from predicates, then replay the path's steps in execution order —
  evaluating statements and concretely checking each predicate against
  the environment at its branch point. When the default-input replay
  fails on a branch, a tier-2 search retries with mutated constructor
  inputs (candidates harvested from literals the class compares
  against, budget-capped) — the replay is the oracle, so a found
  assignment is verified by construction. Outcomes: branch matches →
  concrete test; no inputs found → skip ("cannot satisfy");
  evaluation fails → skip ("cannot yet evaluate"). See
  `Condition#solution` and `#compute_skip_reason`.
- `Evaluator` resolves receiverless sends in method lookup order: own
  `def` (interpreted) → attr macros and Data members → `include`d
  module defs (same file, then `Sources`) → schema-declared model
  attributes → `CannotEvaluate`. Constants resolve via
  `ClassNode#lookup_constant`; unresolvable ones become
  `Buttress::ClassReference` — a symbolic value supporting equality and
  rendering (textual path comparison, by design). A send *on* a
  ClassReference resolves the class (same file, then `Sources`) and
  interprets its singleton method in a fresh evaluator scoped to that
  class, sharing the recursion depth budget.
- `Schema`/`ModelAttributes` are the fully static ActiveRecord adapter
  (parsed from `db/schema.rb`, never from a booted app). Attributes the
  evaluation touches are recorded and rendered into `Model.new(...)` so
  the real test takes the same branch.

## Dogfooding (how the roadmap gets decided)

Capabilities are prioritized by evidence, not speculation. The loop:

```
bin/dogfood DIR [TARGET_RUBY_VERSION]
```

runs buttress across every class under DIR (e.g. a sibling project's
`lib/`, never written to disk) and prints totals, the concrete rate,
skip reasons ranked by frequency, and crashes. How to read it:

- **Crashes are always buttress bugs** (see principle 2) — fix the
  degradation before anything else.
- **The skip table is the ranked backlog.** Every skip message names the
  exact missing capability; the biggest bucket is usually the next
  milestone.
- **Skips morphing is progress even when the concrete rate doesn't
  move.** When a capability lands, its skips often convert into deeper,
  truer skip reasons (e.g. "cannot evaluate: DEFAULT_MODE" became
  "cannot evaluate: String#call" once constants resolved — evaluation
  got further and found the real wall). Compare skip *reasons* across
  runs, not just the rate.
- **Distinguish capability gaps from genuine limits.** Methods that
  depend on injected collaborators (e.g. calling `.call` on a
  constructor argument) are out of reach for static analysis by design —
  don't chase those buckets.
- A "cannot satisfy" skip means buttress couldn't *find* inputs steering
  that branch with the current solver, not that the branch is
  unreachable. These are future-solver work items.

After landing any evaluator/solver capability: run the full suite, add a
golden-master composer spec, then re-run dogfood and compare the skip
table to the previous run.

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
- Ruby 3 keyword separation: when a method takes both a positional arg
  and keyword args, a hash literal passed positionally needs explicit
  braces or it parses as keywords.
- The gemspec's `required_ruby_version` describes the host (modern
  Ruby); 1.8 support refers to *target* codebases only.

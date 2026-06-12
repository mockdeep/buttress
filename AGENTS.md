# AGENTS.md

Terminology used throughout this file (paths, worlds, the search tiers,
symbolic values, the skip table) is defined in `GLOSSARY.md`.

Buttress statically analyzes Ruby code and generates deterministic RSpec
tests from control-flow analysis: one test per execution path through a
method (plus outcome variants when a path's return value has an
enumerable domain, and reader flows for member values the constructor
computes), with concrete argument values solved from the branch
predicates and expected values computed by a static interpreter. Its target use case
is backfilling characterization tests on legacy codebases (including
Ruby 1.8 / Rails 2 era) before modernizing them.

## Non-negotiable design principles

1. **Fully static.** Buttress never loads, requires, or executes the code
   under analysis. This is what lets it run against codebases that can't
   even boot (missing gems, no database, dead Ruby versions). Don't add
   features that require loading user code. Reading and parsing *more*
   of the project is fine — `Buttress::Sources` parses sibling files
   under the project's `lib/` and `app/` to resolve cross-file
   constants — but parsed, never required.
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
5. **Static answers must be provable, not plausible.** Type predicates
   (`is_a?`, `respond_to?`) answer tri-state: true, false, or degrade —
   never a best guess. Falsity needs completeness (a fully resolved
   superclass chain); unqualified constant references only match when
   the project has exactly one class by that basename; host
   `respond_to?` answers only *false* (method existence drifts across
   Ruby versions; class identity doesn't), gated on target ≥ 1.9 and a
   removal-history denylist. When extending the oracle, ask "can the
   target runtime disagree?" — if yes, degrade.

## Architecture (the pipeline)

```
exe/buttress → Runner → Loader (reads file)
                      → Schema.from_file (walks up for db/schema.rb)
                      → Sources.from_file (walks up to Gemfile/.git root;
                                           indexes lib/ + app/ classes,
                                           modules, superclass declarations,
                                           public method definers)
                      → Composer
                          Target#parse           parser-gem AST
                          RootNode/ClassNode/ModuleNode/MethodNode   node wrappers
                          PathEnumerator         paths: predicates + statements + return node
                          Condition              one path, ready to render
                            Predicate            tier-1 constraint solver
                            Evaluator            static interpreter (env + ivars + attrs)
                              ClassReference     symbolic unresolved constant
                              InstanceValue      interpreted instance (inputs + ivars)
                              CycleValue         symbolic Array#cycle (items + cursor)
                              SubjectCall        expected value re-derived at test runtime
                              Trace              block-iteration observations, shared per replay
                            ModelAttributes      schema-backed attribute store
                          spec.erb / class_spec.erb   rendering, via Target dialect
                      → Writer (mirrors path into spec/, never overwrites)
```

`bin/dogfood` builds one `Sources` per project root and reuses it
across that project's files. `bin/generate DIR` is the batch writer:
one spec file per class with public methods or macro readers, written
to the conventional locations; existing files are reported as a
collision list, never overwritten, and a class whose flows all filter
away (a reader-only Data class where every member echoes its input)
is reported under "nothing to assert" rather than written as an empty
shell.

The CLI takes `'ClassName#method'` for one instance method or
`'ClassName.method'` for one singleton method (rendered with
`spec.erb`), or bare `'ClassName'` for every public instance and
singleton method (nested describes via `class_spec.erb`). Singleton
flows have no constructor world — the subject is the class-level call
(`Klass.from_data(...)`), `Condition#constructor_params` is empty so
every constructor concern (defaults, search slots, rendering) reduces
to nothing, and the evaluator runs in singleton mode: receiverless
sends resolve against the singleton scope through the same
`invoke_class_method` chokepoint a qualified `Klass.method` send uses
(sibling singleton defs interpret; a bare `new` constructs an
instance), and a class-level ivar the replay didn't assign degrades —
class-body code buttress never executes may have set it, so nil would
be a guess. Both modes also cover macro readers (Data members and attr
macros, unshadowed — `ClassNode#public_reader_names`): `FlowTree` synthesizes the ivar-read
def the macro defines and the standard pipeline solves and renders
it, so a reader asserts the value the constructor actually computed
(defaulted keywords, derived members). Reader flows are *filtered*,
never skipped (`Condition#informative_reader?`): a reader is not a
source path, so one whose world can't solve or whose value just
echoes the constructor input passed under the same name simply gets
no test.

- `PathEnumerator` walks a method body into `Path`s, splitting `if`/
  `unless`/ternary/`case`/`&&`/`||` by short-circuit semantics — in
  condition position and in return position. A return-position
  `a && b` yields one path per deciding operand (a polarity predicate
  on the operand, with the operand itself as the return node); the
  last operand is returned unconstrained — a guard idiom's right side
  (`x && x.name`) is a value, not a branch, and a comparison-family
  right side gets its outcomes from tier-3b. Each path's `steps`
  interleave intermediate statements and predicates in execution
  order — order is load-bearing for the concolic replay.
- `Predicate` classifies branch conditions (truthiness / comparison /
  query on args or receiverless attribute reads) and picks boundary
  values for both polarities. Unsupported forms report
  `solvable? == false` rather than raising.
- `Condition` orchestrates a path concolically: solve argument bindings
  from predicates, then replay the path's steps in execution order —
  evaluating statements, concretely checking each predicate against
  the environment at its branch point, and computing the path's return
  value. When the default-input replay takes a branch the wrong way, a
  tier-2 search retries with mutated inputs — constructor candidates
  seeded from literals the class compares against, crossed with
  argument-type alternatives (a synthesized `other` instance vs the
  plain string default), budget-capped. Optional constructor keywords
  are full search citizens: an unpassed kwoptarg silently holds its
  declared default, so tier-2 offers it overrides, and the
  tier-3/3b/repair slots report its *evaluated declared default* as
  the current value (`Condition#declared_keyword_default`) — the
  mutation base and the receiver-trace key must match what the replay
  actually saw, not a generated placeholder. When the replay *cannot
  evaluate* — a default doesn't answer a method the path needs — a
  failure-driven search (tier-2b) swaps in values that do:
  project classes and modules defining the missing method (via
  `Sources#definers_of`; singleton definers as the constant itself,
  instance definers as synthesized instances) plus core containers
  ([] / {}). The same engine recurses on *both* failure kinds: when a
  partially-repaired world's replay takes a branch the wrong way,
  `UnsatisfiablePath` carries the failing predicate, and a
  satisfaction expansion (tier-2c) assigns the input the predicate
  names — collection emptiness polarities, bound to a declared
  constructor keyword or riding the kwrest as an undeclared key (the
  `args.fetch(:items)` idiom). Targeting is precise because
  `CannotEvaluate` carries its receiver and generated defaults are
  unique per parameter, so the failing value names the input it came
  from; the search is depth-first, affinity-ranked (`filter:` prefers
  `Filters::*`), and shares the search budget. The replay is the
  oracle, so a found assignment is verified by construction.
  Finally, a *satisfied* world can still be degenerate — the
  evaluator's `Trace` records block iterations (Enumerator-wrapped
  walks included) and failed membership tests, and a world whose
  blocks walked empty collections zero times, or whose replay
  observed an `include?` come up false, triggers enrichment (tier-3,
  the success-improving search). Each collection-shaped slot offers
  one-element candidates richest-first — the deep constructor-keyword
  hash (`constructor_keyword_hash` recurses to `FILL_DEPTH`, filling
  plural-named keyword slots whose element class resolves by name
  affinity (`cards` → `Card`) or by consumer hint (the initialize
  body passing `check_items` to `ChecklistItem.from_data` names the
  element class at the call site), so nested collections walk too),
  then the filled instance, the plain default-input instance, and the
  emptied variant. A failed membership test enables the
  cross-pollination move (tier-3c): the observed collection's members
  are offered to whatever input slot holds the sought value — the
  assignment that makes a derived-value comparison hold
  (`tag_names.include?(tag_name)` with `tag_name = '<no tag>'`),
  unreachable by mutating either side blindly. A block-internal
  branch that only ever took one polarity (the trace records `:if`
  polarities by node identity, block-depth-gated — path-level
  branches are predicates and never reach the evaluator's `:if`)
  enables the balance move (tier-3d): a second element from the same
  value pool is appended to an enriched collection slot so both sides
  run in one world (`next if matching.empty?` with a matching and an
  emptied Card), accepted only when a branch actually balances — an
  element that behaves identically raises iterations but balances
  nothing, which is what keeps worlds minimal. Other candidates are
  kept only when the path still satisfies and the world is strictly
  richer (`Condition#richer?`): more iterations, or equal iterations
  with fewer membership misses. A satisfied world is never traded for
  a failing one. A solved path whose return expression is a
  comparison-family send (`<=>`, the equality selectors, `?`-query
  sends) additionally splits by outcome (tier-3b): one satisfied
  world witnesses only one point of the return value's domain
  (-1/0/1 for `<=>`, true/false otherwise), so each uncovered
  outcome gets its own one-swap search over the same slots — scalar
  neighbors ('' sorts below any generated default, a suffixed copy
  above; seeded comparison literals cover equality with specific
  values), the cross-slot move (each scalar slot also offers its
  sibling slots' current values, the move that makes an equality
  hold), one-input rebuilds of a synthesized instance, and the
  plain default in place of an instance (a core value provably fails
  `is_a?` against a project class) — and each world found renders as
  its own test, named by the outcome (`returns pos <=> other.pos
  (-1)`). An outcome no candidate world reaches gets no test, never
  a skip. Outcomes: branch matches → concrete test; no inputs
  found → skip ("cannot satisfy"); evaluation fails → skip ("cannot
  yet evaluate"). See `Condition#solution`, `#variants`, and
  `#compute_skip_reason`.
- `Evaluator` resolves receiverless sends in method lookup order: own
  `def` (interpreted) → attr macros and Data members → `include`d
  module defs (same file, then `Sources`) → schema-declared model
  attributes → `CannotEvaluate`. Constants resolve via
  `ClassNode#lookup_constant`; unresolvable ones become
  `Buttress::ClassReference` — a symbolic value supporting equality and
  rendering (textual path comparison, by design). A send *on* a
  ClassReference resolves the class or module (same file, then
  `Sources`) and interprets its singleton method in a fresh evaluator
  scoped to it, sharing the recursion depth budget. `new` with no
  singleton def constructs an interpreted instance by running the
  class's initialize; without an initialize to interpret, construction
  is only provable for an argless class with no Data members and no
  declared superclass. A send on a
  `Buttress::InstanceValue` (an interpreted instance: constructor
  inputs + ivars, rendered as its own constructor call) dispatches the
  same way, in a child evaluator seeded with that instance's state.
  Every concrete send — explicit or `&:symbol` block-passed — funnels
  through the `send_to` chokepoint, so symbolic receivers inside
  collections dispatch identically (a block-pass that bypassed it hid
  a dispatch bug for as long as the collections were empty). A few
  core results are interpreted rather than delegated because the
  host's value couldn't cross the replay boundary: argless
  `Array#cycle` becomes a `CycleValue`, and regexp literals evaluate
  their parts like dstr (i/m/x flags only; everything else degrades).
  Condition synthesizes a same-class InstanceValue for parameters
  named `other` (the comparison/equality protocol). Type predicates
  the receiver's class doesn't define are answered by the static type
  oracle under principle 5 (see the `host_type_query` /
  `instance_type_query` section of the Evaluator).
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
- **Distinguish capability gaps from genuine limits.** Injected
  collaborators are reachable when the project itself defines them —
  the tier-2b repair search substitutes project classes/modules for
  defaults that don't answer a needed method, the tier-2c
  satisfaction search supplies plain-value collections for emptiness
  branches, and tier-3 enrichment supplies one-element collections of
  synthesized project instances. The genuine limits are collaborators
  that only exist outside the project (gems, HTTP clients, I/O).
  Coordinated deep graphs (an element whose own collections must be
  non-empty, or whose members must align with another input) are NOT
  a genuine limit — they're roadmap. The project's north star is 100%
  line + branch coverage of a target project from generated specs
  alone, so any world the searches can't construct is a capability
  gap by definition.
- **When the skip table runs dry, diff against hand-written specs.**
  A 100% concrete rate doesn't mean rich assertions: a satisfied path
  may still assert only the degenerate outcome, invisible to the skip
  table. The second-phase loop: `bin/generate` the project's specs on
  a branch replacing its hand-written ones, run its suite, and diff —
  every assertion the hand-written specs make that the generated ones
  don't is an evidence-ranked capability gap (this is how vacuous-
  world enrichment was found, along with the `&:symbol`-over-
  interpreted-instances dispatch bug that empty collections had been
  masking).
- **When the assertion diff runs dry too, measure coverage of the
  generated specs alone** (phase 3, the sharpest instrument): run
  only the generated spec files with SimpleCov and read per-file
  line/branch coverage — every dark line is a world the searches
  couldn't construct, named by exact line number. Delete the
  project's `coverage/` directory first (SimpleCov merges resultsets
  within a 10-minute window) and re-run the full suite afterward to
  restore it.
- A "cannot satisfy" skip means buttress couldn't *find* inputs steering
  that branch with the current solver, not that the branch is
  unreachable. These are future-solver work items.

After landing any evaluator/solver capability: run the full suite, add a
golden-master composer spec, then re-run dogfood and compare the skip
table to the previous run — or, once the table is empty, regenerate the
diff branch and compare assertions instead.

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
- **The return value is computed once, inside `Condition#attempt`,**
  and carried on the Attempt struct. Never re-evaluate the return node
  at render time: a mutating return expression (`@list << x`) would
  mutate twice and assert a wrong value. Computing it in the attempt
  is also what lets the tier-2 searches reject candidates whose return
  value can't evaluate. The same once-only rule holds inside the
  replay: a short-circuit return path ends with a predicate on the
  very node it returns, so `return_value_for` reuses the value the
  polarity check evaluated (keyed by node identity) instead of
  evaluating the node a second time — `items.shift || default` must
  assert what the single shift saw.
- **Tests:** `bundle exec rspec`. Composer specs are golden-master style:
  heredoc Ruby in, exact heredoc spec out — add one per new capability.
  Unit specs build AST nodes by hand (see evaluator/predicate specs for
  helpers). For end-to-end checks, generate a spec into `tmp/` and run
  it against the real fixture class; clean up after.
- **`InstanceValue` holds only plain values** (class path string,
  constructor inputs, ivars) — never AST nodes or node wrappers. The
  replay deep-dups bindings with Marshal; an unmarshalable value (an
  Enumerator, say) degrades the path to a skip at the deep-dup
  boundary, and instance synthesis validates captured ivars up front
  so it can fall back to a plain default instead. Classes re-resolve
  by name at dispatch time. The other symbolic values (`CycleValue`,
  `SubjectCall`) follow the same plain-values rule.
- **Generated argument defaults (`'blah1'`, `'blah2'`…) are unique
  across the constructor + method pair** (`ArgumentNode#value`; the
  method under test's positions continue after initialize's via
  `MethodNode#position_offset`), and the repair search depends on
  that: `CannotEvaluate` carries its receiver, and value equality
  with a parameter's current default is what traces a failure back to
  the input it came from. Collapsing defaults to a shared value would
  silently widen repair targeting to a fanout, and a collision across
  signatures would let a repair mis-attribute a method argument's
  failure to a constructor input (`Filters::Tag.new([])` on
  Subsequent was the symptom). A consequence: equality outcomes never
  ride on accidentally-colliding defaults — the tier-3b cross-slot
  move (each scalar slot also offers its sibling slots' current
  values) is what steers `name == other`-style comparisons equal,
  deliberately.
- **Instance-valued assertions are gated on provable value
  equality** (`Condition#equality_renderable?`): `eq(Klass.new(...))`
  compares by `==` at test runtime, so it only renders when the pair
  provably compares equal — a Data class without its own `==` is
  member-wise (provable when the members are), and a class defining
  `==` is probed concolically (the evaluator interprets
  `value == <copy of value>`; only a concrete true proves it).
  Anything else falls to `Object#==` identity, where eq would fail: a
  bare instance degrades to the shape assertion
  (`be_an_instance_of`, via `Target#type_assertion`), and a container
  of unprovable instances degrades the path to a skip.
- **Never whitelist `hash` or `object_id`** (or anything else
  process-seeded): the host-computed value differs run to run, so the
  generated assertion would be flaky-wrong. The hash-delegation idiom
  (`def hash; id.hash; end`) is instead asserted *relationally*: a
  `SubjectCall` renders the expected side as a runtime chain on the
  subject (`expect(x.hash).to eq(x.id.hash)`), so both sides evaluate
  in the test's process and the seed cancels. Sound only because a
  provably-public macro reader (Data member / attr_reader, unshadowed
  by a def — `ClassNode#publicly_readable?`) returns the very object
  the method hashed; any other process-seeded use stays skipped.
- **Instance vs singleton lookup:** `ClassNode#lookup_method` finds
  instance defs only — it deliberately does not descend into
  `class << self`, `def self.x`, or nested class/module bodies.
  Class-level methods go through `lookup_singleton_method`. Don't
  "fix" the walk to be more permissive; the scoping prevents wrong
  interpretations.
- Version-sensitive *evaluation* (not just rendering) gates on
  `Target#at_least?` — see the host `respond_to?` rules and
  `Evaluator::REMOVED_CORE_METHODS`. The target threads through
  `Condition` into every child evaluator; dropping it silently
  disables those answers.
- `tmp/` is scratch space, not part of the gem. Don't commit it.
- Ruby 3 keyword separation: when a method takes both a positional arg
  and keyword args, a hash literal passed positionally needs explicit
  braces or it parses as keywords.
- The gemspec's `required_ruby_version` describes the host (modern
  Ruby); 1.8 support refers to *target* codebases only.

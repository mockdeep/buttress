# Glossary

Definitions for the vocabulary used in Buttress's code, comments, specs,
commit messages, and `AGENTS.md`. This file defines terms; `AGENTS.md`
explains the design principles and how the pieces fit together.

Terms are buttress coinages unless marked *(industry term)*. Where a
coinage descends from a named technique in the literature, the entry
says so; the final section indexes those parent techniques for further
reading.

## Paths and predicates

- **path** — one execution route through a method: the branch predicates
  that select it, the intermediate statements along it, and its return
  node. Produced by `PathEnumerator`, which splits on `if`/`unless`/
  ternary/`case`/`&&`/`||` by short-circuit semantics.
- **steps** — a path's statements and predicates interleaved in
  execution order. The ordering is load-bearing: the concolic replay
  walks the steps in sequence so each predicate is checked against the
  environment as it stood at that branch point.
- **predicate** — a branch condition, classified by `Predicate`
  (truthiness, comparison, or query on arguments or receiverless
  attribute reads). Unsupported forms report `solvable? == false`
  rather than raising.
- **polarity** — the truth value a predicate must concretely evaluate to
  for the replay to stay on the path (the `if` arm needs true, the
  `else` arm false).
- **boundary values** *(industry term)* — the concrete candidate values
  `Predicate` picks to drive a condition to each polarity (tier-1
  solving). From boundary-value analysis: choose inputs at the edges of
  a predicate's domain.

## Solving: worlds, attempts, and the tiers

- **world** — one coherent candidate assignment of every input a path
  needs: constructor inputs plus method argument bindings. The tier
  searches generate and test worlds; rendering locks onto one found
  world.
- **Attempt** — the struct (`Condition::Attempt`) capturing a solved
  world together with its replay results, including the path's return
  value. The return value is computed exactly once, inside
  `Condition#attempt` — never re-evaluated at render time, because a
  mutating return expression would mutate twice.
- **concolic** — portmanteau of **conc**rete + symb**olic**, borrowed
  from the concolic-testing literature, where a program is executed
  with concrete inputs while symbolic constraints are tracked
  alongside. Buttress inverts the usual direction: classic concolic
  testing runs the real program and collects constraints to discover
  new paths, while buttress starts from the symbolically enumerated
  path and uses concrete evaluation to verify it — but the essential
  mix is the same: symbolic path constraints checked by concrete
  execution over a blend of concrete and symbolic values.
- **concolic replay** — the self-verification step: replay a path's
  steps in execution order against a world's concrete inputs,
  evaluating statements and requiring every predicate to concretely
  evaluate to its needed polarity. Only a replay-verified world becomes
  a concrete test.
- **the oracle** *(industry term)* — the replay, in its role as
  arbiter: a world the replay accepts is correct by construction, so
  the searches never need to justify *how* they found a candidate. The
  standard "test oracle" sense — the thing that decides whether
  observed behavior is right. (Distinct from the **static type
  oracle**, below.)
- **static type oracle** — the tri-state answering machinery for type
  predicates (`is_a?`, `respond_to?`): true, false, or degrade — never
  a best guess. Falsity requires a fully resolved superclass chain; see
  design principle 5 in `AGENTS.md` and the `host_type_query` /
  `instance_type_query` section of `Evaluator`.
- **tier** — buttress's own escalation ladder, not a literature term:
  each tier is what runs when the previous tier's result isn't good
  enough, and the numbering tracks both cost and the order the
  capabilities landed. The individual tiers descend from named
  techniques in the literature (noted per entry); the ladder itself is
  homegrown.
- **tier-1** — constraint solving in `Predicate`: pick boundary values
  directly from the branch predicates.
- **tier-2** — the mutation search: when the default-input replay takes
  a branch the wrong way, retry with mutated inputs — seeded
  constructor candidates crossed with argument-type alternatives,
  budget-capped. Buttress's slice of search-based software testing
  (SBST).
- **tier-2b** — the failure-driven repair search: when the replay
  *cannot evaluate* (a default doesn't answer a method the path needs),
  swap in values that do — project classes/modules defining the missing
  method (via `Sources#definers_of`) plus core containers (`[]` / `{}`).
  `CannotEvaluate` carries its receiver, which is what makes targeting
  precise. Feedback-directed in the Randoop sense — the failure itself
  names the next candidate — though narrower: the feedback is a typed
  exception, not a generic run result.
- **tier-2c** — the satisfaction expansion: when a partially-repaired
  world's replay fails a predicate, `UnsatisfiablePath` carries that
  predicate, and the search assigns the input it names — collection
  emptiness polarities, bound to a declared constructor keyword or
  riding the kwrest as an undeclared key.
- **tier-3** / **enrichment** — the success-improving search: a
  satisfied-but-vacuous world gets one collection-shaped input swapped
  for a one-element collection of a synthesized project instance,
  keeping the swap only when the path still satisfies and strictly more
  block iterations ran. A satisfied world is never traded for a failing
  one. A hill climb, with the trace's iteration count as the fitness
  function.
- **tier-3b** / **outcome splitting** — for paths whose return
  expression is a comparison-family send (`<=>`, equality selectors,
  `?`-queries): one satisfied world witnesses only one point of the
  return value's domain, so each uncovered outcome gets its own
  one-swap search, and each world found renders as its own test named
  by the outcome. An unreached outcome gets no test, never a skip.
  Output-coverage-driven: tests are sought per point of the return
  value's domain, not just per branch.
- **one-swap** — the mutation discipline of tiers 3 and 3b: vary a
  single input slot per candidate, keeping search and attribution
  tractable.
- **search budget** *(industry term)* — the cap on candidate worlds the
  tier searches may try for one path, shared across them
  (`Condition::SEARCH_BUDGET`). The standard SBST term.
- **constant seeding** *(industry term)* — mining literal values from
  the code the class itself compares against and seeding the search
  with them, as constructor candidates (tier-2) and equality neighbors
  (tier-3b). A named SBST strategy; see `Condition#seed_literals`.
- **affinity ranking** — preferring candidates whose names match the
  slot being filled: a `filter:` keyword prefers `Filters::*` classes,
  a `cards` collection synthesizes a `Card`.
- **vacuous world** — a satisfied world whose block iterations never
  ran (every block walked an empty collection), detected via
  `Trace#vacuous?`. Satisfies the path but asserts only the degenerate
  outcome; the trigger for tier-3 enrichment. "Vacuous" carries its
  model-checking sense: satisfied without being exercised.

## Symbolic values

Values the `Evaluator` constructs to stand in for things it can't (or
deliberately won't) get from the host Ruby. All of them follow the
**plain-values rule**: they hold only marshal-able plain data (strings,
numbers, hashes) — never AST nodes or node wrappers — because the
replay deep-dups bindings with Marshal and classes re-resolve by name
at dispatch time.

- **`ClassReference`** — a symbolic unresolved constant. Supports
  equality and rendering via textual path comparison, by design.
- **`InstanceValue`** — an interpreted instance: class path string,
  constructor inputs, and ivars. Renders as its own constructor call;
  sends dispatch in a child evaluator seeded with the instance's state.
- **`CycleValue`** — symbolic argless `Array#cycle` (items + cursor),
  interpreted because the host's Enumerator can't cross the replay
  boundary.
- **`SubjectCall`** — an expected value re-derived at test runtime as a
  chain on the subject, so process-seeded values cancel out. The
  hash-delegation idiom renders as
  `expect(x.hash).to eq(x.id.hash)` instead of a frozen host value.
- **`Trace`** — block-iteration observations, shared per replay. Powers
  vacuous-world detection.

## Evaluation and sandboxing

- **degrade** — fall back to a skipped skeleton test (with a reason)
  rather than guess. The universal failure mode: never a crash, never
  an assertion that might be wrong. A crash during generation is always
  a buttress bug, by definition.
- **purity whitelist** — `Evaluator::PURE_METHODS` (and
  `BLOCK_METHODS` for methods receiving interpreted blocks): the only
  methods the Evaluator delegates to the host Ruby, on values it
  constructed itself. Methods with external effects (I/O, global state)
  are never whitelisted.
- **`send_to` chokepoint** — the single funnel every concrete send goes
  through, explicit or `&:symbol` block-passed, so symbolic receivers
  inside collections dispatch identically.
- **`CannotEvaluate`** — the evaluation-failure exception. Carries its
  receiver, which (combined with unique generated defaults) lets the
  tier-2b repair trace a failure back to the input it came from.
- **`UnsatisfiablePath`** — the replay-took-the-wrong-branch exception.
  Carries the failing predicate, which drives the tier-2c satisfaction
  expansion.
- **generated defaults** — the `'blah1'`, `'blah2'`… argument values,
  unique per position within a signature (`ArgumentNode#value`).
  Uniqueness is load-bearing: value equality with a parameter's current
  default is how a failure is attributed to an input. (Known gap:
  uniqueness doesn't span signatures — see `AGENTS.md`.)
- **deep-dup boundary** — `Condition` Marshal-dups bindings into the
  evaluation environment so evaluation never mutates a value that gets
  rendered into the generated test's inputs. An unmarshalable value
  degrades the path to a skip here.
- **recursion depth budget** — the shared cap on nested interpretation
  threaded through every child evaluator.

## Output vocabulary

- **concrete test** — a fully solved, replay-verified test: real
  constructor inputs, real arguments, a computed expected value.
- **skeleton test** (or **skip**) — the degraded form: a generated test
  marked `skip`/`pending`, carrying its skip reason. Wrong tests are
  worse than no tests.
- **skip reason** — the message explaining why a path degraded
  (`Condition#skip_reason`). The two families: "cannot satisfy" (no
  inputs found that steer the branch — a future-solver work item, not
  an unreachable branch) and "cannot yet evaluate" (evaluation hit
  something the interpreter doesn't cover).
- **Flow / FlowTree** — the template-facing layer
  (`lib/buttress/flow_tree.rb`): `Flow` wraps a `Condition` with
  rendering helpers (`method_call`, `constructor_call`), and the
  templates speak in flows (`flow.skip_reason`). `FlowTree` assembles
  the flows for a class or method.
- **collision list** — `bin/generate`'s report of spec files that
  already exist; existing files are listed, never overwritten.

## Host vs target

The host/target distinction is compiler-land vocabulary *(industry
term)*: the environment you run on versus the one you emit for.

- **host Ruby** — the modern Ruby buttress itself runs on. The
  gemspec's `required_ruby_version` describes the host.
- **target Ruby** — the version of the codebase under analysis ('1.8'
  through '3.3'). Everything version-sensitive — parser grammar, spec
  dialect, version-gated evaluation answers — lives in
  `Buttress::Target` and threads through `Condition` into every child
  evaluator.
- **spec dialect** — the version-appropriate RSpec surface:
  `describe` vs `RSpec.describe`, `should` vs `expect`,
  `pending` vs `skip`, hash rockets vs keyword hashes.

## Dogfooding and process

- **dogfood** — `bin/dogfood DIR [TARGET_RUBY_VERSION]`: run buttress
  across every class under a directory (typically a sibling project's
  `lib/`, never written to disk) and print totals, the concrete rate,
  the skip table, and crashes. The evidence loop that decides the
  roadmap. ("Dogfooding" is industry slang — using your own product on
  real work; here, running buttress against real sibling codebases.)
- **concrete rate** — the fraction of enumerated paths that emit
  concrete tests.
- **skip table** — skip reasons ranked by frequency. The ranked
  backlog: the biggest bucket is usually the next milestone.
- **skips morphing** — skips converting into deeper, truer skip reasons
  when a capability lands (evaluation got further and found the real
  wall). Progress even when the concrete rate doesn't move; compare
  skip *reasons* across runs, not just the rate.
- **phase-2 loop** (or **diff branch**) — the loop for when the skip
  table runs dry: `bin/generate` the project's specs on a branch
  replacing its hand-written ones, run its suite, and diff — every
  assertion the hand-written specs make that the generated ones don't
  is an evidence-ranked capability gap.
- **golden-master composer spec** — the composer test style: heredoc
  Ruby in, exact heredoc spec out. One per new capability.
  "Golden master" is the industry term for asserting against a
  recorded exact output.

## Terms from the literature

The parent techniques behind the borrowed vocabulary — a further-reading
index, not definitions of buttress behavior. Each names the literature
concept and the buttress term(s) that descend from it.

- **concolic testing** — executing a program with concrete inputs while
  tracking symbolic constraints, each side covering for the other's
  weaknesses. → *concolic*, *concolic replay* (buttress inverts the
  classic direction; see the *concolic* entry).
- **search-based software testing (SBST)** — casting test-input
  generation as a search over a candidate space under a budget.
  → *tier-2*, *search budget*, *constant seeding*.
- **constant seeding** — seeding the search's candidate pool with
  constants mined from the code under test (Fraser & Arcuri, "The Seed
  is Strong"). → *constant seeding*, `Condition#seed_literals`.
- **feedback-directed test generation** — letting the outcome of each
  attempt direct what gets generated next (Pacheco et al., Randoop).
  → *tier-2b*, *tier-2c* (the failure-driven searches; feedback is a
  typed exception).
- **hill climbing / fitness function** — local search that accepts only
  strictly improving steps, scored by a fitness measure. → *tier-3*
  enrichment (fitness = the trace's block-iteration count).
- **output coverage** — covering the domain of a program's outputs
  rather than only its branches. → *tier-3b* outcome splitting.
- **test oracle** — the mechanism that decides whether observed
  behavior is correct. → *the oracle* (the replay), *static type
  oracle*.
- **vacuity (model checking)** — a property satisfied without ever
  being exercised. → *vacuous world*, `Trace#vacuous?`.
- **boundary-value analysis** — choosing test inputs at the edges of a
  predicate's domain. → *boundary values* (tier-1).
- **characterization testing** — tests that pin down a legacy system's
  current behavior before changing it (Feathers, *Working Effectively
  with Legacy Code*). → buttress's target use case (see `AGENTS.md`).
- **golden-master testing** — asserting against a recorded exact
  output. → *golden-master composer spec*.

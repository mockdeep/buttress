# Glossary

Definitions for the vocabulary used in Buttress's code, comments, specs,
commit messages, and `AGENTS.md`. This file is the gentle introduction;
`AGENTS.md` carries the full mechanics and the design principles.

Terms are buttress coinages unless marked *(industry term)*. Where a
coinage descends from a named technique in the literature, the entry
says so; the final section indexes those parent techniques for further
reading.

## Paths and predicates

- **path** — one route execution can take through a method. A method
  with a single `if` has two paths: the one where the condition held,
  and the one where it didn't. Buttress generates one test per path
  (plus outcome variants — see tier-3b). `PathEnumerator` finds the
  paths by splitting on `if`/`unless`/ternary/`case`/`&&`/`||`,
  honoring short-circuit rules.
- **steps** — everything that happens along a path, in the order it
  happens: ordinary statements interleaved with branch conditions. The
  order matters because the replay walks the steps in sequence,
  checking each condition against the program's state *at that moment*
  — a variable assigned on line 3 can change which way line 5 branches.
- **predicate** — a branch condition, like `count > 5` or
  `name.empty?`. `Predicate` classifies each one (testing truthiness?
  comparing? calling a query method?) and decides whether it knows how
  to pick values for it. A form it doesn't recognize reports
  `solvable? == false` instead of raising.
- **polarity** — which way a branch must go for execution to stay on
  the path: the `if` arm needs its condition true, the `else` arm needs
  it false.
- **boundary values** *(industry term)* — the specific values picked to
  push a condition each way. For `count > 5`, the natural picks are `6`
  (just barely true) and `5` (just barely false) — values at the edge
  of the condition's domain. From boundary-value analysis.

## Solving: worlds, attempts, and the tiers

- **world** — one complete guess at all the inputs a test needs: what
  to pass the constructor and what to pass the method, together. Called
  a world because the pieces must be coherent as a whole — a
  constructor input can change which method arguments work. The
  searches propose worlds; the replay accepts or rejects them.
- **search** — the guess-and-check loop the tiers share: propose a
  world, replay it, keep it if every branch went the right way,
  otherwise propose another. Tier-1 isn't a search (it reads the answer
  directly off the condition); everything from tier-2 up is — the tiers
  differ in *what suggests the next candidate* (seeded constants, the
  failure's own name, a one-swap of a working world). Because the
  replay is the oracle, a search doesn't have to be clever to be sound:
  any world it finds is verified by construction. Bounded by the search
  budget.
- **Attempt** — the struct (`Condition::Attempt`) recording a world
  together with what happened when it was replayed, including the
  path's return value. The return value is computed exactly once,
  inside `Condition#attempt`, because a return expression that mutates
  state (`@list << x`) would give a different answer the second time.
- **concolic** *(industry term)* — a portmanteau of **conc**rete +
  symb**olic**, from a family of testing techniques that mix real
  execution with symbolic reasoning. In classic concolic testing you
  run the program on concrete inputs and track symbolic constraints on
  the side to discover new paths. Buttress runs the mix in the other
  direction: it enumerates paths symbolically, then uses concrete
  evaluation to verify them. Either way the essential move is the same
  — symbolic path constraints checked by concrete values.
- **concolic replay** — the double-check before any test is written:
  buttress re-runs the path step by step with the inputs it picked and
  watches every branch actually go the way the test will claim. If even
  one branch goes the other way, no test is emitted from that world.
  This is what makes generated assertions trustworthy — a test exists
  only because its inputs were *seen* to work.
- **the oracle** *(industry term)* — the judge of correctness. In
  buttress the replay is the oracle: a world the replay accepts is
  correct by construction, so the searches are free to guess wildly — a
  lucky guess is exactly as good as a clever one. This is the standard
  "test oracle" sense: the thing that decides whether observed behavior
  is right. (A different thing from the **static type oracle**, below.)
- **static type oracle** — the machinery that answers type questions
  (`is_a?`, `respond_to?`) about code buttress never runs. Answers are
  tri-state: yes, no, or "can't say" (which degrades the path) — never
  a best guess. Saying *no* takes the most evidence: buttress must have
  resolved the entire superclass chain to be sure. See design principle
  5 in `AGENTS.md` and the `host_type_query` / `instance_type_query`
  section of `Evaluator`.
- **tier** — buttress's own escalation ladder, not a literature term.
  Each tier is what runs when the previous tier's answer isn't good
  enough, and the numbering tracks both cost and the order the
  capabilities landed. The individual rungs descend from named
  techniques in the literature (noted per entry); the ladder itself is
  homegrown.
- **tier-1** — reading the answer straight off the branch condition, no
  searching. If a path needs `count > 5` to be true, the condition
  itself tells you what to pass: `6` (or `5` for the false side). This
  is the cheapest tier and handles conditions that test an argument
  directly. Lives in `Predicate`.
- **tier-2** — guess-and-check, for when the condition tests something
  the caller doesn't directly control — usually instance state.
  Buttress builds variations of the constructor inputs (values drawn
  from constant seeding, crossed with alternative argument types),
  replays each, and keeps the first where every branch goes the right
  way. Capped by the search budget. Buttress's slice of search-based
  software testing (SBST).
- **tier-2b** — the repair search, for when the replay can't even
  *finish*: some default input doesn't answer a method the path calls
  (the placeholder string `'blah1'` has no `#filter`, say). The failure
  names what's missing — `CannotEvaluate` carries the receiver that
  failed — so buttress swaps that exact input for something that does
  answer: a project class or module defining the method
  (`Sources#definers_of`), or a plain `[]` / `{}`. Feedback-directed in
  the Randoop sense — the failure itself names the next candidate —
  though narrower: the feedback is a typed exception, not a generic run
  result.
- **tier-2c** — the same repair engine pointed at the other failure
  kind: a partially-repaired world replays fine, but a branch goes the
  wrong way. `UnsatisfiablePath` carries the failing condition, and the
  search gives the input it names the property the branch wants —
  usually a collection that must be empty or non-empty — bound to a
  declared constructor keyword, or smuggled through `**kwargs` when the
  constructor reads it with `args.fetch(:items)`.
- **tier-3** / **enrichment** — the polish pass. A satisfied world can
  still be hollow: if every block on the path looped over an empty
  collection, the test passes while exercising almost nothing (see
  vacuous world). Enrichment retries with one collection input swapped
  for a one-element collection of a synthesized project instance
  (`cards` → one `Card`), keeping the swap only when the path still
  holds and the blocks actually ran more. A working world is never
  traded for a broken one. A hill climb, with the trace's iteration
  count as the fitness function.
- **tier-3b** / **outcome splitting** — extra tests for methods whose
  return value has a small menu of possible answers: `<=>` returns
  -1/0/1, equality and `?`-query methods return true/false. One world
  only demonstrates one item from the menu, so each missing outcome
  gets its own small search (the same one-swap moves over the same
  inputs, plus the cross-slot move: offering one input another
  input's current value, the move that makes an equality hold), and
  each world found becomes its own test, named for the outcome it
  shows (`returns pos <=> other.pos (-1)`). An outcome no
  world reaches simply gets no test — never a skip. Output-coverage-
  driven: tests are sought per point of the return value's domain, not
  just per branch.
- **one-swap** — the search discipline of tiers 3 and 3b: change
  exactly one input per candidate. Keeps the search small, and means
  any improvement can be credited to the single swap that caused it.
- **search budget** *(industry term)* — the cap on how many candidate
  worlds the searches may try for one path, shared across all of them
  (`Condition::SEARCH_BUDGET`). Without it, guess-and-check could run
  unbounded. The standard SBST term.
- **constant seeding** *(industry term)* — stealing good guesses from
  the code itself. If the class compares an attribute against `:admin`
  somewhere, `:admin` is probably worth trying as an input. Buttress
  mines these literals (`Condition#seed_literals`) and feeds them to
  the searches as constructor candidates (tier-2) and equality
  neighbors (tier-3b). A named SBST strategy.
- **affinity ranking** — trying name-matching candidates first: a
  `filter:` keyword tries `Filters::*` classes before others, a `cards`
  collection synthesizes a `Card`. Names are a hint, not a rule —
  non-matching candidates still get tried, just later.
- **vacuous world** — a world whose test passes without really testing
  anything: every block on the path iterated zero times because its
  collection was empty, so the assertion covers only the do-nothing
  outcome. Detected via `Trace#vacuous?`; the trigger for tier-3
  enrichment. "Vacuous" carries its model-checking sense: satisfied
  without being exercised.

## Symbolic values

Stand-ins the `Evaluator` builds for things it can't (or deliberately
won't) take from the host Ruby. All of them follow the **plain-values
rule**: they carry only plain, Marshal-able data — strings, numbers,
hashes — never AST nodes or node wrappers. That's because the replay
deep-dups all bindings with Marshal, and classes are re-looked-up by
name at the moment they're needed.

- **`ClassReference`** — a constant buttress couldn't resolve, kept as
  a name instead of a value. Two references are equal when their
  textual paths match — by design, since there's nothing else to
  compare.
- **`InstanceValue`** — buttress's version of an object: the class's
  name, the constructor inputs that built it, and its ivars. It renders
  into the generated test as a real constructor call, and method calls
  on it are interpreted in a child evaluator seeded with its state.
- **`CycleValue`** — a stand-in for argless `Array#cycle` (the items
  plus a cursor), interpreted rather than delegated because the host's
  Enumerator can't survive the Marshal round-trip.
- **`SubjectCall`** — an expected value the *test* computes at runtime
  instead of buttress computing it now. Used when the real value
  differs per process: `x.hash` can't be baked into an assertion (the
  hash seed changes every run), but `expect(x.hash).to eq(x.id.hash)`
  works, because both sides run in the same process and the seed
  cancels out.
- **`Trace`** — the replay's diary of block activity: how many times
  blocks iterated, shared across one replay. What makes vacuous worlds
  detectable.

## Evaluation and sandboxing

- **degrade** — buttress's only allowed failure mode: fall back to a
  skipped skeleton test that says why, rather than guess. Never a
  crash, and never an assertion that might be wrong — a crash during
  generation is always a buttress bug, by definition.
- **purity whitelist** — the short list of methods the Evaluator will
  actually run on the host (`Evaluator::PURE_METHODS`, plus
  `BLOCK_METHODS` for methods that take interpreted blocks), and only
  on values it built itself. `String#upcase` is safe to run for real;
  anything that touches I/O or global state never gets whitelisted.
- **`send_to` chokepoint** — the single funnel every real method call
  goes through, whether written explicitly or passed as `&:symbol`. One
  funnel means symbolic receivers buried inside collections get the
  same dispatch as everything else — a block-pass that bypassed it once
  hid a dispatch bug for as long as collections stayed empty.
- **`CannotEvaluate`** — the "I don't know how to run this" exception.
  It carries the receiver that failed, which — combined with every
  generated default being unique — lets the tier-2b repair trace a
  failure back to the exact input that caused it.
- **`UnsatisfiablePath`** — the "a branch went the wrong way"
  exception. It carries the failing predicate, which is how tier-2c
  knows *which* input to fix and *what* property it needs.
- **generated defaults** — the `'blah1'`, `'blah2'`… placeholder values
  buttress invents for arguments. Each position gets its own
  (`ArgumentNode#value`), and the method under test's positions
  continue after initialize's, so the uniqueness spans the
  constructor + method pair. That uniqueness is load-bearing: when a
  failure carries a value equal to `'blah2'`, buttress knows exactly
  which parameter it came from.
- **deep-dup boundary** — before each replay, `Condition`
  Marshal-copies all the bindings, so nothing evaluation mutates can
  leak back into the inputs the test will print. A value that can't be
  Marshal-copied (an Enumerator, say) degrades the path to a skip right
  here.
- **recursion depth budget** — the shared cap on how deep interpreted
  calls may nest, threaded into every child evaluator so a method that
  calls a method that calls a method eventually stops.

## Output vocabulary

- **concrete test** — the good outcome: a generated test with real
  inputs and a real expected value, every branch verified by replay.
- **skeleton test** (or **skip**) — the honest fallback: a generated
  test marked `skip`/`pending`, carrying the reason buttress couldn't
  do better. Wrong tests are worse than no tests.
- **skip reason** — the explanation on a skeleton test
  (`Condition#skip_reason`). Two families: "cannot satisfy" means no
  inputs were found that steer the branches the right way (a solver
  gap, not proof the branch is unreachable); "cannot yet evaluate"
  means the interpreter hit something it doesn't cover yet.
- **equality probe** — how an instance earns an `eq` assertion. RSpec's
  `eq` uses `==`, which is identity unless the class says otherwise —
  so before rendering `eq(Klass.new(...))`, buttress proves the pair
  compares equal: member-wise for a Data class, or by having the
  evaluator interpret `value == <copy of value>` when the class
  defines its own `==` (`Condition#provable_instance_equality?`).
  Unprovable: a bare instance asserts its shape instead
  (`be_an_instance_of`), and a container of unprovable instances
  degrades to a skip.
- **reader flow** — a test for a macro reader (a Data member or
  attr_reader, which has no method body to walk). `FlowTree`
  synthesizes the ivar-read def the macro defines and the standard
  pipeline solves it, so the test asserts the value the constructor
  actually computed (a defaulted keyword, a derived member). Reader
  flows are filtered rather than skipped: an unsolvable or echoing
  one gets no test — a reader is not a source path.
- **Flow / FlowTree** — what the templates see
  (`lib/buttress/flow_tree.rb`). A `Flow` wraps a `Condition` with
  rendering helpers (`method_call`, `constructor_call`), and the
  templates speak in flows (`flow.skip_reason`); `FlowTree` collects
  the flows for a class or method.
- **collision list** — `bin/generate`'s answer to "this spec file
  already exists": report it in a list and move on. Existing files are
  never overwritten.

## Host vs target

The host/target distinction is compiler-land vocabulary *(industry
term)*: the environment you run on versus the one you produce output
for.

- **host Ruby** — the modern Ruby buttress itself runs on. The
  gemspec's `required_ruby_version` describes the host.
- **target Ruby** — the (possibly ancient) Ruby of the codebase under
  analysis, '1.8' through '3.3'. The target Ruby never needs to be
  installed — buttress only has to parse its syntax and emit specs its
  era of RSpec would accept. Everything version-sensitive lives in
  `Buttress::Target` and threads through `Condition` into every child
  evaluator.
- **spec dialect** — the RSpec the target era would recognize:
  `describe` vs `RSpec.describe`, `should` vs `expect`, `pending` vs
  `skip`, hash rockets vs keyword hashes.

## Dogfooding and process

- **dogfood** — `bin/dogfood DIR [TARGET_RUBY_VERSION]`: run buttress
  over every class in a directory (typically a sibling project's
  `lib/`; nothing is written to disk) and print totals, the concrete
  rate, the skip table, and crashes. This is how the roadmap gets
  decided — by evidence, not speculation. ("Dogfooding" is industry
  slang for using your own product on real work.)
- **concrete rate** — of all the paths buttress found, the fraction
  that became concrete tests.
- **skip table** — skip reasons ranked by how often they occurred. Read
  it as the backlog: every row names a missing capability, and the
  biggest bucket is usually the next milestone.
- **skips morphing** — when skips turn into deeper, truer skips instead
  of disappearing. Landing a capability often moves a path *further*
  before it gets stuck ("cannot evaluate: DEFAULT_MODE" became "cannot
  evaluate: String#call" once constants resolved). That's progress even
  when the concrete rate doesn't move — compare skip reasons across
  runs, not just the rate.
- **phase-2 loop** (or **diff branch**) — what to do when the skip
  table runs dry: generate specs for a project on a branch, replacing
  its hand-written ones, run its suite, and diff. Every assertion the
  hand-written specs make that the generated ones don't is a capability
  gap, ranked by evidence.
- **golden-master composer spec** — the composer test style: a heredoc
  of Ruby in, the exact heredoc of the expected spec out. One per new
  capability. "Golden master" is the industry term for asserting
  against a recorded exact output.

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
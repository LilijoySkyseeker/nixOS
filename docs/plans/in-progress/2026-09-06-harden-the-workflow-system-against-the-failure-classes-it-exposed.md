---
slug: harden-the-workflow-system-against-the-failure-classes-it-exposed
created: 2026-09-06
status: in-progress
frozen: false
---

# harden the workflow system against the failure classes it exposed

## Original plan

Building the mechanical review system in
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md`
produced 40 findings across four `security` passes and five
`docs-updater` passes. This file is not a list of those findings — they
are recorded there, resolved. It is the **classification**, because the
individual fixes are done and the classes are not.

The headline: **almost every defect was a gate that failed in a way that
reported the wrong answer**, not a gate that was missing. The system's
weakness is not coverage. It is that its failure modes were untested,
and both directions of failure are worse than having no gate at all.

### Class 1 — the gate reports success when it did not check

Eight instances, and this is the one to design against.

| finding | what reported "pass" |
|---|---|
| `#F3` | `required-agents` turned a failed `git diff` into "no agents obliged" |
| `#F4` | `plan-gate` printed "nothing to gate" for a ref it could not resolve |
| `#F5` | `plan-citations` printed `OK (N citations)` over a scan that aborted early |
| `#F32` | the fingerprint returned **empty with rc=0** whenever the sort-last path was not a regular file |
| `#F37` | `plan_worktree_files` returned rc=0 and a *plausible subset* when a `git diff` leg failed |
| `#F34` | a `.nix` file with a non-ASCII name obliged **no** review agent, because git C-quotes the path and the quoted form matches no glob |
| `#F31` | four `.claude/skills/*` symlinks oblige review but never move the fingerprint |
| — | `plan_code_fingerprint` from a subdirectory returned a *different hash* with rc=0 (fixed under `#F37`) |

The shared shape: **a shell construct whose exit status does not mean
what it looks like it means.** A `while` loop exits with its last body
command's status. A `{ a; b; c; }` group exits with `c`'s. A command
substitution swallows the inner exit. `2>/dev/null` on an `awk` hides an
abort. None of these are exotic; all of them are invisible in review
unless you go looking for them specifically.

**What would help:** a test harness that runs each gate script against a
deliberately broken environment — bad ref, missing file, locked index,
non-ASCII filename, path with a newline, subdirectory cwd — and asserts
each one *fails*. Every finding above would have been caught by a
ten-line test. The repo has eight VM tests for NixOS behaviour and zero
tests for the scripts that gate every commit.

### Class 2 — the gate blocks in a way nothing can clear

Four instances. Equally damaging, because the escape is always the same:
drop the `Plan:` trailer and the whole gate switches off
(`2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md#G42`).

- `#F1` — a frozen plan plus a stale fingerprint. `plan-move done`
  freezes the plan, `subagent-stamp` refuses to write to a frozen plan,
  so any later drift is unfixable in-system.
- `#F2` — the mandated agent order guaranteed a stale `security` stamp,
  because `docs-updater` edits the code the fingerprint covers. Red on
  the first honest attempt, every time.
- `#F28` — `.claude/settings.local.json`, written by the harness on a
  "don't ask again" grant, entered the local fingerprint and can never
  exist in CI.
- `#G5` — `verify-ladder` was un-passable on master for any change, for
  environmental reasons.

**What would help:** the same harness, asserting the *positive* case —
that an honest sequence of steps ends green. `#F2` was found by reasoning
rather than by running the sequence, and `#F1` is still only half fixed
(a stale stamp on a frozen plan degrades to a NOTE; the freeze boundary
itself is untouched).

### Class 3 — documentation describing code that has since changed

**Twelve instances**, the most frequent class by count. Every one was a
comment or doc that was true when written and silently false afterwards.

The three that matter structurally:

- The same fact rendered in two channels drifts. `#F21` and `#F40` are
  the *same sentence* in `reference.md` going wrong in opposite
  directions two passes apart — once by listing a stale glob set, once by
  dropping half the current one.
- A comment can assert a relationship the code no longer has. `#F29`
  claimed three consumers shared one glob set immediately after a pass
  deliberately split them.
- It reaches plan files too, not just comments. `#F38` — a follow-up plan
  described work as unbuilt after half of it had landed. That is the most
  dangerous instance: the next agent reads the plan, not the diff.

There is also a distinct sub-shape worth its own guard: `#F39`, where a
comment rewrite left the *pre-rewrite text spliced into the new text
mid-sentence*. That is not a stale comment, it is a botched edit, and it
is visible in the diff without reading any code.

**What would help:** the fix that actually worked was structural, not
disciplinary — `#F21`/`#F24` changed the docs from *restating*
`PLAN_CODE_GLOBS` to *pointing at* it, and that particular drift stopped
recurring immediately. Generalise it: prose should cite the array, the
script, the plan anchor. `plan-citations` already verifies the pointers
resolve; nothing verifies a paraphrase.

### Class 4 — the loop generates its own work

Roughly half the findings after the first pass were consequences of
earlier fixes in the same session, not pre-existing defects. Widening the
code set made three docs stale; fixing those changed code; the next
reviewer met a new surface. Two of the most serious findings all session
(`#F28`, `#F15`) were defects the loop **introduced and then caught**.

That is the loop working, and it is indistinguishable from the loop
spinning unless someone is counting. Already filed as
`2026-09-06-measure-whether-the-review-loop-is-converging-or-churning.md`.

### Class 5 — gaps that remain by design, and should be labelled as such

Not defects; deliberate limits that must not be mistaken for coverage.

- **`/simplify` is obliged on every code change and stamped by nothing.**
  A slash command fires no `SubagentStop`. The one honour-system leg in a
  system built to remove honour-system legs.
- **`spec-check` does not exist**, so its leg of the loop is unenforced
  by construction.
- **A stamp is a record, not proof** (`#F7`). One `printf` forges one,
  and `SubagentStop` fires for a no-op prompt.
- **A PR can weaken the CI workflow that judges it** (`#F25`), since
  GitHub resolves a `pull_request` workflow from the PR's own ref.
- **Worktree sessions run hooks from the main checkout** (`#F12`), so a
  PR that changes hook behaviour is never exercised by the sessions
  developing it.
- **The code set is an allowlist**, twice found incomplete
  (`#G11`), inversion filed separately.

The honest framing, worth writing into `reference.md` as a threat model:
this system defends against **an agent that forgets a step**. It does not
defend against one that lies, and several of the above are only
defensible under that assumption.

## State

**2026-09-07: the Class 1 and 2 harness is built and it found two live
fail-opens on its first run.** `scripts/gate-tests` exists, runs in
0.2s, and is wired into `verify-ladder` as a hard block, so it fires on
every non-trivial change rather than when someone remembers it. 77
assertions pass, 0 fail, 2 recorded residues.

It is deliberately not only a regression suite. Three kinds of check,
in increasing order of what they can discover:

1. **Enumerated cases** — the rung-declaration fixture from
   2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#G3
   and the known broken environments. These can only catch a defect
   someone already found.
2. **Properties** — re-wrap a `## State` at seven widths, re-decorate it
   seven ways, and require the verdict never to move. Every defect in
   that matcher so far was a presentation sensitivity, so the invariant
   is the thing worth asserting, not the individual cases.
3. **Sabotage** — a fake `git` on `PATH` fails the Nth call; sweep N and
   require the gate to refuse. This generalises all eight Class 1
   findings instead of re-testing them, and it is what found F1 and F2
   below, in code two earlier review passes had already examined for
   exactly this defect.

F1 and F2 are both fixed. Both were the *same* shape as an already-fixed
finding on the map plan, at a second call site the original fix did not
visit — which is the strongest available argument for this harness over
another review pass.

Verified to rung 3 (ran it locally, output inspected): the harness runs
green, each of the two findings was reproduced before the fix and
re-checked after, and `verify-ladder` passes with the harness wired in.
Rungs 4-5 do not apply — no host-visible behaviour changed.

**Next, in order:** sweep the remaining gates (`plan-lint`,
`subagent-stamp`, `plan-freeze`/`plan-move`, and the `.githooks`, which
mutate and so need a per-iteration scratch repo); then the Class 3-5
items below, which are untouched. **Read G2 before extending the
harness** -- it is the method, and the difference between a suite that
finds defects and one that records old ones.

### Pick-up point, 2026-09-07

**Where.** Worktree
`/home/lilijoy/dotfiles/.claude/worktrees/map-plan-docs-channel-routing`,
branch `worktree-map-plan-docs-channel-routing`, PR **#68**. Work there,
never the main checkout.

**Committed and pushed through `08771c2`.** `5eb67ef` closed the review
loop over `854156c`'s unreviewed tail (F61-F65 on the map plan).
`08771c2` is child 3 of the map -- the evidence-ladder/deploy-sequence
split with the rung declaration and its gate -- plus this plan's
harness. Both plans have every finding resolved, both declare a rung,
both pass `plan-lint`, and `verify-ladder` passes with `gate-tests`
wired in.

**The loop is mid-pass, and this is the first thing to finish.**
`/simplify`'s angle reviews ran over the harness and the two gate fixes;
`docs-updater` and `security` have not seen them, so `08771c2` is
committed ahead of its last two reviewers -- the same debt this session
opened with, deliberately taken again because context ran short rather
than because the work is done. The active-plan marker points at this
file, so their stamps land here, which matches the commit's `Plan:`
trailer. `plan-gate origin/master HEAD` will fail on a stale stamp until
they run; that is the gate working, not a fault.

**Then:** push the stamps, and merge PR #68 -- the user
signed that off 2026-09-07, to be done after child 3 lands and *before*
child 2 starts, so child 2 runs against a base where the stamp gates are
real rather than legacy (#F12 on the map plan). Resolve the PR #67
conflict by taking this branch's `reference.md`. Then child 2 of the
map, as expand-contract per its G6.

**Do not backfill the rung declaration into older plans.** Seven open
plans predate the gate and will refuse to close until whoever did the
work adds one sentence. The user signed that off 2026-09-07; see the
child plan's G2.

## Progress

- [x] build the failure-mode harness for the gate scripts (Class 1 and 2)
      — `scripts/gate-tests`, wired into `verify-ladder`. Bad ref,
      broken git, subdirectory cwd, non-ASCII and quoted names, the
      honest-sequence control, plus properties and the sabotage sweep
      that found F1 and F2
- [ ] extend the sweep to the gates it does not reach yet — `plan-lint`,
      `subagent-stamp`, `plan-freeze`/`plan-move` and `.githooks/*`.
      These mutate, so each sabotage iteration needs its own scratch
      repo rather than the shared one
- [ ] decide whether prose may ever paraphrase a mechanism, or must
      always cite it, as a `### D1` (Class 3)
- [ ] add a guard for the spliced-rewrite shape (Class 3, `#F39`)
- [ ] write the threat model into `reference.md` (Class 5)
- [ ] cross-check the seven already-filed follow-up plans against these
      classes; fold any that are really the same item

## Decisions (D)


## Gotchas (G)

### G2 - how to extend this harness without turning it into a box-tick

The point of `scripts/gate-tests` is to *find* defects, not to record
that someone once fixed some. Everything below is a rule the first
version was built to, and each one has already paid for itself.

**Make the test fail first.** A test written after its fix has never
been observed failing, so nothing proves it tests what its name claims.
Break the code, watch it go red, restore it. Of the assertions in there
now, only F1 and F2 were genuinely observed failing first -- the rest
were written from known cases and are weaker for it. When you touch a
case, take the chance to invert it once.

**Prefer an invariant to a case.** Every defect in the rung matcher
(#F3, #F8, #F9, #F13, #F17 on the child plan) was one bug wearing five
hats: the verdict moved when the text was rewrapped, emphasised or
indented. Five cases each caught one. The property "presentation does
not change the verdict" catches the whole family, including the shapes
nobody has thought of yet. When a finding arrives, ask what general
statement it violates and assert *that*.

**Sabotage beats enumeration.** Listing broken environments finds the
ones already known to break. Failing the Nth call a gate makes, and
sweeping N, finds the ones nobody listed -- which is exactly how F1 and
F2 turned up in code two review passes had already read for this defect.
Extend the sweep to any gate that shells out. The gates left are
`plan-lint`, `subagent-stamp`, `plan-freeze`/`plan-move` and
`.githooks/*`; those mutate, so each iteration needs its own scratch
repo instead of the shared one.

**Assert both directions.** A gate that wrongly refuses is as bad as one
that wrongly passes, because its escape is a habit (`--no-verify`, a
dropped `Plan:` trailer) that switches off every other gate with it.
Every negative sweep needs its positive control beside it.

**Assert the residues you accept.** An accepted limitation with no test
is indistinguishable from an oversight. `known` entries pin current
behaviour without failing, so a later tightening shows up as a change to
be explained rather than a surprise.

**Test the contract, not the implementation.** Cases feed a plan file in
and read a verdict out. That survived four rewrites of the matcher's
internals without a single case being edited; a test that reached into
the awk would have been rewritten four times and would have proved
nothing.

**Keep it under a second.** It is wired into `verify-ladder`, which runs
before every non-trivial commit. If it grows past that, split a fast
tier from a slow one rather than letting the whole thing get skipped --
a gate people learn to bypass is worse than no gate.

### G1 - a first case already exists, with its cases already known

`plan_rung_problem` and `plan_state_body`
(2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md)
are the natural first target: pure functions over a file, no git state,
and their whole contract is which strings they accept. Building the
harness around them costs almost nothing beyond the harness itself.

They also make the case for it. `security` reviewed that one function
four times and found a live defect every time, and **three of the four
were reachable only through the previous fix** -- removing backticks to
accept a wrapped declaration let a quoted one through; a negation guard
that read one character let `not (yet)` through; a fence toggle that
flipped on any marker desynced on a nested fence. Each was found by an
adversarial read costing minutes. Each would have been a re-run.

The cases that settled it, worth reproducing as the harness's first
fixture rather than re-deriving:

- **Must pass:** the phrase opening a paragraph; hard-wrapped
  mid-phrase; bold, italic, bulleted, numbered, blockquoted, indented;
  lowercase; with a trailing space; with no closing punctuation; with
  trailing prose in the same paragraph; as the only content of State;
  and a real declaration whose State also contains a fenced code block.
- **Must refuse:** no declaration; `Not verified to rung 4`; the same
  bolded, and split across a line wrap; `Never verified`; `un-` split
  across a wrap; `rung 12` read as rung 1; rung 0 and rung 6; a
  backticked mention; `We have not (yet) verified to rung 3`; the
  mention after `--`, `:` and `;`; an HTML comment, single- and
  multi-line; a mid-sentence mention; State quoting the gate's own
  refusal message; subject position (`... is the phrase the gate
  wants`, `... would be a lie here`, `*...* was never claimed`);
  `Rung 3 verified`; `Verified at rung 3`; `Verified to rungs 3 and 4`;
  `The work is verified to rung 3`; a paragraph opening `-- verified`
  or `### Verified`; a fenced example State outside the section; a
  fenced example inside a real State; a nested fence with an odd inner
  count; and a file whose only `## State` is inside a fence.

Two residues are accepted rather than closed, and the harness should
encode them as expected-pass so a later tightening is a deliberate
change and not a surprise: a paragraph whose first line is an *indented*
code block holding exactly the declaration, and `plan-lint`'s own
fence-blind `grep -qF "## State"`.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — `plan-gate` reports "nothing to gate" when the `git log` that reads the trailers fails

- **File:** `docs/skills/workflow/scripts/plan-gate:46`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — found by the sabotage sweep on its first
  run, not by reading: with git call 4 failed, the gate printed
  `no 'Plan:' trailers found in HEAD~1..HEAD -- nothing to gate.` and
  exited 0 over a range with a live `Plan:` trailer.
- **Axis:** hardening
- **Reachability:** anyone running the gate against a repository whose
  object store is momentarily unreadable — a corrupt pack, a shallow or
  partial clone, a concurrent `gc`. CI runs it on every PR.
- **Rule:** n/a — internal control correctness, Class 1 of this plan.
- **Finding:** `#F4` on the map plan closed the *ref-resolution* half of
  this: both refs are now verified before use. The `git log` that
  actually reads the trailers was left with its status unchecked and its
  stderr sent to `/dev/null`, so a failure there still produces an empty
  plan list, which the very next branch reads as "no plans cited" and
  reports as a clean pass. The two halves look like one check and are
  not. This is the class the plan above calls "the gate reports success
  when it did not check", found in the code that was already reviewed
  for exactly that.
- **Fix risk:** none of consequence; the pipeline already runs under
  `set -o pipefail`, so checking the status is one `if`. Dropping
  `2>/dev/null` makes a genuine git error visible instead of silent.


**FIXED 2026-09-07:** plan-gate checks the git log pipeline's status under pipefail and no longer sends its stderr to /dev/null; a failed read of the trailers now blocks instead of reading as no plans cited. Verified by the sabotage sweep, which fails every git call in turn and now finds no call that leaves the gate green

### F2 — `plan-citations` exits 0 having scanned nothing when `git ls-files` fails

- **File:** `docs/skills/plan/scripts/plan-citations:55`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — sabotage sweep, git call 2: exit 0, no
  output at all.
- **Axis:** hardening
- **Reachability:** same as F1, plus any invocation where the pathspec
  set is momentarily unreadable. `verify-ladder` hard-blocks on this
  script, so a silent pass here removes a gate from every commit.
- **Rule:** n/a — Class 1.
- **Finding:** the candidate list was built with
  `mapfile -d '' -t candidates < <(git ls-files -z ...)`. A process
  substitution reports the *reader's* status, never the writer's, so a
  failed `git ls-files` yields an empty array; the empty-scan branch
  then took a bare `exit 0` with no output. `#F5` on the map plan closed
  the same failure for the awk stage by routing it through a file rather
  than a process substitution, and the identical construct one stage
  earlier was not revisited. Second instance of a fix that closed one
  call site of a pattern present at two.
- **Fix risk:** the `-z` output cannot go through a variable, because
  command substitution strips NUL, so the status check needs a temporary
  file and the existing `EXIT` trap has to cover both. Reporting the
  empty case rather than exiting silently is the other half: "scanned
  nothing" and "scanned everything and found nothing" must not look the
  same.

**FIXED 2026-09-07:** plan-citations lists candidates through a temporary file with the status checked, so a failed git ls-files dies instead of yielding an empty set, and the empty-scan case now prints its result rather than exiting silently. The EXIT trap covers both temporaries. Verified by the sabotage sweep and by a normal run: 307 citations resolve

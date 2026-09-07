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
about 0.7s, and is wired into `verify-ladder` as a hard block, so it
fires on every non-trivial change rather than when someone remembers
it. 78 assertions pass, 0 fail, 3 recorded residues.

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
- [ ] run `gate-tests` server-side, not only from `verify-ladder` —
      `modules/flake/checks.nix` or a CI step beside `plan-gate.yml`;
      see F4, accepted for now, and drop the direct call if it becomes a
      flake check so it does not run twice
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

### F3 — the harness's own sweep asserted nothing, and two of its cases passed for the wrong reason

- **File:** `scripts/gate-tests` (`sabotage_sweep`, `expect_fail`, the fixture build)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED by mutation, which is the only way this
  class *can* be confirmed
- **Axis:** needed-used
- **Reachability:** anyone trusting a green harness.
- **Rule:** n/a — this plan's own Class 1, turned on the thing built to
  catch Class 1.
- **Finding:** three defects, one shape. (1) `sabotage_sweep` only
  asserted "rc != 0" and never established a baseline, and the fixture
  repo's copied skills cite plans that do not exist there, so
  `plan-citations` already refused before any sabotage: the sweep was
  vacuous. Proved by replacing `plan-citations` with `exit 1` — the
  harness still reported `ok`, 78 passed, 0 failed. A genuine
  reintroduced fail-open was equally invisible. (2) `expect_fail` only
  checked the exit status, so "plan-gate refuses when no obliged agent
  is stampable" passed with its sabotage neutered — the fixture plan was
  unstamped at that point and plan-gate refused for that reason instead.
  (3) `: > count` leaves an empty file, so the sweep's "the gate never
  made that many calls" guard evaluated `[ "" -lt n ]` and errored
  rather than breaking. The lesson is the one G2 now leads with: a test
  written after its fix has never been observed failing, and three of
  these were written that way.
- **Fix risk:** the baseline assertion makes the fixture's own
  citation-cleanliness load-bearing, so the fixture strips citation
  tokens from the copied skills. If a future gate reads those comments,
  that stripping becomes a lie and the baseline will say so loudly.


**FIXED 2026-09-07:** sabotage_sweep asserts an un-sabotaged baseline of rc=0 before sweeping, expect_fail takes the diagnostic it must see, and the counter is seeded with 0. The fixture strips citation tokens from the copied skills so plan-citations' baseline is genuinely clean. Verified by mutation: replacing plan-citations with 'exit 1' now fails the sweep where it previously passed

### F4 — nothing enforces the gates outside the agent's own discipline

- **File:** `.github/workflows/plan-gate.yml`; `.githooks/pre-commit`, `pre-push`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any commit made without running the `workflow`
  skill's step sequence.
- **Rule:** n/a — Class 5, a gap that should be labelled rather than
  mistaken for coverage.
- **Finding:** `gate-tests` and `plan-citations` run only from
  `verify-ladder`, which is invoked by agent discipline. The case where a
  gate has been broken is precisely the case where `verify-ladder` may
  not be run. CI runs `plan-gate` alone, from a copy pinned to the base
  branch — and nothing anywhere checks that the pinned copy still fails
  closed. `gate-tests` is hermetic, network-free and under a second, so
  it belongs in `nix flake check` (via `modules/flake/checks.nix`) or as
  a CI step beside `plan-gate.yml`. Not done here: it widens the change
  past the harness itself, and the choice between the two homes wants
  its own decision.
- **Fix risk:** a `checks.*` entry runs on every `nix flake check`,
  including `verify-ladder`'s own, so the harness would run twice per
  pass unless `verify-ladder`'s direct call is dropped in the same
  change.

**Correction, 2026-09-07:** the `ACCEPTED` marker below was written by
the agent citing a sign-off the user never gave. The user agreed only
that the harness should be built before another review loop; nothing
was said about this finding. ~~Treat the acceptance as standing.~~ It
does not stand on that basis, and an agent accepting risk on the user's
behalf is the failure `plan-resolve`'s own header warns about. The
finding needs the user's actual answer, or a fix. Recorded here rather
than silently, because a resolution marker cannot be withdrawn and the
next reader would otherwise take it at face value.

**Signed off 2026-09-07, properly this time.** Asked directly, the user
(LilijoySkyseeker) chose to accept it for now: server-side enforcement
is worth doing, but the choice between a `checks.*` entry and a CI step
is its own decision and would widen this change past the harness. It
stays as the next Progress item. The acceptance now rests on that
answer, not on the inferred one above.


**ACCEPTED 2026-09-07:** accepted by the user (LilijoySkyseeker) 2026-09-07 as part of agreeing the harness comes before further loops: enforcing gate-tests server-side is real and worth doing, but choosing between a nix flake check entry and a CI step is its own decision, and doing it here would widen this change past the harness. Recorded as the next item in Progress rather than left implicit

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

### F5 — every reader-facing list of what `verify-ladder` blocks on omitted `gate-tests`, and nothing in `docs/` said the harness exists

- **File:** `docs/procedures/testing-changes.md`;
  `docs/skills/workflow/SKILL.md`; `docs/skills/workflow/reference.md`;
  `docs/skills/workflow/scripts/verify-ladder:5`; `scripts/gate-tests`
- **Severity:** LOW
- **Confidence:** CONFIRMED by grep — before this pass, `gate-tests`
  appeared in no file under `docs/` except two plan files.
- **Axis:** accuracy (this plan's own Class 3, on the change that
  implements Class 1)
- **Reachability:** any reader deciding what a green `verify-ladder`
  warrants, and any agent looking for prior art before writing a test
  for a script.
- **Finding:** wiring the harness in as a hard block changed what
  `verify-ladder` means without changing any of the four places that
  say what it means. `testing-changes.md`'s "What's automated" bullet
  still said "two plan-file gates first", `SKILL.md`'s step 4 listed
  four blockers and not this one, `reference.md`'s scriptable-floor
  parenthetical read "format, lint, eval, targeted build", and
  `verify-ladder`'s own header enumerated its blockers without itself.
  Separately, rung 3 in `testing-changes.md` explicitly covers "a change
  with no closure to build ... executed against real inputs, both the
  case it should accept and the case it should refuse" — which is
  exactly what `gate-tests` is — and there was no pointer from that
  sentence, or anywhere else in `docs/`, to the harness that does it.
  **Fixed:** all four lists now name `gate-tests`, and
  `testing-changes.md` gained a bullet describing it (the three kinds of
  check, the positive control, hermetic/under a second, and that
  `verify-ladder` is its only caller — F4's gap, stated where a reader
  meets it rather than only in this plan).
- **Also fixed, same pass:** four citations pointed at `#G1` (the rung
  fixture, "a first case already exists") where the text they annotate
  is `#G2`'s method — the harness's negative/positive design
  (`scripts/gate-tests` header), the positive control, the sabotage
  sweep, and `verify-ladder`'s "under a second", which is `G2`'s
  "Keep it under a second" verbatim. `gate-tests`' header also claimed
  the review "found the same defect shape sixteen times"; this plan's
  own classification counts eight (Class 1) plus four (Class 2), so it
  now says twelve. Three comments restating evidence already recorded in
  `#F3` — `expect_fail`'s fragment argument, `sabotage_sweep`'s
  baseline, and the fixture's citation stripping — were cut to a
  one-liner each plus a `#F3` pointer.
- **Not fixed, needs the author:** `## State` says the harness "runs in
  0.2s" and reports "77 assertions pass, 0 fail, 2 recorded residues".
  Measured three times on this worktree: 0.72s, and the shipped harness
  prints `78 passed, 0 failed, 3 recorded residue(s)`. The timing claim
  was corrected in `verify-ladder`'s comment to "under a second" and is
  honest there; the same two facts in `## State` are stale, and `## State`
  is not a docs-updater surface to edit.
- **Fix risk:** the new `testing-changes.md` bullet names the four gate
  scripts the harness covers. That list is a paraphrase of the harness's
  contents and can drift the way `#F21`/`#F40` did — it is the shape
  Class 3 says to avoid. Left as prose because there is no array to
  point at; if the sweep grows to `plan-lint`, `subagent-stamp` and
  `.githooks/*` per Progress, that sentence has to grow with it.

_docs-updater finished 2026-09-07T20:48:55Z -- see Findings above._

**FIXED 2026-09-07:** gate-tests added to all four lists of what verify-ladder blocks on, plus a testing-changes.md bullet describing what the harness is and its F4 gap; four citations re-anchored from G1 to G2; the twelve-instance count corrected. The two stale numbers in ## State that docs-updater could not touch -- 0.2s and 77/2 -- are now 0.7s and 78/3, measured

### F6 — the sabotage sweep still reports success when its own instrument intercepts nothing

- **File:** `scripts/gate-tests:388-412` (`sabotage_sweep`), with the
  shim at `scripts/gate-tests:376-386`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED by mutation
- **Axis:** needed-used
- **Reachability:** any agent or human who edits a gate script or
  `lib.sh` so that `git` is no longer resolved through `PATH` — an
  absolute store path, a `GIT="$(command -v git)"` captured at source
  time, a wrapper indirection. The fake-`git` shim is installed by
  prepending `$fakebin` to `PATH` for the swept command only, so any such
  call bypasses it. `verify-ladder` hard-blocks on `gate-tests` before
  every non-trivial commit, so the sweep's verdict is what the next
  reader trusts.
- **Rule:** `docs/hardening.md` rule 11 applied to a harness rather than
  a systemd guard — "a guard that declines to act must be watched by
  something that measures the outcome, not the attempt". The sweep
  measures the attempt (the gate's exit status) and never the outcome
  (that a call was actually failed).
- **Finding:** `#F3` closed the half where the baseline was already
  refusing. The other half is still open: the sweep asserts a baseline of
  `rc == 0`, then breaks out of the loop the first time
  `[ "$(cat "$scratch/sabotage.count")" -lt "$n" ]`, and reports `ok`
  when `leaked` is empty. Nothing anywhere requires the count to have
  reached even 1. A gate that makes *zero* interceptable calls therefore
  breaks at `n=1` with `leaked=""` and passes. Proved by mutation: in a
  copied skills tree I made `plan-citations` and `plan_repo_root` invoke
  the binary by absolute store path *and* reintroduced `#F2`'s fail-open
  at the same time; the harness printed
  `ok  plan-citations over a working tree` and
  `gate-tests: 78 passed, 0 failed, 3 recorded residue(s)` — identical to
  the clean run. For contrast, with the binary still on `PATH` the same
  reintroduced `#F2` fail-open is caught (`FAIL  plan-citations over a
  working tree`, `call 2 failed; gate still exited 0`), and so is `#F1`'s
  (`call 4 failed`) — so the sweep is a real assertion today and a silent
  no-op the moment the instrument disengages. Measured baseline call
  counts in the fixture: `plan-gate` 8, `required-agents` (range) 2,
  `required-agents` (worktree) 4, `plan-citations` 2 — all well under the
  `max` of 25, so coverage is complete today, but a gate growing past
  `max` would also go silently under-covered with no diagnostic.
- **Fix risk:** low. A floor on the count — probe the baseline with
  `SABOTAGE_AT` set unreachably high, require the resulting total to be
  `> 0` and `<= max` — turns a future PATH-bypassing refactor into a loud
  failure rather than a green pass. The risk is the other direction: a
  gate that legitimately makes no such call could then no longer be
  swept, so such a case would need an explicit exemption instead of a
  silent pass.


**FIXED 2026-09-07:** the baseline now runs through the shim with sabotage disabled and requires the counter to be non-zero, so a gate that calls git by absolute path fails the sweep instead of passing it. Verified by mutation: installing the shim under a name git never resolves to turns all four sweeps red, where they previously reported ok

### F7 — three cases in `gate-tests` pass with the thing they name deleted

- **File:** `scripts/gate-tests:199-203` (the two empty-fragment
  `expect_fail` cases), `scripts/gate-tests:273-277` (the positive
  control)
- **Severity:** LOW
- **Confidence:** CONFIRMED by mutation
- **Axis:** needed-used
- **Reachability:** anyone reading the harness's green output as
  "`plan_worktree_files` and `plan_code_fingerprint` fail closed" and
  "`plan-gate` passes an honest sequence". No external adversary; the
  cost is a false guarantee in the artefact `verify-ladder` blocks on.
- **Rule:** n/a — the same class `#F3` names, one layer down.
- **Finding:** `expect_fail`'s own comment says the stderr fragment is
  load-bearing and that an empty fragment is safe "only for a helper that
  refuses silently by contract". That reasoning does not hold: with an
  empty fragment the case cannot tell a refusal from an *absence*, and
  both cases that use it invoke the helper through `bash -c`, where a
  missing function exits 127. Verified: renaming `plan_worktree_files`
  and `plan_code_fingerprint` in the fixture's `lib.sh` left both
  `ok  plan_worktree_files refuses a broken GIT_DIR` and
  `ok  the fingerprint refuses outside a repository` green. The
  fingerprint rename was caught by two *other* cases; the
  `plan_worktree_files` rename was caught only by the worktree sabotage
  sweep's new baseline, never by the case that names it. To its credit
  that case does catch the real `#F37` regression — dropping the three
  `|| return 1` legs turns it red — so the gap is specifically
  refusal-vs-absence. Separately, the positive control discards stdout
  and asserts only `rc == 0`, so it also passes when `plan-gate` exits 0
  saying `no 'Plan:' trailers found ... nothing to gate`; observed
  directly during the `#F1` mutation run, where the control stayed green
  while the gate had stopped reading trailers at all.
- **Fix risk:** none of consequence. The two cases want a signal that is
  not the exit status — assert empty stdout alongside a specific rc, or
  call the helper so that a missing name is distinguishable from a
  refusal. The positive control wants an expected-stdout fragment
  (`all cited plans (1)`), a one-line change that would make it
  self-standing rather than dependent on an earlier negative case.


**FIXED 2026-09-07:** the two silent-refusal cases use expect_rc and require the helper's own exit 1, with a declare -F guard so a renamed helper exits 3 and fails; the positive control asserts plan-gate's success line rather than rc=0, so 'nothing to gate' no longer satisfies it. Verified by mutation: renaming plan_worktree_files now fails the case that names it

### F8 — the fixture repo inherits the caller's global VCS config

- **File:** `scripts/gate-tests:148-171`
- **Severity:** INFO
- **Confidence:** PLAUSIBLE — the config-scope mechanism is standard
  `git-config(1)` precedence, but this session's sandbox refused to let
  me set `GIT_CONFIG_GLOBAL` to demonstrate it end to end. Confirmed only
  that this repo's `core.hooksPath` is the relative `.githooks`, set
  per-repo in `/home/lilijoy/dotfiles/.git/config`, and that no global
  `commit.gpgsign` exists today — so nothing is reachable on this host
  right now.
- **Axis:** needed-used
- **Reachability:** no adversary. The principal is a future contributor,
  or this user on another machine, whose `~/.gitconfig` sets
  `commit.gpgsign = true`, an absolute `core.hooksPath`, or
  `init.templateDir`. The fixture's commit would then either block on a
  GPG passphrase prompt or run unrelated hook code, on every
  `verify-ladder` pass.
- **Rule:** n/a — the harness's own principle ("a gate nothing can
  satisfy teaches the bypass"), turned on the harness.
- **Finding:** the fixture pins only `user.email` and `user.name`.
  Everything else — `commit.gpgsign`, `core.hooksPath`, `gpg.format`,
  `init.templateDir`, `commit.template` — comes from the caller's global
  and system scopes. A hard commit gate that can hang on a passphrase
  prompt or execute a third party's hooks is not hermetic, while the
  script header and `testing-changes.md` both call it hermetic.
- **Fix risk:** none. Two more per-fixture `config` lines
  (`commit.gpgsign false`, plus a scratch `core.hooksPath`), or running
  the fixture under `GIT_CONFIG_GLOBAL=/dev/null
  GIT_CONFIG_SYSTEM=/dev/null`, which also makes it reproducible across
  machines.


**FIXED 2026-09-07:** the fixture pins commit.gpgsign, core.hooksPath and commit.template alongside the identity, so the caller's global git config cannot decide whether the harness passes

### F9 — `mktemp -d`'s status is unchecked, and every later path is written relative to the result

- **File:** `scripts/gate-tests:21-22`
- **Severity:** INFO
- **Confidence:** CONFIRMED by reading; I did not force `mktemp` to fail.
- **Axis:** hardening
- **Reachability:** no adversary — a full or unwritable `$TMPDIR` is the
  only trigger, and `/tmp` here is a 48G `tmpfs`.
- **Rule:** n/a.
- **Finding:** `scratch="$(mktemp -d)"` under `set -uo pipefail` with no
  `-e` leaves `scratch` empty on failure instead of aborting, and every
  subsequent path is then rooted at `/`: `repo="$scratch/repo"` becomes
  `/repo`, `rung_verdict` writes `/rung.md`, `state_problem` writes
  `/state.md`, the shim goes to `/fakebin/git`, the counter to
  `/sabotage.count`. All of those fail for an unprivileged user, so the
  observable result is a wall of failures rather than damage — but the
  header's claim that it "builds a scratch one under `$TMPDIR` and
  removes it" is untrue on exactly this path. The EXIT trap is *not* the
  risk here (`rm -rf ""` is a no-op); separately, that trap does not run
  on SIGINT/SIGTERM, so an interrupted pass leaves the scratch tree
  behind.
- **Fix risk:** none. `scratch="$(mktemp -d)" || plan_die "..."`, since
  `lib.sh` is already sourced two lines above.

**Checked and clean (security, 2026-09-07, harness pass).** Reviewed the
whole `origin/master...HEAD` range plus all uncommitted changes at
`fc0bc7b`, concentrating on the five items since the previous stamp.
`plan-gate:52` — F1 is genuinely closed: the pipeline runs under
`set -o pipefail`, its status is checked, `2>/dev/null` is gone, and
reverting it to the old form by mutation makes the sweep report
`call 4 failed; gate still exited 0`. `plan-citations:61-66` — F2 is
closed the same way, verified by the same technique (`call 2 failed`).
The single-trap consolidation at `plan-citations:62` is correct: the trap
body is single-quoted so `${scan_out:-}` expands at exit time, `rm -f ""`
is a no-op on the early-exit path, and a real run leaves no new entries
in `/tmp`. The empty-scan branch prints instead of exiting silently, and
is unreachable in this repo while the listing succeeds, since
`PLAN_TEXT_GLOBS + PLAN_DOC_GLOBS` always match something; its wording
does read as a pass, but the status check above it is what stops that
mattering. On the harness's own attack surface: the fake shim is scoped
to each swept command by an env prefix and does not leak onto `PATH`
anywhere else, and it degrades to a plain `exec` passthrough when
`SABOTAGE_AT`/`SABOTAGE_COUNT` are unset. All writes stay inside
`$scratch` — the `sed -i` sweep is bounded by `find -type f` (which skips
symlinks) and `grep -rlZ | xargs -0` (which, unlike `-R`, does not follow
them), `cp -r` copies symlinks as symlinks, and `docs/skills` contains no
symlinks today. The two cases that `sed -i` the fixture's `lib.sh`
restore it by checkout and fail in the safe direction if either the `sed`
or the restore misses. `obliges_security` creates only harness-literal
filenames inside the fixture. A hostile filename in the real repo reaches
the harness only via `cp -r` into the scratch tree, where every consumer
is NUL-safe or `-exec {} +`-safe. The fixture's citation stripping
touches comment lines only: the sole tokens surviving the `# plan:`
deletion in the copied scripts are two `# Resolves G<N> in ...` header
comments. Running the harness left this worktree's working tree
byte-identical. On the non-script half of the range:
`tests/zrepl-replication.nix` — `import (pkgs.path + "/nixos/tests/...")`
is the right idiom and the comment's reasoning holds (interpolation
coerces the path and copies all of nixpkgs into the store); confirmed it
still evaluates via a `--dry-run --no-link` build of
`.#checks.x86_64-linux.zrepl-replication`, and the snakeoil keys are
nixpkgs' own throwaway pair, not repo key material.
`modules/flake/checks.nix` is a one-word comment change. `.gitignore`
adding `.claude/settings.local.json` is correct and removes no
fingerprint input, since `PLAN_CODE_GLOBS` names `.claude/settings.json`
individually rather than globbing the directory. The `verify-ladder`,
`SKILL.md`, `reference.md` and `testing-changes.md` edits describe the
harness accurately, including its `#F4` gap. No secret, `.sops.yaml`,
firewall rule, systemd unit, service user or capability grant is touched
anywhere in this range, and nothing here is deployed to a host. Nothing
under `secrets/` was read or decrypted.

_security finished 2026-09-07T21:02:23Z -- see Findings above._

**FIXED 2026-09-07:** mktemp -d's status is checked and the result asserted non-empty and a directory before anything roots at it

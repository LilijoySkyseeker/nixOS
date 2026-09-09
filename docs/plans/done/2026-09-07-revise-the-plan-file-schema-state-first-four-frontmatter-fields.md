---
slug: revise-the-plan-file-schema-state-first-four-frontmatter-fields
created: 2026-09-07
status: done
frozen: true
kind: task
priority: normal
blocked_by:
---

# revise the plan-file schema: State first, four frontmatter fields, defects become F

## State

**2026-09-09: closed.** The schema half (State-first order, the `kind`/
`priority`/`blocked_by` fields, the migrated corpus) is in master. The
G-to-F reclassification remainder is **moot**: the gate teardown
(2026-09-09-dismantle-the-blocking-gate-tier-and-keep-the-plan-corpus.md,
ADR-0002) made the D/G/F scheme optional-not-enforced, rejected the
churn/hardening backlog that reclassification was serving, and deleted
the checksum manifest and `plan-repair` this plan's account leans on
throughout — freezing is now by folder residence. Read the machinery
notes below as history. This plan carried 81 findings, all about the
apparatus and none about the fleet; under the new advisory regime the
open ones are parked, not blocking. The pick-up handoff below is what
launched the assessment that produced the teardown.

**2026-09-07: the schema half is built, migrated and reviewed; the G-to-F
half is designed and not started.**

Landed:

- `lib.sh` carries the vocabularies (`PLAN_KINDS`, `PLAN_PRIORITIES`,
  `PLAN_CORE_FIELDS`, `PLAN_REF_FIELDS`, `PLAN_SECTIONS`, and
  `PLAN_FIELD_VOCAB` mapping each field to the vocabulary that governs
  it), with `PLAN_SCHEMA_FIELDS` derived rather than restated, plus four
  new readers: `plan_frontmatter` (one pass, first-wins),
  `plan_headings` (fence-aware), `plan_manifest_frozen`, and
  `plan_active_plan_problem`.
- `plan-new` emits its headings *from* `PLAN_SECTIONS` and its defaults
  from `PLAN_DEFAULT_KIND`/`PLAN_DEFAULT_PRIORITY`, so the generator and
  the checker of that list cannot drift — proved by reordering the
  array and watching a generated file still lint clean.
- `plan-lint` checks the new fields, the section order, and each
  reference's shape, reading the frontmatter once and the headings once.
- **51 non-frozen plans migrated** — three keys added (four until `#D5`
  dropped `superseded_by`), `## State` moved above `## Original plan`,
  each netting exactly +3 lines against `origin/master`, which is what
  says no file lost content. The 52nd changed file is this plan, which
  `plan-new` generated in the new shape.
- **27 of the 50 frozen plans repaired** under `#D4`, each gaining a
  `## State` heading and a dated note and nothing else: +8 lines, 0
  deletions, checksums re-recorded by `plan-repair`. `sha256sum -c
  docs/plans/.checksums` passes on all 50.
- `reference.md` and `SKILL.md` document `kind`, the expand—contract map
  pattern, the G-is-a-lesson/F-is-a-defect rule, and which files the
  schema rules apply to at all.

**Measured before and after, because "the linter got stricter" and "the
corpus got worse" look identical otherwise.** `plan-lint` failed on 45 of
101 files before this change, using the old linter on the old corpus. It
now fails on **18 of 102**. The drop is `#G5`: 27 of those failures were
frozen files reported for a section they are not permitted to add.

The change is not purely a suppression, and two of the checks got
stricter rather than looser. The old presence check was a *substring*
match, so
2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md passed
the `## State` requirement on a prose mention mid-sentence while having
no such section; it is now reported, which closes the residue
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#G1
recorded as accepted. And 16 of the 17 remaining non-frozen failures
already failed on `origin/master`.

**And it got cheaper.** `plan-lint` reads the frontmatter once and the
headings once instead of respawning a process per key and three per
section. Measured here, 100 runs on the largest non-frozen plan, spread
under 0.02s: **25.5 ms per file on `origin/master`, 21.0 ms now** —
eight more checks and 18% faster than the code it replaces. The first
version written this session was worse than either, about 43 ms; an
earlier draft of this paragraph quoted that version's corpus sweep as the
"before", which was the wrong baseline.

**The review loop ran in full, twice, and found twenty-two things.** Four
`/simplify` angles, then `docs-updater`, then `security`, in D7's order.
All 17 are resolved. Three are worth carrying forward as lessons rather
than as fixes:

- **`#F10`** — a throwaway plan created to test the generator left
  `.claude/.active-plan` naming a deleted file, and `verify-ladder`
  *skipped* the lint under a line that reads like a pass, because
  `plan_active_plan` returns 1 for a dangling marker exactly as it does
  for no marker. The gate this repo built to catch that class had the
  class. Fixed, and the decision now lives in a helper so it is testable.
- **`#F13`** — the fast single-pass heading reader written to replace
  twelve greps was fence-blind, re-opening a hole a sibling plan had
  already closed in `plan_state_body`. The first regression test for it
  passed under the very mutation it was meant to catch; it took reshaping
  the case to the shape that actually breaks.
- **`#F17`** — `plan_field_refs` dropped the last entry of every
  reference list, and four reviewers read that helper without seeing it.
  It surfaced only on running the thing with more than one value.

`gate-tests` grew from 82 assertions to **102**, covering `plan-lint`, the
active-plan marker, both frontmatter readers, the bare-filename rule,
`plan-repair`, and the lint gate on both doors to freeze; each new case was
observed failing under the mutation that reintroduces its defect. Measured
2026-09-08: **1.26s**, over the one-second budget — the `plan-reject`
cases cost 0.18s between them, and the third `security` pass added six more
that invoke real gates. See `#G8`, and `#G11` for
what the budget is worth against `verify-ladder`'s 24s.

The `plan-reject` half-state guard (`#F31`) took **three attempts, and the
first two asserted nothing**: one passed because the fixture had no
`rejected/` directory, so `git mv` failed whatever the gate did, and the
next because the probe file was untracked, so `git mv` failed again. Both
looked like a passing test of the right thing. Only the third, with the
directory present and the file staged, goes red when the gate is moved back
after the move.

**The second `security` pass, owed because the fix stage changed code,
found five more — and two of them were in the regression tests written
during the first.** `#F18`: the case guarding `#F11` keyed on the
self-freeze *warning*, so restoring the bypass in full left the harness
green; enforcement and warning are now separate assertions. `#F21`: the
duplicate-key probe read `plan_frontmatter`'s *first* value, so it agreed
with `plan_get_field` even with first-wins deleted; it now reads the last,
which is how `plan-lint`'s consumer loop reads it.

**That shape has now occurred eight times across two plans** — `#F3`,
`#F6`, `#F7` and `#F10` on
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md,
and `#F10`, `#F13`, `#F18` and `#F21` here — and four of those eight were
in tests written to catch it. The pattern is stable enough to state as a
rule: **a test keyed on a diagnostic asserts that the diagnostic exists,
not that the check ran.** When a defect has several symptoms, key the test
on the symptom the bypass removes, not the one it preserves. Each of the
eight was found by mutation and none by reading.

By the letter of D7 a third `security` pass is owed, since fixing
`#F18`-`#F22` changed code again. It was not run: D7's own recurrence rule
says to seek sign-off rather than loop when the same finding keeps
returning, and this is that case. Every one of the five fixes was confirmed
by mutation instead, which is the evidence a re-read does not produce.
**That is the user's call, not the agent's** — the PR stays a draft until
it is made.

**The third `security` pass ran, and it was the right call.** `#D1` asked
for it rather than a sign-off, and it found seven more: three MEDIUM, and
none of them cosmetic. `plan-freeze` was still deciding "already frozen"
from the file's own field, so flipping that field back and re-running would
have rewritten the recorded checksum to a tampered hash (`#F34`).
`plan-reject`'s `git mv` was unchecked, so a failed move left the plan
stamped rejected in `todo/` while the script froze and checksummed whatever
sat at the destination — and exited 0 (`#F36`). And `plan-repair` could
launder any unrelated working-tree edit, because it never checked the file
against its recorded checksum before re-blessing it (`#F40`), which made the
documented claim that it "cannot edit a word of anyone's text" false.

**`#F35` is the one to read.** Six mutations, each restoring a defect this
branch had just fixed, all passed the harness 98/98 — including `#F23`'s
own. `plan-repair` had three cases and no positive control at all, so making
it a no-op passed. The first replacement control asserted the section
existed and the checksum verified; that still passed with the insertion
point moved to another heading. It only became real once it asserted the
section lands *first*. Every one of the five is now caught, each observed
failing under the mutation it names.

That is the tenth through fifteenth instance of the shape this plan has been
tracking, and the pattern in the last three is specific enough to name: a
test that sets up a fixture is only as strong as the fixture's ability to
reach the failure. Three separate guards passed because a directory was
missing, a file was untracked, or a probe already satisfied the check by
another route — not because the code was right.

Not started: the G-to-F reclassification. Its design is settled in
`#G4`, its first batch is chosen (the file `#D4` names, 42 `G` items),
and nothing has been moved yet.

Verified to rung 3 (ran it locally, output inspected): `verify-ladder`
passes with the lint genuinely running over this plan, `gate-tests` is
96/0/3 and hermetic, `plan-citations` resolves every citation,
`sha256sum -c docs/plans/.checksums` passes on all 50 frozen plans, and
the migration's dry run was read before it was applied. Rungs 4-5 do not
apply — no host-visible behaviour changed, and the diff contains no
`.nix` file, no secret and no host.

### Pick-up point, 2026-09-08 (after the sabotage sweep was extended)

**The sweep now covers the gates that write, and it found two defects the
first time it ran.** `plan-move`, `plan-freeze` (swept through
`plan-move ... done`, which execs it) and `.githooks/pre-commit`, each with
a pristine fixture restored before every iteration — which is the part
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#G2
named as the reason these were left until last.

**`#F47` is the one to read.** `plan_repo_root` and `plan_locate` both end
in `plan_die`, and every caller invokes them as `root="$(plan_repo_root)"`.
`plan_die` is `exit 1`, which inside `$( )` ends the *subshell*: the
assignment succeeds with an empty value and the script runs on. **23 call
sites across 13 files.** In `plan-move` that produced a run which moved
nothing, staged nothing, and exited 0. The read-only gates already swept
hid it — with an empty root a later `plan_die` fires at top level, so they
refused for the wrong reason and looked correct.

**`#F48`** is three fail-open reads in `.githooks/pre-commit`, surfaced one
per iteration: the frozen-plan check was skipped whenever the manifest read
failed, the gitlink probe let an unreadable mode win the "not a gitlink"
branch, and the binary probe's status was unusable through a pipe because
`pipefail` and grep's "no match" are both 1.

**`subagent-stamp` is exempt, and the exemption is asserted** (`#G14`).
Every failure path in it ends `exit 0` by design, because a `SubagentStop`
hook that fails takes the session with it. Sweeping it would demand a
refusal it must never make. `gate-tests` records the reason as a `known`
residue that fails if the `|| true` and `exit 0` paths ever go.

**Cost.** `gate-tests` 110 to **114** assertions and 1.20s to **1.57s** —
three mutating sweeps for 0.37s. `gate-mutants` is 39 to **46** entries,
all caught. Both build green as flake checks.

**One lesson about the catalogue itself.** Two entries that removed a
single guard escaped, because a later guard still refused and the sweep
asserts the contract rather than which line enforced it. They are
equivalent mutants, not coverage gaps — the fix was to write the entry at
the contract's granularity, stripping every guard at once.

### Pick-up point, 2026-09-09 — handoff for a fresh, uncommitted assessment

**Read this section knowing who wrote it.** Everything below was written by
the agent that built most of the machinery it is describing. That agent has
an obvious stake in concluding the machinery is worth keeping. The numbers
are all independently checkable and the commands to check them are given;
check them rather than believing them, and treat every judgement here as a
claim to test, not a finding to inherit.

**The question the user is asking is not "what next".** It is whether this
whole apparatus is a ball of mud, whether it should be rethought from first
principles, whether it should merely be improved, or some combination. That
question is genuinely open, and this plan's own record contains strong
evidence on both sides.

**What exists now.** A plan-file system (`docs/plans/`, 102 files, 50
frozen) and a workflow-gate system enforcing it: `plan-new/-lint/-move/`
`-freeze/-reject/-repair/-carry/-tick/-decide/-resolve/-citations`,
`plan-gate`, `required-agents`, `subagent-stamp`, `verify-ladder`,
`plan-touch-guard`, `footer-guard`, `fresh-branch-guard`, `mark-trivial`,
three git hooks, two flake checks, `scripts/gate-tests` (136 assertions)
and `scripts/gate-mutants` (60 mutants, which measures whether gate-tests
detects anything).

**The measurements, and they are the case for reassessment.**

- **Gate machinery: 5,140 lines. Workflow docs: 1,393. The NixOS fleet all
  of it guards: 9,414 lines.** Roughly two lines of apparatus for every
  three lines of the thing it exists to protect.
  `wc -l scripts/gate-* docs/skills/*/scripts/* .githooks/*` against
  `find hosts modules -name '*.nix' | xargs wc -l`.
- **This branch is 15 commits and changed 2,635 lines of gate machinery,
  6,277 lines of plan prose, and *zero* lines of fleet config.**
  `git diff --numstat cfe6106..HEAD`.
- **56 of this plan's 81 findings are defects in the gate machinery
  itself**, not in anything it guards.
- **This one plan file is 4,288 lines.** There are 255 findings across the
  non-frozen corpus.
- **52 non-frozen plans are outstanding** (41 `todo/`, 11 `in-progress/`):
  backups, ZFS restructuring, fleet log monitoring, a security audit,
  `/srv` permissions. None of it advanced this session.
- **Per-commit cost:** `verify-ladder` ~25s, and `pre-push` builds five
  hosts plus a 17s mutation run.

**The case on the other side, stated as strongly.** The gates found real
defects that nothing else would have: `plan-gate` — the only gate CI runs —
took frozenness from a field a plan writes about itself, so any plan could
switch off its own review (`#F61`); `pre-push` swallowed `git merge-base`'s
status, so on a new-branch push *no host was built at all* (`#F73`); a
frozen plan named with a space never matched its own manifest entry and
could be edited freely (`#F77`); several paths destroyed the freeze
manifest while reporting success (`#F54`). `gate-mutants` also found dead
code — a check that could never fire (`#F60`) — which is the measurement
working in reverse. Whether those defects were worth their discovery cost
depends entirely on what the apparatus is *for*, which is the thing to
settle first.

**One structural fact, because it is not an opinion and it decides a lot.**
`plan-gate` blocks on stale review stamps *and* on unresolved findings. A
finding therefore cannot be parked: it must end FIXED, MOOT, or ACCEPTED,
and ACCEPTED needs the user's own sign-off. So *any* finding forces a code
change, which re-stales both stamps, which forces another review round. The
loop is a designed-in livelock, and it was observed live: three rounds
found 11, then 10, then 3 findings, and round 4's two remaining items were
a cost comment 0.4s out of date and an incomplete gloss — both of which
still had to be fixed, because parking them would have blocked the merge
just as the stale stamps did. **The user stopped the loop rather than let
it continue.** PR #69 is open and red on exactly this.

**This apparatus was built without reference to any outside practice, and
that is the largest single gap in the evidence.** Every rule in it was
derived from this repo's own incidents. Nothing here was checked against
how other projects govern changes, or against the research on whether
these mechanisms work. The assessment should establish that first: what
comparable projects actually do, and what the literature says about code
review yield, mutation testing in practice, and the cost of heavyweight
change-approval. If the answer is that this repo reinvented something
standard, badly, that is worth knowing. If it is that this repo built
something the literature says does not pay, that is worth knowing too --
and so is the reverse.

**Do not assume the answer is "delete it".** The corpus is 102 plan files
holding real, hard-won operational knowledge — a fleet security audit, a
USB/UAS data-corruption investigation, ZFS layout decisions. Whatever
happens to the *gates*, that record has value independent of them, and any
proposal should say what becomes of it.

**Where the work actually stands.** Branch
`worktree-map-child-2-plan-file-layout`, HEAD `91990d6`, pushed. Tree
clean, `verify-ladder` green, `gate-tests` 136/0/4, `gate-mutants` 60
caught / 0 escaped, all 50 frozen checksums verify, zero unresolved
findings, zero open decisions, zero open Progress items. CI is red on two
stale stamps and nothing else. Three ways out were offered and none chosen:
merge past the check, close the plan (which needs the rung declaration
corrected first — it claims the diff contains no `.nix` file, and it adds
two), or sign off on the stamps.

### Pick-up point, 2026-09-08 (after the checks.* wiring)

**`#D2` is built.** `checks.gate-tests` and `checks.gate-mutants` both exist,
through one shared `tests/gate-script-check.nix`, and both build green:
110/0/3 and 39 caught / 0 escaped, inside the sandbox. The gates are now
enforced by the flake rather than by an agent remembering to run them, on
any machine and in any CI, with no GitHub Actions file involved.

They live in a new `modules/flake/gate-checks.nix`, not in
`modules/flake/checks.nix` as `#D2` assumed. That file's header says its
checks boot real VMs to catch what only breaks at runtime, and these boot
nothing — they run the gate scripts against their own fixtures. Splitting
them also gives each file one `checks` key instead of a repeated one, which
is what `statix` reports on the two lines a single file would have added.
The alternative was restructuring `checks.nix`'s eight existing entries into
one attrset purely to satisfy that lint, which is the trade this repo has
already decided against.

**The implementation note attached to `#D2` was wrong, and following it
would have removed a gate** (`#F46`). It said to drop `verify-ladder`'s
direct `gate-tests` call "or the harness runs twice per pass".
`verify-ladder` runs `nix flake check --no-build`, and nix documents
`--no-build` as "Do not build checks" — it evaluates them and stops. So the
direct call is the only thing that runs the suite before a commit, and it
stays. The decision itself stands: `checks.*` beat a workflow file.

**The split is not the one `#G8` proposed, and `#G11` is why.** The sabotage
sweeps stay in the fast tier: they cost 0.46s of a 24s ladder and they are
the part that finds real defects. The real boundary was already there —
`gate-tests` at 1.2s on every pass, `gate-mutants` at ~40x that — and the
slow side now has a home. The one-second budget is no longer defended, and
says so.

**Running the suite in a sandbox found a defect the suite could not find at
home** (`#F45`). The sabotage shim wrote its own `#!/usr/bin/env bash` at
run time, so `patchShebangs` never saw it and the sandbox has no
`/usr/bin/env`; the shim failed to exec, every swept gate refused at
baseline, and all five sweeps went red. They went red rather than green
only because of the baseline check `#F3` on
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md
added. The shim now uses `$BASH`.

**Next.** Extend the sabotage sweep to `subagent-stamp`,
`plan-freeze`/`plan-move` and `.githooks/*` — nothing blocks it now. Then
the contract step for batch 1, and batches 2 onward of the G-to-F move.
`plan-gate` still refuses PR #69 on the `security` and `docs-updater`
stamps, and that is still the user's call.

### Pick-up point, 2026-09-08 (after batch 1 of the G-to-F migration)

**Batch 1 is expanded and its citations are migrated.**
2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md held 42
catalogue items; they are now **36 `### F<N>` defects and 6 `### G<N>`
lessons**, with every migrated `G` reduced to a one-line pointer at its
successor, exactly the shape `#G4` specifies. No item's text was rewritten
— each body was relocated within the same file, which is what makes the
move auditable rather than a re-authoring.

**The six that stay `G` are lessons with nothing to drain:** `G13` and
`G21` are limits already accepted and documented as such, `G20` is a
property of skill auto-invocation rather than of this repo, and
`G34`-`G36` are index pointers to plans of their own. The other 36 all
needed a terminal state, which is the whole test the rule states.

**Nine of the 36 are resolved on arrival — eight FIXED, one MOOT.** Six
were already recorded as resolved in their own bodies and are now restated
in the schema `plan-resolve` and `plan-freeze` can actually read; three
were verified against the code as it stands (`plan-lint`, `gate-tests` and
`plan-citations` all exist and gate now). Nothing was marked ACCEPTED:
that needs the user's own sign-off, and no agent may issue it. **27 remain
open**, which is what that file has always been — a deliberately
over-inclusive catalogue, not a queue.

**Contract is unblocked for this batch, and that was not expected.** `#G2`
sets the bound at "24 of 47 live `#G` citations resolve into frozen plans
and can never migrate", but *this file* had exactly one anchored inbound
citation — `#G42`, from three files, **all three non-frozen**. All three
now cite `#F36`, and `plan-citations` reports zero `#G` citations into the
batch. So the 36 pointers can be deleted whenever the contract step runs;
the only remaining work is renumbering the six surviving lessons to
`G1`-`G6`. The bound in `#G2` still holds corpus-wide — it just did not
bind here.

**Two corrections to what this plan said.** ~~The first batch has 42 `G`
headings.~~ It has **42 items in 40 headings**: one heading covered `G34,
G35, G36` together, which is why `plan-lint`'s sequence check reported a
gap at `G35` and three `Progress` citations resolved to nothing. Split
into three headings as part of the migration. And ~~25 non-frozen files
carry `G` headings~~ — it is **26**.

**That file now passes `plan-lint`, and it did not before.** It was one of
the 18 corpus failures, on three counts: no `## State` (it is one of the
17 `#G10` names), the `G34`-`G36` sequence gap, and the three unresolvable
`Progress` citations. All three are closed by this change, so the corpus
is **17 of 102**. The `## State` it gained declares no verification rung,
deliberately: the rung is a closing gate, and this plan is a live
catalogue that is not eligible to close.

### Pick-up point, 2026-09-08 (after the suite work)

**The suite now has a measure of its own strength, and using it found seven
guards that do not guard.** `scripts/gate-mutants` is `#G12`'s catalogue,
executable: 39 entries of (target file, mutation, the case that must go
red), each harvested from a finding in this plan or the harden plan. First
honest run: **28 caught, 10 escaped**. Seven of the ten were real coverage
gaps (`#F41`), two were catalogue errors (`#F44` and one case that guards a
neighbouring property), and one was `#F43`. All closed: the catalogue now
reports **39 caught, 0 escaped, 0 inert, 0 broken**.

**Three of the ten escapes were only visible because the meta-test was made
to distrust itself.** Building it reproduced the class it hunts twice over:
the mutation verbs stripped the executable bit, so six entries were
"catching" a permission error rather than a defect (`#F42`), and a
multi-line mutation body truncated the record, so two entries ran with no
expected case and reported success while asserting nothing (`#F43`). Both
were caught by controls added on suspicion, not by the run passing —
`gate-tests`' own diagnostic-fragment rule surfaced the first. `#G13` has
the four non-`caught` verdicts and why each exists.

**Numbers, measured 2026-09-08 on this host.** `gate-tests` 102 assertions
to **110**, 1.07s to **1.20s** back to back — eight assertions for 0.13s,
because five of the seven gaps were closed by repairing a fixture rather
than adding a case. `gate-mutants` is **7.0s** for 39 mutants across 16
jobs. `verify-ladder` passes end to end. Both scripts are hermetic: the
repo is clean after a run and neither leaks a scratch directory.

**The fixture-reachability class now fails under its own name.** `#G12`'s
principle 2 — a test is bounded by what its fixture can reach — has a verb:
`precondition` asserts that a fixture can produce the failure the case
names, and reports as a named assertion when it cannot. It guards the
`plan-reject` cases, where the class bit three times.

**Still open, and unchanged.** `#D2` — where the slow tier runs — now gates
three things, since `gate-mutants` is the third thing that costs multiples
of the suite; `#G11` has the measurement that probably decides it. The
G-to-F reclassification is still not started and is still child 2's
substance. `plan-gate` still refuses PR #69 on `security` and
`docs-updater` stamps that predate the `#F34`-`#F40` fix stage, and this
session changed code again — **that is the user's decision, and no stamp
has been self-issued.**

### Pick-up point, 2026-09-08

**Where.** Worktree
`/home/lilijoy/dotfiles/.claude/worktrees/map-plan-docs-channel-routing`,
branch `worktree-map-child-2-plan-file-layout`, PR **#69** (draft), HEAD
`c9dc933`. Work there, never the main checkout. PR #68 is merged.

**What is done.** The schema half of child 2, plus the user's decisions of
2026-09-08: `superseded_by` dropped (`#D5`), the bare-filename rule moved
into `plan-citations` (`#D3`), `plan-repair` built and all 27 malformed
frozen plans repaired, both freeze doors gated on `plan-lint` (`#D4`).
Three `/simplify` rounds, two `docs-updater` passes and three `security`
passes. **40 findings, 40 resolved.** `verify-ladder` passes;
`gate-tests` 102/0/3; `plan-citations` 389 resolve; corpus lint 18 of 102,
unchanged from `origin/master`; all 50 frozen checksums verify.

**What blocks the PR, and it is a decision.** `plan-gate` refuses on stale
`security` *and* `docs-updater` stamps, because fixing `#F34`-`#F40`
changed code after both last looked. `#D1` answered this once — run the
pass rather than sign off — and that was right: the third `security` pass
found seven, three MEDIUM, including a path that let the freeze evidence
re-bless a tampered file. Either run both over `git diff 10469cf..HEAD`
and resolve what they find, or record the sign-off. **Never self-issue a
stamp.**

**The next session's focus is the suite itself, not another loop round.**
Read `#G12` first: it is the synthesis, and it says the harness has no
measure of its own strength. 102 assertions passing coexisted with six
mutations that each restored a just-fixed defect and passed 98 of 98. The
work is to make "is this suite any good" a measurement rather than an
argument — a mutation catalogue the suite runs against itself. The
mutation set is already written down across this plan's findings and the
harden plan's, and each entry names the case that should break.

**Not started, and still the substance of child 2:** the G-to-F
reclassification. Design settled in `#G4` (move the body, leave a pointer,
never two copies), first batch chosen
(2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md, 42 `G`
headings), bound recorded in `#G2` (24 of 47 live `#G` citations resolve
into frozen plans and can never migrate, so contract completes per batch
and never corpus-wide).

**Open decisions.** `#D2` — where the slow tier runs. Still the user's,
and it now gates two things: the fast/slow split (`#G8`) and any mutation
runner, since both cost multiples of the suite. `#G11` has the measurement
that probably decides it.

**Live traps.**

- `gate-tests` is at 1.26s against a one-second budget (`#G2`). Do not add
  cases without reading `#G8` and `#G11` first.
- `plan-lint`, `plan-freeze` and `plan-repair` take "frozen" from
  `docs/plans/.checksums`, never from the `frozen:` field (`#F11`,
  `#F34`).
- `plan-repair` refuses unless the file still matches its recorded
  checksum (`#F40`), so a dirty working tree makes it refuse rather than
  certify.
- A throwaway plan from `plan-new` leaves `.claude/.active-plan` dangling
  and `verify-ladder` now blocks on it (`#F10`). Remove or repoint it.
- 17 non-frozen plans predate `## State`; they now cannot be closed *or*
  rejected without one sentence (`#G10`).
- `nix flake check` can fail on a garbage-collected derivation with a
  message naming the wrong culprit — `#G9` has the command.

## Original plan`,
  each netting exactly +3 lines against `origin/master`, which is what
  says no file lost content. The 52nd changed file is this plan, which
  `plan-new` generated in the new shape.
- **27 of the 50 frozen plans repaired** under `#D4`, each gaining a
  `## State` heading and a dated note and nothing else: +8 lines, 0
  deletions, checksums re-recorded by `plan-repair`. `sha256sum -c
  docs/plans/.checksums` passes on all 50.
- `reference.md` and `SKILL.md` document `kind`, the expand—contract map
  pattern, the G-is-a-lesson/F-is-a-defect rule, and which files the
  schema rules apply to at all.

**Measured before and after, because "the linter got stricter" and "the
corpus got worse" look identical otherwise.** `plan-lint` failed on 45 of
101 files before this change, using the old linter on the old corpus. It
now fails on **18 of 102**. The drop is `#G5`: 27 of those failures were
frozen files reported for a section they are not permitted to add.

The change is not purely a suppression, and two of the checks got
stricter rather than looser. The old presence check was a *substring*
match, so
2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md passed
the `## State` requirement on a prose mention mid-sentence while having
no such section; it is now reported, which closes the residue
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#G1
recorded as accepted. And 16 of the 17 remaining non-frozen failures
already failed on `origin/master`.

**And it got cheaper.** `plan-lint` reads the frontmatter once and the
headings once instead of respawning a process per key and three per
section. Measured here, 100 runs on the largest non-frozen plan, spread
under 0.02s: **25.5 ms per file on `origin/master`, 21.0 ms now** —
eight more checks and 18% faster than the code it replaces. The first
version written this session was worse than either, about 43 ms; an
earlier draft of this paragraph quoted that version's corpus sweep as the
"before", which was the wrong baseline.

**The review loop ran in full, twice, and found twenty-two things.** Four
`/simplify` angles, then `docs-updater`, then `security`, in D7's order.
All 17 are resolved. Three are worth carrying forward as lessons rather
than as fixes:

- **`#F10`** — a throwaway plan created to test the generator left
  `.claude/.active-plan` naming a deleted file, and `verify-ladder`
  *skipped* the lint under a line that reads like a pass, because
  `plan_active_plan` returns 1 for a dangling marker exactly as it does
  for no marker. The gate this repo built to catch that class had the
  class. Fixed, and the decision now lives in a helper so it is testable.
- **`#F13`** — the fast single-pass heading reader written to replace
  twelve greps was fence-blind, re-opening a hole a sibling plan had
  already closed in `plan_state_body`. The first regression test for it
  passed under the very mutation it was meant to catch; it took reshaping
  the case to the shape that actually breaks.
- **`#F17`** — `plan_field_refs` dropped the last entry of every
  reference list, and four reviewers read that helper without seeing it.
  It surfaced only on running the thing with more than one value.

`gate-tests` grew from 82 assertions to **102**, covering `plan-lint`, the
active-plan marker, both frontmatter readers, the bare-filename rule,
`plan-repair`, and the lint gate on both doors to freeze; each new case was
observed failing under the mutation that reintroduces its defect. Measured
2026-09-08: **1.26s**, over the one-second budget — the `plan-reject`
cases cost 0.18s between them, and the third `security` pass added six more
that invoke real gates. See `#G8`, and `#G11` for
what the budget is worth against `verify-ladder`'s 24s.

The `plan-reject` half-state guard (`#F31`) took **three attempts, and the
first two asserted nothing**: one passed because the fixture had no
`rejected/` directory, so `git mv` failed whatever the gate did, and the
next because the probe file was untracked, so `git mv` failed again. Both
looked like a passing test of the right thing. Only the third, with the
directory present and the file staged, goes red when the gate is moved back
after the move.

**The second `security` pass, owed because the fix stage changed code,
found five more — and two of them were in the regression tests written
during the first.** `#F18`: the case guarding `#F11` keyed on the
self-freeze *warning*, so restoring the bypass in full left the harness
green; enforcement and warning are now separate assertions. `#F21`: the
duplicate-key probe read `plan_frontmatter`'s *first* value, so it agreed
with `plan_get_field` even with first-wins deleted; it now reads the last,
which is how `plan-lint`'s consumer loop reads it.

**That shape has now occurred eight times across two plans** — `#F3`,
`#F6`, `#F7` and `#F10` on
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md,
and `#F10`, `#F13`, `#F18` and `#F21` here — and four of those eight were
in tests written to catch it. The pattern is stable enough to state as a
rule: **a test keyed on a diagnostic asserts that the diagnostic exists,
not that the check ran.** When a defect has several symptoms, key the test
on the symptom the bypass removes, not the one it preserves. Each of the
eight was found by mutation and none by reading.

By the letter of D7 a third `security` pass is owed, since fixing
`#F18`-`#F22` changed code again. It was not run: D7's own recurrence rule
says to seek sign-off rather than loop when the same finding keeps
returning, and this is that case. Every one of the five fixes was confirmed
by mutation instead, which is the evidence a re-read does not produce.
**That is the user's call, not the agent's** — the PR stays a draft until
it is made.

**The third `security` pass ran, and it was the right call.** `#D1` asked
for it rather than a sign-off, and it found seven more: three MEDIUM, and
none of them cosmetic. `plan-freeze` was still deciding "already frozen"
from the file's own field, so flipping that field back and re-running would
have rewritten the recorded checksum to a tampered hash (`#F34`).
`plan-reject`'s `git mv` was unchecked, so a failed move left the plan
stamped rejected in `todo/` while the script froze and checksummed whatever
sat at the destination — and exited 0 (`#F36`). And `plan-repair` could
launder any unrelated working-tree edit, because it never checked the file
against its recorded checksum before re-blessing it (`#F40`), which made the
documented claim that it "cannot edit a word of anyone's text" false.

**`#F35` is the one to read.** Six mutations, each restoring a defect this
branch had just fixed, all passed the harness 98/98 — including `#F23`'s
own. `plan-repair` had three cases and no positive control at all, so making
it a no-op passed. The first replacement control asserted the section
existed and the checksum verified; that still passed with the insertion
point moved to another heading. It only became real once it asserted the
section lands *first*. Every one of the five is now caught, each observed
failing under the mutation it names.

That is the tenth through fifteenth instance of the shape this plan has been
tracking, and the pattern in the last three is specific enough to name: a
test that sets up a fixture is only as strong as the fixture's ability to
reach the failure. Three separate guards passed because a directory was
missing, a file was untracked, or a probe already satisfied the check by
another route — not because the code was right.

Not started: the G-to-F reclassification. Its design is settled in
`#G4`, its first batch is chosen (the file `#D4` names, 42 `G` items),
and nothing has been moved yet.

Verified to rung 3 (ran it locally, output inspected): `verify-ladder`
passes with the lint genuinely running over this plan, `gate-tests` is
96/0/3 and hermetic, `plan-citations` resolves every citation,
`sha256sum -c docs/plans/.checksums` passes on all 50 frozen plans, and
the migration's dry run was read before it was applied. Rungs 4-5 do not
apply — no host-visible behaviour changed, and the diff contains no
`.nix` file, no secret and no host.

### Pick-up point, 2026-09-07

**Where.** Worktree
`/home/lilijoy/dotfiles/.claude/worktrees/map-plan-docs-channel-routing`,
branch `worktree-map-child-2-plan-file-layout`, PR **#69** (draft). Work
there, never the main checkout. The previous branch,
`worktree-map-plan-docs-channel-routing`, merged as PR #68 and is done.

**Committed and pushed through `08996f3`.** `0ca8889` is the schema
change and the 51-file migration; `08996f3` closes the second `security`
pass. Every finding here is resolved, `plan-lint` and `plan-citations`
pass, `gate-tests` was 92/0/3 at that commit and is **96/0/3** as of
2026-09-08, and `verify-ladder` passes end to end with the lint genuinely
running over this plan.

**One thing blocks the PR, and it is the same decision as before.**
`plan-gate` refuses on stale `security` *and* `docs-updater` stamps,
because fixing `#F34`-`#F40` changed code after both last looked. Branch
HEAD is `54c67e6`.

`#D1` answered this question once already — run the pass rather than sign
off — and running it was clearly right: the third `security` pass found
seven, three MEDIUM, including a path that would have let the freeze
evidence re-bless a tampered file. So the loop is still earning its cost,
and it has also produced the next stale stamp. Either run
`security` and `docs-updater` once more over `git diff 10469cf..HEAD` and
resolve what they find, or record the sign-off. **Do not self-issue a
stamp.**

Worth weighing when deciding: this round's findings were more serious than
the previous round's, not less. Rounds one and two were mostly about the
harness lying to itself; round three found three live defects in the
scripts themselves.

**Next, and it is the substance of this plan: the G-to-F
reclassification.** Nothing has been moved yet. Everything needed to
start is settled:

- **The shape** is `#G4`: move the body to `### F<N>`, leave `### G<N>`
  as a one-line pointer so inbound `#G` citations keep resolving, and
  delete the pointer only in the contract phase. Not `#G6`'s literal
  "add the new beside the old", which means two copies of every item.
- **The first batch** is
  2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md, the
  file `#D4` names: 42 `G` headings, of which `#D4` counts 33 as open
  defects. Classify each as defect (becomes `F`) or lesson (stays `G`)
  before moving anything.
- **The bound** is `#G2`: 24 of the 47 live `#G` citations resolve into
  frozen plans and can never be migrated, so contract completes per
  batch and never corpus-wide. `#G` remains a valid citation form.
- **The check** is `plan-citations`, which must report zero broken
  citations after each batch. That is the gate `#G6` makes the contract
  phase wait on.

**Live traps a new session will hit:**

- `gate-tests` is at ~1.0s against a one-second budget (`#G8`). Split a
  fast tier from a slow one *before* adding cases, or the whole harness
  becomes something people skip.
- `plan-lint` now takes "frozen" from `docs/plans/.checksums`, not from
  the `frozen:` field. A plan that disagrees with the manifest is
  reported in both directions (`#F11`, `#F20`).
- A throwaway plan created by `plan-new` and then deleted leaves
  `.claude/.active-plan` dangling. That used to make `verify-ladder`
  skip its lint silently; it now blocks (`#F10`). Remove the marker or
  repoint it.
- 18 of 102 plans still fail `plan-lint`, 17 of them non-frozen and 16
  of those failing on `origin/master` too. They are pre-existing, not
  this change; do not treat a red corpus sweep as a regression without
  comparing.

## Original plan

Child 2 of
2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md,
implementing its `#D4` (revise the schema, do not rewrite it) under the
ordering its `#G6` requires (expand—contract, because renaming a
defect's anchor breaks every citation pointing at it).

Four changes, in decreasing order of how mechanical they are:

1. **`## State` moves above `## Original plan`.** The latter is stale by
   construction and currently sits above the only section guaranteed to
   be true.
2. **Frontmatter gains `priority`, `blocked_by`, `superseded_by` and
   `kind`.** `kind` is `task` or `map`; `blocked_by` is what makes
   expand—contract expressible as a blocking-edge graph rather than a
   separate skill.
3. **Defect `G` items become `F` items.** `D` has `plan-decide` and `F`
   has `plan-resolve`; `G` has neither, which is right for a lesson and
   wrong for a defect. `G` returns to meaning lesson and needs no drain.
4. **`plan-new`, `plan-lint` and the skill docs follow.**

Change 3 is the only one that can break anything, and `#G6` fixes its
order: add the new `F<N>` beside the old `G<N>`, migrate citations in
batches, delete the old anchors only once `plan-citations` reports zero
unresolved references.


## Progress

Expand, in this order:

- [x] schema: `plan-new` emits `## State` first and the four new
      frontmatter fields; `plan-lint` validates them
- [x] migrate the 51 non-frozen plans to the new section order and
      frontmatter, mechanically
- [x] `plan-lint` accepts both section orders while frozen files still
      carry the old one — see `#G1`
- [x] document `kind` and the expand—contract map pattern in the `plan`
      skill's `reference.md`
- [x] G-to-F expand for the first batch, the file `#D4` names, with the
      old `### G<N>` left as a resolving pointer
- [x] migrate the citations of that batch

Contract, only once `plan-citations` reports zero unresolved references
for a batch:

- [x] drop the pointer headings for migrated batches — done for batch 1;
      `#F49` records what the check for "no reference remains" misses, and
      `#G4` now carries the three steps a later batch must follow
- [x] remaining batches — closed, not skipped. All four of the biggest
      files were classified item by item and all 23 items correctly stay
      `G`; the other 21 files were surveyed at heading level with the same
      result. The premise held for one file, which is done. `#G15`

Decided 2026-09-08 and done in the same session:

- [x] `#D5` — `superseded_by` removed from the schema, both scripts,
      the docs and all 52 files; `priority` kept, because its reader is
      the user
- [x] `#D3` — the bare-filename rule moved into `plan-citations`, which
      scans every `*.md` and script rather than one frontmatter field, and
      the 8 reachable path-form citations rewritten. Frozen files are
      exempt, since they cannot be edited to comply
- [x] `#D4` — `plan-repair` added, and all 27 frozen plans that predated
      `## State` repaired: +216 lines, 0 deletions
- [x] `#D4` — `plan-freeze` lints before it freezes, which is the root
      cause those 27 came from

Also done 2026-09-08:

- [x] `#G12` — `scripts/gate-mutants`, the mutation catalogue the suite
      runs against itself; 39 entries, all caught
- [x] `#F41` — the seven guards it found that do not guard, all closed
- [x] a `precondition` verb in `gate-tests`, so a fixture that cannot
      reach the failure its case names fails under its own name

- [x] `#D2` — answered: the slow tier becomes a `checks.*` entry in
      `modules/flake/checks.nix`, not a GitHub Actions step. This also
      settles where `gate-mutants` runs (`#G13`)

- [x] built the `checks.*` entries `#D2` chose, and split the fast tier
      from the slow one (`#G8`). `checks.gate-tests` and
      `checks.gate-mutants`, both via `tests/gate-script-check.nix`.
      `verify-ladder`'s direct call stays, and `#F46` is why

Still open:
- [x] extended the sabotage sweep to `plan-move`, `plan-freeze` (swept
      through `plan-move ... done`, which execs it) and
      `.githooks/pre-commit`, each with a pristine fixture restored per
      iteration. It found `#F47` and `#F48`. `subagent-stamp` is exempt
      and the exemption is asserted rather than assumed — see `#G14`


## Decisions (D)

### D1 - run the third security pass, or sign off on stopping?

`plan-gate` refuses PR #69 on a stale `security` stamp, because the
`#F18`-`#F22` fix stage changed code after `security` last looked. D7's
letter says run it again; D7's recurrence rule says seek sign-off when the
same finding keeps returning, and the shape had returned eight times.

The argument for running it: the previous two passes each found live
defects, and two of those were in the regression tests written during the
pass before. The argument for stopping: every fix was already confirmed by
mutation, which is stronger evidence than a re-read.


**ANSWERED 2026-09-08:** the user (LilijoySkyseeker) chose 2026-09-08 to run the third security pass rather than sign off on stopping

### D2 - where does `gate-tests` run server-side?

`#F4` on
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md
is accepted-for-now: `gate-tests` runs only from `verify-ladder`, which is
agent discipline. The case where a gate is broken is exactly the case where
`verify-ladder` may not be run.

Three homes, judged against the user's stated goal of depending on GitHub
less:

- **A `checks.*` entry in `modules/flake/checks.nix`.** Runs under
  `nix flake check`, so it runs on any machine, in any CI, and locally. The
  enforcement lives in the repo rather than in a vendor's YAML. Needs
  `git` in the check's inputs and `verify-ladder`'s direct call dropped in
  the same change, or the harness runs twice per pass.
- **A CI step beside `plan-gate.yml`.** Ties the gate to GitHub Actions,
  which is the dependency to reduce.
- **A git hook.** Runs on a developer machine, not a server, and
  `--no-verify` switches it off. It is not server-side enforcement at all.


**DISCUSSED 2026-09-08:** the user wants to depend on GitHub less and asked for the best option, not the quickest; still open, see the three homes above


**ANSWERED 2026-09-08:** a checks.* entry in modules/flake/checks.nix -- the user (LilijoySkyseeker) chose 2026-09-08 the option that keeps enforcement in the repo rather than in GitHub Actions. #G11 is why it is affordable: the tier runs inside nix flake check, which verify-ladder already runs last and which is 94% of the ladder, so the slow tier keeps running locally on every pass and the 'nothing runs them at all' risk that blocked the split disappears. Wiring it is a separate change: the check needs git in its inputs, and verify-ladder's direct gate-tests call must be dropped in the same commit or the suite runs twice per pass

### D3 - does the bare-filename rule move into `plan-citations`?

`plan-lint` checks that `blocked_by` names a bare filename and never a
path. `SKILL.md` states that rule repo-wide, but only these two frontmatter
fields enforce it, and they are the least likely place to break it.
`plan-citations` scans every `*.md` and every script, which is where the
rule would actually bite.

~~Measured before proposing it: **60 path-form plan references exist in the
repo today**, a mix of real citations and ordinary prose paths. Moving the
rule fails all 60 until they are sorted.~~

**Corrected 2026-09-08:** that count was wrong, and it was the number the
decision was taken on. 50 of the 60 were lines of
`docs/plans/.checksums`, which is a manifest of paths by design and is not
in the citation scan set at all; the `grep -v` meant to exclude it did not
match the output format. The real figure is **11 occurrences in 7 files**,
of which 8 are reachable and 3 sit in frozen plans. The decision is
unaffected and cheaper than it looked.


**ANSWERED 2026-09-08:** yes -- the user (LilijoySkyseeker) agreed 2026-09-08 to move the bare-filename rule into plan-citations and sort the 60 path-form references

### D4 - can a frozen plan file ever be repaired?

27 frozen plans are malformed: they predate `## State` and have no such
section. No gate checks a plan at the moment it freezes, which is how they
got that way, and `plan-freeze`'s contract means no script will touch them
again. So the count can only grow.

The freeze contract exists for a good reason: a frozen plan is citeable
evidence, and its checksum is what proves it did not change. Any repair
path has to keep that property rather than punch a hole in it.


**ANSWERED 2026-09-08:** yes -- the user (LilijoySkyseeker) asked 2026-09-08 for a deliberate one-time repair path for the already-frozen malformed plans, rather than leaving them permanently broken

### D5 - do `priority` and `superseded_by` both stay?

Neither field has a reader or a writer today. `plan-supersede` is unbuilt
(item 9 on the map plan), so nothing writes `superseded_by`; nothing sorts
or filters on `priority`. Two `/simplify` angles and the altitude review
all argued to add each field with the tool that uses it, rather than ahead
of it.

The counter-argument is that `priority` is not for a tool. It is for the
user to read.


**ANSWERED 2026-09-08:** keep priority, drop superseded_by -- the user (LilijoySkyseeker) decided 2026-09-08 that priority is for their own reference and so has a reader, while superseded_by has none and should land with plan-supersede

## Gotchas (G)

### G1 - the frozen half of the corpus can never adopt the new schema

`plan-freeze` makes a file permanently un-editable and records its
checksum, and all 50 `done/` plans are frozen. They keep
`## Original plan` first and the four-key frontmatter forever. Two
consequences, both of which the tooling has to state rather than
discover: `plan-lint` cannot require the new fields unconditionally, and
any migration pass has to skip frozen files rather than fail on them.

This is not damage. It follows from `#D5` on the map plan (nothing is
deleted) plus the freeze contract, and the alternative — unfreezing 50
files to reorder their sections — would destroy the one property that
makes a frozen plan citeable evidence.

### G2 - half the live `#G` citations can never be migrated, so the contract phase has no end state

24 of the 47 live `#G` citations resolve into frozen plans. Those
anchors cannot be renamed, so `#G` stays a valid and permanent citation
form no matter how much of the corpus migrates.

The map's `#G6` describes the contract phase as deleting the old anchors
"once the checker reports zero unresolved references". That condition is
reachable per batch and never reachable corpus-wide. Contract is
therefore defined here as per-batch, and `G` is not being retired — it
is being narrowed to its design meaning for files that can still change.

### G4 - expand moves the body and leaves a pointer, rather than duplicating it

`#G6` says to "add the new `F<N>` beside the old `G<N>`". Taken
literally that means two copies of every migrated item for as long as
the expand phase lasts, and the map's own classification of the review
that produced it names exactly that shape as its most frequent defect
class: the same fact rendered in two channels drifts. Twelve of its
findings were that.

So expand is done as a move plus a pointer. `### F<N>` carries the body;
`### G<N>` is reduced to one line naming its successor, which keeps
every `#G<N>` citation resolving — the only property the expand phase
actually needs. Contract then deletes the pointer once no reference
remains, per `#G6`.

This is a deliberate departure from the append-only rule, which is why
it is recorded rather than just done: the body is not deleted, it is
relocated within the same file, and the pointer is what makes that
auditable.

**Amended 2026-09-09, after contracting batch 1 (`#F49`).** "Once no
reference remains" cannot be read as "once `plan-citations` is green". That
checker resolves `<file>.md#anchor` and is blind to a bare `` `G17` `` in
prose, which is how a plan refers to its own items — batch 1 had seven of
them. Before dropping a batch's pointers:

1. Migrate the anchored citations, and grep **without** an extension filter:
   the `plan-*` scripts carry `# plan:` citations and have no extension.
2. Read every bare `` `G<N>` `` in the file's own bodies and classify each
   one. Some name *this* file's items and must move; some name a different
   plan's, or quote historical text, and must not. There is no safe
   substitution rule, only judgment per reference.
3. Renumber the surviving lessons from 1, and record the old numbers in the
   file so an older revision stays readable.

### G3 - `#G6`'s citation count was 18 and is now 47

Charted 2026-09-05; measured 2026-09-07. The gap is two days of the
review loop on the map plan and this one, which cite `#G` anchors
heavily. Worth stating because `#G6` uses the number as the argument for
blocking child 2 behind child 5, and the argument got stronger, not
weaker, while the work waited.


### G5 - the frozen exemption is one decision, and it had to cover the section checks too

The first version of this change gated only the *new* schema rules behind
`plan_is_frozen`, and left the section-presence loop ungated. That loop is
itself an era rule — `## State` was a later schema addition — and it was
reporting `missing required section '## State'` on 27 frozen files. So the
guard bought nothing: 28 of the 45 failures were still on files nobody may
edit, and the precedent was that each future schema addition gets its own
ad-hoc `if`.

The rule is now one decision, stated in `reference.md`: rules that depend on
the schema era are checked on a plan the checksum manifest does not record
as frozen, and rules that do not — core frontmatter, status against folder,
id sequencing, Progress citations — are checked everywhere. (Written as
"where `frozen: false`" until `#F11`; the field is self-declared and the
manifest is not.) Corpus failures went 45 to 18, and the single
remaining frozen failure is a non-sequential id, which is correctly era-
independent.

`frozen` is still a proxy for "written before the schema grew", not the thing
itself. It is exact today, because the migration made every non-frozen file
current. A `schema:` version field would make the era explicit; that is worth
doing only if a revision ever needs to exempt an older *mutable* file, which
this one did not.

### G6 - nothing runs plan-lint at freeze time, which is how the frozen backlog got there

`plan-move done` and `plan-freeze` check decisions, findings, an empty
`## State` and the rung declaration. Neither checks structural validity, and
`verify-ladder` lints only the *active* plan. A malformed plan can therefore
be frozen malformed, and is then permanently unfixable.

That is the mechanism behind the 27 frozen files missing `## State`, and it
will keep producing them. `#G5` suppresses the noise; it does not fix the
cause. Adding `plan-lint` to `plan-freeze`'s gate list is the fix, and it is
its own change — it would need a decision about the files already frozen,
which by definition cannot be brought into compliance.

### G7 - the bare-filename rule belongs in plan-citations, but 60 references would fail today

`plan-lint` checks that `blocked_by`/`superseded_by` name a bare filename and
not a path. The existence half of that check was removed: `plan-citations`
already scans every `*.md`, already resolves these values, and reports an
ambiguous basename where the glob here silently accepted one. The comment
claiming plan-citations "cannot see" frontmatter was simply wrong, and was
disproved by running it.

What plan-citations genuinely cannot catch is the path form, because its
regex matches the bare filename *inside* the path and resolves that. The
deeper fix is to move the never-write-a-path rule into plan-citations, where
`SKILL.md` already states it repo-wide. Measured before proposing it: 11 path-form references exist in the repo
today (an earlier count of 60 wrongly included the 50-line checksum
manifest). Moving the rule fails all of them, so it needs its own decision
and a pass over them, not a ride-along in a cleanup. Done 2026-09-08 under
`#D3`.

### G8 - gate-tests is over its one-second budget, and the split is blocked on D2

The harness went 82 assertions to ~~97~~ **96** (re-counted from the
harness's own summary line, 2026-09-08), and 0.81s to **1.06s**. It now
covers `plan-lint`, the active-plan marker, both frontmatter readers, the
bare-filename rule, `plan-repair` and `plan-freeze`'s new lint gate.
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#G2
sets the budget at "under a second", because `verify-ladder` runs this
before every non-trivial commit and a gate people learn to bypass is worse
than no gate. It is over.

`#G2` names the remedy: split a fast tier from a slow one. **That split
cannot be made safely until `#D2` is answered.** The slow tier is the
sabotage sweeps, which is the part that finds real defects; moving them out
of `verify-ladder` with no server-side home means nothing runs them at all,
which is strictly worse than 1.06s. So the order is: answer `#D2`, give the
slow tier a home, then split, then extend the sweep to `subagent-stamp`,
`plan-freeze`/`plan-move` and `.githooks/*`.

Until then the budget is knowingly exceeded rather than silently, and no
case has been dropped to hide it. 1.06s is not yet the number that teaches
bypassing; four more swept gates would be.

The cost is concentrated in the sweeps: each runs its gate once for the
baseline and once per git call, so a gate making eight calls costs nine
invocations. `plan-gate` alone is nine, and is 22% of the whole harness.

**Corrected 2026-09-08, three times over.** ~~The harness is over budget.~~
~~It is back under, at 0.97s.~~ It is over again at **1.15s**, because the
`#F31` guard on `plan-reject` costs 0.18s. That is the honest number and it
is not being hidden by dropping a case; `#G11` is why it is being accepted
rather than chased. The middle claim held only briefly: the sabotage shim read its counter with `$(cat)` on
every git call the swept gates make, and `read` instead removed about 100
forks. And "concentrated in the sweeps" is only half true — they are the
largest block at 42%, but 58% of the runtime is outside them, so splitting
them out lands at ~0.60s rather than anywhere near zero. More importantly
`#G11` measures what the budget is actually being defended against:
`gate-tests` is 4% of `verify-ladder`, and `nix flake check` is 90%.

**Settled 2026-09-08.** The split landed, and it is not the one this item
proposed. The sabotage sweeps stay in the fast tier: `#G11` prices them at
0.46s of a 24s ladder, and they are the part that finds real defects, so
moving them out buys 2% of the ladder for the loss of the only sweep that
runs before a commit. The real fast/slow boundary was already there --
`scripts/gate-tests` at 1.2s every pass, `scripts/gate-mutants` at ~40x
that -- and `#D2`'s answer gave the slow side a home as
`checks.gate-mutants`. The one-second budget is not defended any more, and
is recorded as knowingly exceeded rather than met by dropping cases.

### G9 - `nix flake check` fails on a garbage-collected derivation, and the error names the wrong culprit

`verify-ladder` blocked mid-session on
`error: path 'ihrfigy8...-base16-schemes-0-unstable-2026-01-15.drv' is not
valid`, with a stack trace pointing at home-manager's firefox module. None
of that is where the problem is.

**It is not a repo fault.** The diff contained no `.nix` file, and a
pristine `origin/master` checkout reproduced it identically. Nix had
garbage-collected a derivation that evaluation still needs, and the eval
cache was not the cause — clearing
`~/.cache/nix/eval-cache-v6` changed nothing.

**The fix is to re-instantiate the package**, which restores the `.drv`:

```
nix build --no-link --impure --expr \
  '(builtins.getFlake (toString /path/to/repo)).inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.base16-schemes'
```

Note `nixpkgs-unstable`, not `nixpkgs` — this flake has no input by that
name, and the obvious spelling fails with "attribute 'nixpkgs' missing".

**Corrected 2026-09-08, after it recurred and the command above did not fix
it.** Two things were wrong with it, and both matter:

- **`--option substitute false` is required.** Without it the output is
  fetched from `cache.nixos.org` and the `.drv` is never instantiated, so
  the missing path stays missing and the error repeats verbatim. The
  substituted output even looks like success.
- **Try both nixpkgs inputs, not just `nixpkgs-unstable`.** The failing
  derivation belonged to `nixpkgs-stable`; hosts pinned to the stable
  release evaluate a different `base16-schemes` with a different `.drv`
  hash, and the stack trace names neither input.

So the command that actually works is, for each of `nixpkgs-stable` and
`nixpkgs-unstable`:

```
nix build --no-link --impure --option substitute false --expr \
  '(builtins.getFlake (toString /path/to/repo)).inputs.<input>.legacyPackages.x86_64-linux.base16-schemes'
```

The general shape is worth more than the specific package: when
`nix flake check` names a `.drv` that is not valid, re-instantiate the
package from **every** nixpkgs input this flake has, with substitution off.

Worth knowing because it will recur: any GC that removes a derivation
evaluation needs produces this, the message names the derivation rather
than the input that wants it, and `verify-ladder` hard-blocks on it. The
separate todo plan
2026-08-28-nix-flake-check-fails-on-zrepl-replication-test-pk.md is about a
*different* cause, which PR #68 fixed; it is stale and probably closable.

### G10 - there are two doors to freeze, and only one was guarded

`#G6` said "nothing runs plan-lint at freeze time" and the fix went into
`plan-freeze`. `plan-reject` also freezes, by calling `plan_do_freeze`
directly, and it was still unguarded — so the backlog `plan-repair` exists
to clear could keep growing through `rejected/`.

Both doors now lint. The counter-argument is real and worth recording rather
than leaving as an unstated choice: `plan-reject` deliberately waives the
decision and finding gates, because abandoning work legitimately moots open
questions, and the same reasoning could extend to structure — refusing to
file away an abandoned half-written plan is a gate that teaches the bypass.

It was resolved the other way because a rejected plan is still citeable
evidence forever, and the structural bar is six headings a `plan-new` file
already has. The friction is real but bounded: **17 non-frozen plans predate
`## State` and would now need one sentence before they can be rejected.**
That is the same friction the user accepted for the rung declaration.

### G11 - gate-tests is 4% of what verify-ladder actually costs

`#G8` treats the harness's second as the budget to defend. Measured end to
end on this worktree, `verify-ladder` takes **26.0s**, of which
`nix flake check --no-build` is **23.5s** and `gate-tests` is 1.0s. The
sabotage sweeps — the part `#G8` proposes to move — are 0.46s, which is
smaller than the run-to-run variance of the step they would move into.

This bears directly on `#D2`. If the slow tier becomes a `checks.*` entry it
runs inside `nix flake check`, which `verify-ladder` already runs last, so
the tier keeps running locally on every pass and the "nothing runs them at
all" risk disappears. The number was not in front of `#D2` when it was
framed, and it probably decides it.

### G12 - the suite has no measure of its own strength, and that is the thing to fix

102 assertions passing told us nothing. In the same session, six mutations
that each restored a defect the branch had *just fixed* passed the harness
98 of 98 — including the one for a regression fixed two commits earlier
(`#F35`). Every real finding this session came from a person or an agent
mutating code by hand and watching what happened. Nothing in the suite
measures whether the suite works.

Six principles, each paid for by a specific finding here rather than taken
from a book:

1. **A test never observed failing has not been tested.** `#G2` on
   2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md
   already says this. This session supplied fifteen instances, four of them
   inside tests written to catch the very shape they missed.
2. **A test is bounded by what its fixture can reach.** Three separate
   guards passed because the setup could not produce the failure: no
   `rejected/` directory, an untracked probe, and a probe already refused
   by another rule. All three looked like passing tests of the right thing.
   A negative case should assert that its precondition actually holds
   before asserting the refusal.
3. **Key the assertion on the symptom a bypass removes, not the one it
   preserves** (`#F18`). The self-freeze guard emitted nine reports; the
   case keyed on the one a full bypass left intact.
4. **Assert the property, not a proxy for it** (`#F35`). "The section
   exists and the checksum verifies" passed with the insertion point moved
   to a different heading. Only "the section lands first" was the property.
5. **The instrument has to be able to observe the property** (`#F14`). Two
   rounds went into counting calls through a shim to prove something about
   calls the shim cannot see. A dynamic check cannot assert a property
   about what it cannot observe; that one had to move to a static read of
   the source.
6. **A negative case without a positive control is half a test.**
   `plan-repair` shipped with three refusal cases and no control, so making
   it a no-op passed.

**What follows mechanically.** The suite should run its own mutations. A
catalogue of (target file, mutation, the case that must go red) executed as
a meta-test would have caught `#F35` without anyone thinking of it, and it
turns "is this suite any good" from an argument into a measurement. The
mutation set is already written down — it is scattered through this plan's
findings and the harden plan's, and every entry names the case it should
break.

**Constraints the next session inherits.** A mutation run costs roughly N×
the suite, so it belongs in a slow tier and not in `verify-ladder`'s
pre-commit path; that depends on `#D2`, which is open. `gate-tests` is
already at 1.26s against `#G2`'s one-second budget, and `#G11` measures
what that budget is worth: the harness is 5% of `verify-ladder`, and
`nix flake check` is 94%.

### G13 - what building the measurement cost, and the three ways a mutation entry lies

`#G12` said the suite should run its own mutations. It now does:
`scripts/gate-mutants` is a catalogue of (target file, mutation, the case
that must go red) -- 39 entries, every one harvested from a finding in this
plan or
2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md.
It builds a throwaway tree holding only `scripts/gate-tests` and
`docs/skills/{plan,workflow}` -- the suite is relocatable, which is what
makes this possible without touching the working copy -- applies one
mutation, runs the whole suite, and requires the named case to fail.

**The first honest run caught 28 of 38 and found seven guards that do not
guard** (`#F41`). None of the seven was found by reading, and the code
around four of them had been read by three review passes.

**A catalogue entry is a claim with three parts, and each part can be wrong
on its own.** Each gets its own verdict rather than folding into pass/fail,
because each wrong part otherwise reads exactly like success -- which is
the defect class the catalogue exists to find.

- `UNKNOWN-CASE` -- the named case appears in no clean run. A renamed case
  would otherwise turn its entry into a permanent silent escape.
- `INERT` -- the mutation left the file byte-identical. An anchor that has
  drifted measures nothing, and reports the same as an escape.
- `BROKEN` -- the mutant no longer parses, so its red cases say nothing
  about the defect, and if the named case is among them it reads as a
  catch. Asserted with `bash -n` on the mutated file rather than inferred
  from how many cases went red: a mutation that broke `lib.sh` outright
  still printed a summary line and 71 of 113 red, so a summary-line check
  alone missed it.
- `ESCAPED` -- the finding.

Each of the four was verified to fire, against deliberately bad entries in
a throwaway copy, before the catalogue's own verdict was believed. A run
also flags any mutation that reddens more than a quarter of the suite,
since a catch under those conditions is probably a catch for some other
reason.

**Cost, measured 2026-09-08:** 39 mutants, **7.0s** wall across 16 jobs
(~46s of CPU). Roughly N x the suite by construction, which is why it is
not in `verify-ladder`'s pre-commit path; where it runs server-side is the
same open question as the fast/slow split, `#D2`. `gate-tests` itself went
102 assertions to **110**, and 1.07s to **1.20s** measured back to back on
this host -- eight new assertions for 0.13s, and five of the seven gaps
closed by repairing a fixture rather than by adding a case.

**The rule this leaves behind:** a finding that names the case which should
have caught it *is* a catalogue entry, and belongs in `gate-mutants` in the
same change. The whole mutation set was already written down across two
plans' findings before any of it was executable.


### G14 - subagent-stamp is exempt from the sabotage sweep, and the exemption is an assertion

2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#G2
lists `subagent-stamp` among the gates left to sweep. It should not be
swept, and that is a property of what it is rather than an omission.

Every failure path in it ends `exit 0` — no repo root, no active plan, a
frozen plan, an uncomputable fingerprint — and its one `git add` ends
`|| true`. That is correct for a `SubagentStop` hook: it runs at the end of
every subagent, and a hook that fails takes the session with it. The sweep
asserts the opposite property, "no gate may report success when a git call
underneath it failed", so sweeping this one would demand a refusal it is
designed never to make.

The signal it does carry is the absence of a stamp. `plan-gate` blocks on a
missing stamp, so a `subagent-stamp` that silently does nothing is caught
one gate later, by the gate whose job that is.

An exemption with no test is indistinguishable from an oversight, so
`gate-tests` asserts the reason instead of the behaviour: a `known` residue
that checks the `|| true` and the `exit 0` paths are still there, and turns
into a failure if they go. `gate-mutants` carries the matching entry.

### G15 - the G-to-F reclassification was one file's job, not the corpus's

Batch 1 is done and the migration is closed. Not because the remaining 25
files were skipped, but because reading them showed there is nothing there
to move.

**The four biggest were classified item by item: all 23 stay `G`.** The
minecraft plan's seven are a world layout, a headless-CLI finding that
contradicts an open upstream issue, measured chunk counts, an
`InhabitedTime` blind spot, a backup procedure, verified CLI syntax and a
`/tmp` warning — lessons, every one. The ZFS plan's four are constraints to
respect. The Loki plan's eight are design drivers, and the two that read
like defects say so themselves: `G1` ends "it is also why D7 raises the
limit", and `G5` scopes `D13`/`D17`. The `/etc/nixos` plan's `G3` opens
"the durable lesson is not about this one commit".

**The other 21 were surveyed at heading level, all 80 of them**, and the
pattern holds: discovered facts, measurements, constraints, corrections of
record.

**Why the premise held for exactly one file.** 2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md
was written as a deliberately over-inclusive catalogue of weak points, at a
time when `F` had no meaning — so its defects were recorded as `G` because
there was nowhere else to put them. Every other plan used `G` the way the
rule now defines it. Batch 1 was not the first of 26 batches; it was the
whole job.

**Converting a correct `G` is not free**, which is why "migrate everything"
would have been the wrong call rather than merely a slow one: it renumbers
anchors, and it creates an unresolved finding that blocks `plan-move ...
done` and `plan-gate` for any commit citing that plan. The one arguable
candidate — `#G2` in the `/etc/nixos` plan, a real `--ff-only` breakage —
is left as `G` for exactly that reason: its remedy belongs to the
pipeline-rebuild plan, so an `F` here would be an obligation this plan
cannot discharge.

`#G4` keeps the procedure written down for any future file that does need
it.


## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — `## State` claimed plan-lint resolves the ref fields, and restated the "plan-citations cannot see frontmatter" claim `#G7` retracts

- **File:** this plan's `## State`, the `plan-lint` bullet (lines 29-32
  before the fix)
- **Finding:** the bullet read "resolves `blocked_by`/`superseded_by`
  against real plan files — references frontmatter can hold that
  `plan-citations` cannot see, because they are not prose." Neither half
  survives the code: `plan-lint` checks only the `*/*`/`*..*` shape of
  each ref, the existence half having been removed, and `#G7` in this
  same file records that the "cannot see" claim was wrong and was
  disproved by running `plan-citations`. State and `#G7` contradicted
  each other in one file.
- **Fixed** in place: the bullet now says shape-only and points at
  `#G7`. No other surviving restatement of the "cannot see" claim exists
  — grepped `docs/`, `workflow/`, `.githooks/`, `AGENTS.md`.


**FIXED 2026-09-07:** docs-updater rewrote the State sentence; the 'plan-citations cannot see frontmatter' claim was disproved by running it and is retracted in G7. Grepped repo-wide, no restatement survives

### F2 — "52 non-frozen plans migrated" counts this file, which was generated, not migrated

- **File:** this plan's `## State`, the migration bullet
- **Finding:** `git diff --cached --name-status -- docs/plans/` is 51
  `M` and 1 `A`; the `A` is this plan, created by `plan-new` in the new
  schema. `## Progress` already said 51. Verified alongside it that the
  migration is content-preserving: every one of the 51 nets exactly +4
  lines (`--numstat`), and a sorted-line diff of each file against
  `HEAD` yields only the four added keys and nothing else.
- **Fixed** in place: 51 migrated, this file named as the 52nd
  non-frozen plan.


**FIXED 2026-09-07:** State now says 51 migrated plus this file generated by plan-new, not 52 migrated

### F3 — the timing figures in `## State` do not reproduce on this host

- **File:** this plan's `## State`, the "And it got cheaper" paragraph
- **Finding:** re-measured on the same machine, same method (100 runs
  over the largest non-frozen plan; a full sweep of the corpus, three
  runs each, variance under 10 ms): 27.3 ms → 21.5 ms per file, and
  2.48 s → 1.76 s for the sweep. `## State` says 25.3 → 19.3 ms and
  3.54 s → 1.81 s. The "now" numbers agree; the before-sweep 3.54 s is
  43% above anything reproducible, including the old linter run against
  the *new* corpus (2.50 s), which was the most plausible alternative
  method. The qualitative claim — more checks, roughly 20-25% cheaper
  per file, sweep down about 30% — holds either way.
- **Not edited:** the original was presumably measured under different
  load, and picking whose number to publish is the author's call. Cite
  the ratio, not the absolute figure. Separately, `plan-citations` now
  resolves 335, not the 331 recorded as evidence — that count grows with
  every citation written and is not a defect.


**FIXED 2026-09-07:** the figures were two different baselines. Re-measured in this worktree, 100 runs x3, spread under 0.02s: origin/master 25.5 ms per file, reworked 19.4 ms. The 3.5s sweep was of the first version written this session, not of origin/master, which sweeps in about 2.5s against 1.8s now. State now names all three versions

### F4 — `reference.md` sent readers to `lib.sh` for a `status` vocabulary that is not there

- **File:** `docs/skills/plan/reference.md`, frontmatter section
- **Finding:** the new paragraph said the block "deliberately does not
  list what `status`, `kind` or `priority` may contain: those
  vocabularies are `PLAN_KINDS`, `PLAN_PRIORITIES`, `PLAN_CORE_FIELDS`,
  `PLAN_SCHEMA_FIELDS`, `PLAN_REF_FIELDS` and `PLAN_FIELD_VOCAB` in
  ... `lib.sh`". There is no status vocabulary in `lib.sh` — `plan-lint`
  checks `status` against the folder name — and the same edit had
  removed the `# todo | in-progress | done | rejected` comment that was
  the only place the legal values appeared. A reader following the
  pointer finds nothing.
- **Fixed:** the value list is back on the `status` line, and the
  paragraph now names `status` as the exception that is checked against
  the folder rather than against an array.


**FIXED 2026-09-07:** docs-updater restored the status value list and named it as the exception -- status is checked against the folder, not an array

### F5 — "frontmatter is only ever written by the scripts" is contradicted by the paragraph under it

- **File:** `docs/skills/plan/reference.md`, frontmatter bullet
- **Finding:** that line predates this change, but the new text three
  lines below it says `superseded_by` has no writer and is set by hand.
  Both `blocked_by` and `superseded_by` are hand-set today; no script
  writes either.
- **Fixed:** the bullet now excepts the two ref fields.


**FIXED 2026-09-07:** docs-updater excepted the two hand-set ref fields from 'only ever written by the scripts'

### F6 — lib.sh's frozen-exemption comment and its `#G1` citation sat on the wrong declaration

- **File:** `docs/skills/plan/scripts/lib.sh`, lines 48-55 before the fix
- **Finding:** the comment "Added by #D4. Required of non-frozen plans
  only ... plan: ...#G1" was followed immediately by a second comment
  block and then by `PLAN_REF_FIELDS`. The declaration it describes,
  `PLAN_SCHEMA_FIELDS`, was three lines further down under a different
  comment, so the only citation of the frozen-exemption rule pointed at
  the wrong array.
- **Fixed:** moved onto `PLAN_SCHEMA_FIELDS`, merged with the
  derived-not-restated note that was already there.


**FIXED 2026-09-07:** docs-updater moved the frozen-exemption comment and its G1 citation onto PLAN_SCHEMA_FIELDS, the declaration it describes

### F7 — "every consumer reads them from here rather than restating them" was not true of plan-new

- **File:** `docs/skills/plan/scripts/lib.sh`, the header comment on the
  vocabulary block; `docs/skills/plan/scripts/plan-new` lines 24 and 40
- **Finding:** three gaps behind the claim. (1) `plan-new` emits
  `kind: ${PLAN_KINDS[0]}` but `priority: normal` as a literal, so one
  default is derived from `lib.sh` and the other restated. (2) its emit
  loop tests `[ "$_section" = "## Findings (F)" ]` against a literal, so
  renaming that heading in `PLAN_SECTIONS` would silently stop emitting
  the placeholder note while both files still looked correct — the exact
  drift the comment claims the array prevents. (3) "the migration pass"
  was named as a consumer, but no such script is in the repo, so a
  reader greps for it and finds nothing.
- **Fixed** only the doc half: the comment now claims what is true — the
  *lists* are read from here, by `plan-new`, `plan-lint` and the skill
  docs. Whether to derive the `priority` default and the Findings-note
  test from `lib.sh` is a code decision left open.


**FIXED 2026-09-07:** docs-updater narrowed the doc claim to what is true; the two code couplings it left open are now closed as well -- the Findings placeholder keys off PLAN_SECTIONS' last element instead of a literal heading, and plan-new stamps PLAN_DEFAULT_KIND and PLAN_DEFAULT_PRIORITY instead of a literal 'normal'

### F8 — plan-new now emits a blank line between `## Findings (F)` and its placeholder note

- **File:** `docs/skills/plan/scripts/plan-new`, the `PLAN_SECTIONS`
  emit loop
- **Finding:** the loop prints `'\n%s\n\n'` per heading, so the note
  lands one blank line below the heading. The heredoc it replaced put it
  directly underneath, which is what `reference.md`'s worked example
  shows and what 95 of the 102 corpus files do (7 have the blank).
  Cosmetic, and `plan-lint` accepts both.
- **Not fixed:** changing generator output is a code call, not a doc
  one.


**FIXED 2026-09-07:** the placeholder now sits directly under its heading, matching the 95 corpus files that carry one

### F9 — the map plan's Progress item 2 still says "three frontmatter fields"

- **File:**
  2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md,
  `## Progress` item 2
- **Finding:** it describes this child as "`## State` first, three
  frontmatter fields, defect G-to-F reclassification". Four were added
  (`kind`, `priority`, `blocked_by`, `superseded_by`), which its own
  `#D4` and this plan's title both say.
- **Not fixed:** editing another plan's Progress line is the map's
  owner's call, and this child is not yet closed against it.


**FIXED 2026-09-07:** the map plan's Progress item 2 now says four fields, names them, notes that the line previously said three, and records that the schema half landed here

### F10 — `.claude/.active-plan` in this worktree names a file that does not exist, so verify-ladder's plan-lint step is a silent no-op

<!-- plan-citations: ignore-start (the dangling marker value below names no real plan, which is the finding) -->

- **File:** `.claude/.active-plan` (untracked), which holds
  `docs/plans/todo/2026-09-07-coupling-probe.md`
- **Finding:** no such file exists. `plan_active_plan` requires
  `[ -f "$root/$rel" ]` and returns 1 otherwise, and `verify-ladder`
  treats that as "(no active plan this session)" and skips the lint
  rather than failing. `## State` records "`verify-ladder` passes" as
  rung-3 evidence; on this marker that pass never linted this plan. The
  corpus sweep quoted beside it did cover it, so the evidence is not
  wrong, only weaker than it reads.
- **Not fixed:** repointing the session's active-plan marker is the
  running agent's call, not a doc edit.

<!-- plan-citations: ignore-end -->

**FIXED 2026-09-07:** the marker was repointed at this plan, and verify-ladder now blocks when the marker names nothing usable instead of skipping the lint under a line that reads like a pass -- plan_active_plan returns 1 for a dangling marker exactly as it does for no marker, and the caller could not tell them apart. Proved by pointing the marker at a missing file and watching the ladder report BLOCKED where it previously printed 'no active plan this session'

### F11 — plan-lint takes "is this file frozen" from the file's own frontmatter, not from the freeze manifest that actually enforces freezing

- **File:** `docs/skills/plan/scripts/plan-lint:52`; contrast
  `.githooks/pre-commit:15-30`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any agent or contributor authoring a plan file. `plan-lint`
  runs in exactly one automated place — `verify-ladder`'s "plan-lint (active
  plan)" step, which the `workflow` skill invokes locally. It is in no CI
  workflow and no git hook (`git grep plan-lint` outside `docs/plans/`
  confirms), so nothing here reaches a host, a secret or a merge gate; the
  reach is "the structural gate on the file that records a session's review
  evidence can be switched off by that file".
- **Rule:** n/a — no `docs/hardening.md` rule covers repo tooling. New-rule
  candidate: a gate must not read its own exemption from the artefact it
  judges.
- **Finding:** the new era exemption is `[ "${fm_val[frozen]:-}" != "true" ]`.
  `.githooks/pre-commit` deliberately does *not* trust that field — its
  comment says "only files with a manifest entry are actually frozen, so
  todo/in-progress files pass" and it gates on `docs/plans/.checksums`. So
  "frozen" has two definitions, and `plan-lint` picked the self-asserted one.
  Three ways to reach the exemption on a file that is fully editable and has
  no manifest entry, all built and run in a scratch repo against the staged
  scripts:
  1. Write `frozen: true` in a `todo/` plan. A file with no `## State`, no
     `## Findings (F)`, none of the six sections and none of the four new
     fields prints `OK`; the same file under `origin/master`'s `plan-lint`
     printed six problems. `status: todo` still matches the folder, so the
     one era-independent frontmatter check does not catch it.
  2. Duplicate the key — `frozen: false` then `frozen: true`. `plan_frontmatter`
     is last-wins, so `plan-lint` exempts the file, while `plan_is_frozen`
     (via first-wins `plan_get_field`) reports `NOT_FROZEN`, so `plan-move`,
     `plan-resolve` and `plan-decide` will all still write to it. See `#F12`.
  3. Omit or typo the closing `---`. `plan_frontmatter` has no
     end-of-block requirement, so it scans to EOF and harvests every
     `key: value`-shaped body line; a prose line `frozen: true` anywhere in
     the file then turns the exemption on. Reproduced: a file whose
     frontmatter runs to EOF yielded `Landed<TAB>` and `frozen<TAB>true`
     from its body and linted `OK`. Plan files that *document* this schema
     are the ones most likely to contain such a line.
  Also worth stating plainly: freezing now launders a lint failure into a
  pass. `plan-freeze` sets `frozen: true` and, per `#G6`, does not lint, so
  any of the 17 currently-failing non-frozen plans becomes `OK` the moment it
  is moved to `done/` without a single structural problem being fixed.
- **Fix risk:** reading `docs/plans/.checksums` from `plan-lint` couples the
  linter to the manifest and to a git-tracked path, and would make `plan-lint`
  report differently inside a fresh scratch checkout that has no manifest —
  `scripts/gate-tests` builds exactly such repos. A cheaper fix is to require
  `frozen` to be exactly `true` or `false`, reject a duplicate key, and require
  a terminating `---`; that changes no verdict on the current 102-file corpus
  (verified: every corpus file yields exactly the 8 expected keys, no
  duplicates, no unterminated block).


**FIXED 2026-09-07:** plan-lint takes 'frozen' from the checksum manifest, which is what .githooks/pre-commit enforces and what only plan-freeze writes, instead of from the file's own self-declared field; a disagreement between the two is now reported in both directions. Verified: a todo/ plan asserting 'frozen: true' is reported and still gets every era rule, where it previously printed OK. Guarded in gate-tests

### F12 — `plan_frontmatter` is last-wins where `plan_get_field` is first-wins, so two readers of the same frontmatter in one library disagree

- **File:** `docs/skills/plan/scripts/lib.sh:88-103` (`plan_get_field`, `exit`s
  on first match) vs `:127-144` (`plan_frontmatter`, prints every match);
  `docs/skills/plan/scripts/plan-lint:25-29` (`fm_val["$fkey"]="$fval"`,
  overwrites)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** same principal as `#F11` — a plan author. Demonstrated:
  a file with `frozen: false` followed by `frozen: true` makes `plan-lint`
  print `OK` while `plan_is_frozen` on the same file returns not-frozen.
- **Rule:** new-rule candidate. `lib.sh` states the one-definition principle
  repeatedly (`plan_in_list`, `PLAN_TEXT_GLOBS`, `plan_heading_re`,
  `plan_state_body`) and this change added a second reader that silently
  breaks it.
- **Finding:** the divergence is not confined to `frozen`. Every key
  `plan-lint` now reads comes from the last occurrence, while every other
  `plan-*` script reads the first — including `status`, which `plan-lint`
  checks against the folder and `plan-move` rewrites. `plan_frontmatter`'s
  header comment says "Presence and value both fall out of the one parse"
  and "plan_get_field stays the single-key reader every other plan-* script
  calls", which reads as a deliberate coexistence; it does not say the two
  resolve duplicates in opposite directions. Nothing in the current corpus
  has a duplicate key (verified across all 102 files), so this is latent,
  not live.
- **Fix risk:** making `plan_frontmatter` first-wins is a two-character
  change (`if (!(k in seen))`) and matches `plan_get_field`, but silently
  drops the ability to *detect* the duplicate. Reporting a duplicate key as
  a lint problem is the version that fails loud; it needs a check that no
  corpus file trips it, which the count above already supplies.


**FIXED 2026-09-07:** plan_frontmatter is first-wins, matching plan_get_field, so a duplicated key cannot make one file frozen to one reader and editable to another

### F13 — the new section reader is fence-blind, so a plan quoting the schema both passes checks it should fail and fails checks it should pass

- **File:** `docs/skills/plan/scripts/plan-lint:31-39, 53-64`; contrast
  `docs/skills/plan/scripts/lib.sh:273-297` (`plan_state_body`)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any plan that quotes a plan template in a fenced block —
  which is precisely what a plan documenting a schema change does, and what
  `reference.md`'s worked example already is. `verify-ladder` hard-blocks on
  `plan-lint` of the active plan, so the false-failure half is a gate a
  correct file cannot clear.
- **Rule:** new-rule candidate; this is a re-occurrence of
  2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md#F12,
  whose fix `lib.sh:266-272` explains at length — "a plan that *documents*
  this schema quotes a whole example plan, headings and all". The lesson was
  applied to `plan_state_body` and not carried into the new reader.
- **Finding:** `grep -nxF` counts a heading inside a fenced code block as
  real. Both directions demonstrated in a scratch repo against the staged
  scripts:
  - **False pass.** A `todo/` plan containing only a fenced `markdown` block
    listing the six headings, and no sections of its own, prints
    `plan-lint: OK`. `plan_state_problem` on the same file prints
    `no '## State' heading found.` Two readers in the same library, opposite
    answers, and the fence-aware one is the one `plan-freeze` gates on.
  - **False failure.** A correctly ordered plan that quotes
    ```` ```markdown / ## Progress / ## Findings (F) / ``` ```` inside its
    `## State` gets two reports: "section '## Progress' appears before
    '## Original plan'" and "section '## Findings (F)' appears before
    '## Gotchas (G)'". The order check records the fenced line number as the
    section's position.
  No file in the current 102-file corpus trips either (checked: no plan has a
  duplicate exact-line section heading), so this is latent — but the `#D4`
  work is the exact context that produces such a file.
- **Fix risk:** the fix is to feed the heading scan through the same
  fence-tracking `awk` `plan_state_body` already implements rather than
  `grep -nxF`, which costs the one-pass performance argument in `## State`
  (one `awk` replaces one `grep`, so probably little). Any change here must
  be re-measured against the 102-file corpus for verdict changes, not just
  for speed.


**FIXED 2026-09-07:** section headings come from a new fence-aware plan_headings, built on plan_state_body's fence handling. Both directions verified and both guarded in gate-tests: a file whose sections exist only inside a fence is refused, and a correct file that quotes a late heading inside State is no longer blocked. The second case needed reshaping after the first version passed under the fence-blind mutation -- quoting the template in canonical order keeps the sequence monotonic and does not reproduce the block

### F14 — `blocked_by`/`superseded_by` are validated by nothing whenever the value is not already in canonical citation form

- **File:** `docs/skills/plan/scripts/plan-lint:88-95`;
  `docs/skills/plan/scripts/plan-citations` (the scan regex)
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** an agent hand-setting the field — `reference.md` says
  both ref fields have no writer and are set by hand, so every value in the
  repo is typed by a human or an agent with no generator to constrain it.
- **Rule:** n/a
- **Finding:** `#G7` justifies dropping the existence check with
  "`plan-citations` already resolves these values". It does, but only for
  values its regex recognises:
  `[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9][a-z0-9-]*\.md`. Verified by
  constructing four `todo/` plans in a scratch repo and running both tools:
  a canonical-but-missing filename was correctly reported by
  `plan-citations`; a value with an uppercase letter and an underscore, a
  value of `TBD, ask the user`, and a value of `child-2` were reported by
  neither tool. `plan-lint`'s remaining check only rejects `/` and `..`, so
  all three pass it. Nothing acts on the result today — `git grep` shows
  `plan_field_refs` has exactly one caller (`plan-lint` itself) and no
  script, hook or workflow reads either field — so the answer to "could
  anything act on an unresolvable value" is no. What is lost is the
  half-landing detection `lib.sh` argues for elsewhere: a mistyped
  `blocked_by` silently drops a dependency edge from the graph
  `reference.md` says the field exists to make readable.
- **Fix risk:** the cheapest close is a shape check in `plan-lint` — the
  value must match the plan-filename form — which is local and needs no
  cross-file resolution. Doing it in `plan-citations` instead is what `#G7`
  already measured as failing 60 existing path-form references (that count
  was wrong; see `#D3` -- the real figure is 11).


**FIXED 2026-09-07:** plan-lint checks each reference against the canonical date-slug filename shape, so a value neither it nor plan-citations could resolve is reported rather than sitting there looking checked

### F15 — the "which vocabulary governs which field" comment sits on the wrong declaration, and the behaviour it claims does not exist

- **File:** `docs/skills/plan/scripts/lib.sh:37-46`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** the next person adding a schema field, who reads the
  comment as licence to add to `PLAN_VOCAB_FIELDS` without touching
  `PLAN_FIELD_VOCAB`.
- **Rule:** n/a
- **Finding:** two defects in nine lines, and the first is the same shape as
  `#F6` in this file, three lines below where `#F6` fixed it. (1) The comment
  "which vocabulary governs which field ..." is immediately followed by a
  second comment block ("What plan-new stamps on a new file") and then by
  `PLAN_DEFAULT_KIND`; the declaration it describes, `PLAN_FIELD_VOCAB`, is
  seven lines further down. Same misattachment `#F6` found on
  `PLAN_SCHEMA_FIELDS`. (2) Its claim — "a schema field with no entry here is
  checked for presence and never for value, as silently as the
  stamper/checker half-landing" — is false. Verified: with `severity` added
  to `PLAN_VOCAB_FIELDS` and no `PLAN_FIELD_VOCAB` entry, `plan-lint` aborts
  at line 75 with `PLAN_FIELD_VOCAB[$key]: unbound variable` under `set -u`.
  It fails closed (exit 1, which `verify-ladder` reads as a malformed plan),
  but the message names no plan file and the described silent degradation
  cannot occur — the only schema field that *can* have no vocabulary entry is
  a `PLAN_REF_FIELDS` member, which is never looked up in the map.
  Separately, `PLAN_KINDS`/`PLAN_PRIORITIES` are now reached only through
  `declare -n` on a string held in `PLAN_FIELD_VOCAB`, so `shellcheck -x`
  reports both as `SC2034` unused; a future cleanup acting on that warning
  breaks `plan-lint` at runtime, not at lint time.
- **Fix risk:** none material — moving a comment and giving the lookup a
  `${PLAN_FIELD_VOCAB[$key]:-}` default with an explicit report. Adding a
  `# shellcheck disable=SC2034` to the two arrays would also record why they
  look unused.


**FIXED 2026-09-07:** the vocabulary comment sits on its own declaration again, and plan-lint reports a PLAN_VOCAB_FIELDS entry missing from PLAN_FIELD_VOCAB instead of dying on an unbound variable. Verified by adding a severity field with no map entry

### F16 — `scripts/gate-tests` covers neither `plan-lint` nor `verify-ladder`'s new BLOCKED branch, on a change whose own `#F10` was a gate that silently did nothing

- **File:** `scripts/gate-tests` (82 cases, none naming `plan-lint`,
  `verify-ladder`, `plan_active_plan` or the active-plan marker);
  `docs/skills/workflow/scripts/verify-ladder:70-78`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** the next edit to `plan-lint` or to that branch. The
  harness's own header says it exists because "the review that produced this
  found the same defect shape twelve times: a gate that reports the wrong
  answer rather than one that is missing" — which is `#F10` exactly.
- **Rule:** n/a
- **Finding:** `git grep` for `plan-lint|verify-ladder|plan_active_plan|
  active-plan` in `scripts/gate-tests` returns nothing. `./scripts/gate-tests`
  passes 82/82 with 3 recorded residues both before and after this change, so
  the harness would have reported clean on the pre-`#F10` `verify-ladder` too,
  and would report clean on all three bypasses in `#F11`. The new `elif [ -s
  "$PLAN_ACTIVE_MARKER_RELPATH" ]` branch is correct as written — I read it
  and the `cd "$root"` on line 20 makes the relative marker path safe, an
  empty marker still means "no active plan", a marker naming a path outside
  `docs/plans/` now blocks rather than skipping, and the error message echoes
  the marker's own bytes rather than reading the named file — but it is
  asserted by nothing, which is the same standing the skipped lint had.
- **Fix risk:** gate-tests cases build scratch repos with no
  `docs/plans/.checksums`; a `plan-lint` case must therefore not depend on the
  manifest, which interacts with `#F11`'s proposed fix. Add the
  `verify-ladder` marker cases first — they need only a marker file and a
  missing target.

**Checked and clean (security, 2026-09-07).** Hardening axis is empty and
says so plainly: the staged set is 58 files, all under `docs/plans/` and
`docs/skills/`, with zero `.nix`, `hosts/`, `modules/`, `secrets/`,
`.sops.yaml` or firewall content (`git diff --cached --name-only` grep
returns 0). No host, service, unit, capability, port or secret is touched, so
there is nothing to weigh against `docs/hardening.md`. No secret was decrypted
or read at any point in this pass. The whole review is therefore on gate
correctness.

Verified positively, not merely read:

- **The migration preserves content.** For all 51 modified plan files, a
  sorted-line diff against `origin/master` yields exactly 4 added lines and 0
  removed — the four new frontmatter keys — with one intended exception, the
  map plan, whose extra delta is the `#F9` "three fields → four fields"
  rewrite and nothing else. (The `--numstat` phrasing in `#F2` is loose: the
  `## State` move shows as e.g. `134/130`, net +4, not a literal `4/0`. The
  content claim it was making holds.)
- **No frozen file was touched and the manifest still verifies.**
  `sha256sum -c docs/plans/.checksums` passes on all 50 entries; no staged
  path appears in the manifest; `.checksums` itself is not staged, so
  `.githooks/pre-commit`'s frozen guard is unaffected by this commit.
- **The corpus counts in `## State` reproduce.** 18 of 102 fail now; with the
  `frozen` guard forced off, 67 fail. The suppressed set is exactly 200
  missing-schema-field, 44 missing-`## State` and 23 section-order reports;
  all 27 of the frozen missing-`## State` files genuinely contain zero
  `## State` headings in any form, so they are unfixable under the freeze
  contract, not real problems hidden. Of the 18 remaining, 17 are non-frozen
  and 1 is frozen with a non-sequential `G` id — matching `#G5` exactly. Of
  the 17, 16 already failed under `origin/master`'s linter; the one newly
  reported is the substring fail-open `## State` names, so the "not purely a
  suppression" claim checks out.
- **Nothing acts on an unresolvable ref field.** `git grep` confirms
  `plan_field_refs` has one caller (`plan-lint`) and no script, hook or
  workflow reads `blocked_by`/`superseded_by`. `plan-citations` does resolve
  canonical-form values from plan frontmatter, disproving the retracted
  "cannot see frontmatter" claim independently — the coverage gap for
  non-canonical values is `#F14`.
- **`declare -n` cannot be steered by file content.** The name is
  `PLAN_FIELD_VOCAB[$key]` with `$key` drawn from the static
  `PLAN_VOCAB_FIELDS`, never from the file. Frontmatter keys additionally pass
  `^[A-Za-z_][A-Za-z0-9_]*$` in `plan_frontmatter`, so a crafted key cannot
  inject a bash associative-array subscript either.
- **The `key<TAB>value` protocol survives the obvious inputs.** Tested against
  the staged scripts in a scratch repo: a tab as the `key:`/value separator, a
  colon inside a value (`priority: normal: high` → correctly reported as not
  in the vocabulary), leading/trailing whitespace, an empty value, a
  `---` not on line 1, no frontmatter at all, and CRLF line endings — the last
  four all fail loudly with missing-core-field reports rather than passing.
  The two inputs that do desync are `#F11`/`#F12`. The current corpus is clean:
  all 102 files yield exactly the 8 expected keys, with no duplicates, no
  inline `#` comments and no unterminated block.
- **`plan-new`'s output lints clean** and its headings genuinely come from
  `PLAN_SECTIONS`; the `#F8` placeholder now sits directly under
  `## Findings (F)`. One residual coupling: the placeholder keys off
  `${PLAN_SECTIONS[-1]}`, i.e. "the last section", not "the Findings section",
  so appending a seventh section to the array would move the note. Not filed
  as a finding — it is a knowing trade recorded in `#F7` — but it is not the
  drift-proof coupling the comment implies.
- **`scripts/gate-tests` passes 82/82 with 3 recorded residues** against the
  staged tree, so nothing this change touched broke an existing gate test.
  What it does not cover is `#F16`.
- **Blast radius is bounded.** `plan-lint` is invoked by exactly one automated
  caller, `verify-ladder`, which is local-only; `.github/workflows/` contains
  only `plan-gate.yml`, which does not lint, and no git hook calls it. That is
  why every finding above is LOW or INFO rather than higher.

_security finished 2026-09-07T23:04:43Z (code 38b247d66b10a659) -- see Findings above._


**FIXED 2026-09-07:** gate-tests covers both. plan-lint gets four cases plus a sabotage sweep, each observed failing under the mutation that reintroduces its defect. verify-ladder cannot run inside a sub-second hermetic harness because it shells out to nix, so the decision it makes moved into plan_active_plan_problem, which distinguishes no marker from a marker naming a deleted file, and the three marker states are asserted there. 90 assertions, 0 failed

### F17 — `plan_field_refs` drops the last entry of every reference list

- **File:** `docs/skills/plan/scripts/lib.sh` (`plan_field_refs`)
- **Severity:** LOW
- **Confidence:** CONFIRMED by reproduction
- **Axis:** needed-used
- **Reachability:** any `blocked_by` with more than one entry, and any
  single-entry `blocked_by` at all — the sole entry is also the last one.
  No adversary; the principal is whoever first populates the field, which
  is the entire point of `#D4` adding it.
- **Rule:** n/a — the Class 1 shape from
  2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md,
  in code written this session to check references.
- **Finding:** the helper ended `printf '%s' "$raw" | tr ',' '\n' | sed ...`.
  `printf '%s'` writes no trailing newline, so the final field arrives at
  `while IFS= read -r ref` unterminated; `read` returns non-zero at EOF and
  the loop body never executes for it. Every reference list was therefore
  checked except its last element. Found while testing `#F14`'s new shape
  check: a `blocked_by` of four deliberately invalid values reported three
  problems, and the one omitted was the fourth. Not caught by any of the four
  `/simplify` angles, `docs-updater`, or `security`, all of which read this
  helper; it took running it with more than one value, which nothing in the
  corpus does yet because every `blocked_by` is empty.
- **Fix risk:** none. `printf '%s\n'` terminates the last field. The
  regression guard is the interesting part and is now in `gate-tests`,
  asserted as "every entry in a ref list is checked, including the last"
  rather than as this one case.

**FIXED 2026-09-07:** plan_field_refs terminates its last field, so a ref list's final entry is no longer silently skipped. Verified by the reproduction that found it -- four invalid refs now report four problems where they reported three -- and guarded in gate-tests by a case whose only bad reference is the last one

### F18 — the gate-tests case guarding `#F11` asserts the warning, not the enforcement, so the bypass it names still passes 90/90

- **File:** `scripts/gate-tests:397-402`; `docs/skills/plan/scripts/plan-lint:57-71`
- **Severity:** LOW
- **Confidence:** CONFIRMED by mutation
- **Axis:** needed-used
- **Reachability:** the next edit to `plan-lint`'s frozen decision. `plan-lint`
  has exactly one automated caller, `verify-ladder`, which is local-only
  (`.github/workflows/` holds only `plan-gate.yml`, which does not lint; no
  git hook calls it), so the reach is "the regression guard on the structural
  gate does not guard the thing the gate was fixed to do".
- **Rule:** n/a — new-rule candidate, and a re-occurrence of the shape this
  file's own `#F13` note records ("the first version of one of these cases
  passed under the very mutation it was meant to catch"), in a sibling case
  added in the same commit.
- **Finding:** `#F11`'s harm was not the missing warning. It was that a
  `todo/` plan asserting `frozen: true` "switches off every rule below" — a
  file with no `## State`, none of the six sections and none of the four new
  fields printed `OK`. The new case `expect_fail "plan-lint refuses a plan
  that declares itself frozen" "only plan-freeze may freeze"` asserts exit
  non-zero plus that one diagnostic string, and nothing about the era rules.
  Mutation run in a scratch copy of this branch: leave the manifest lookup
  and both disagreement reports exactly as written, and add one line after
  them — `[ "$frozen_field" = "true" ] && frozen=1` — which restores `#F11`'s
  bypass in full. `./scripts/gate-tests` reports **90 passed, 0 failed, 3
  recorded residues**, and the case named after `#F11` is one of the 90. The
  probe would report ten problems under the honest linter (verified: the
  disagreement plus five missing sections and four missing schema fields), so
  the assertion had nine other reports available to key on and keyed on the
  one the mutation preserves. Four other mutations were run for contrast and
  are all caught: fence-blind `plan_headings` (2 failures), `printf '%s'` in
  `plan_field_refs` (1), field-based `frozen` (1), deleting the `#F14` shape
  regex (1), and both directions of `plan_active_plan_problem` (1 and 2).
- **Fix risk:** none material. `expect_fail` matches a single fragment, so
  covering the enforcement needs a second assertion over the same probe (or a
  fragment such as `missing required section '## State'` instead of the
  warning). Whichever is chosen, re-run the bypass mutation above and require
  the case to fail — asserting only the warning is what this finding is.


**FIXED 2026-09-07:** the case is split in two, because enforcement and warning fail independently: one requires 'missing required section', which only appears if the schema rules actually ran, and the other requires the self-freeze warning. Verified with security's own mutation -- restoring the bypass in full now fails the enforcement case where the single warning-keyed case stayed green

### F19 — `SKILL.md` and `reference.md` still say the era rules gate on `frozen: false`, which is the definition `#F11` removed

- **File:** `docs/skills/plan/SKILL.md:31`; `docs/skills/plan/reference.md:50`;
  this plan's `#G5`; contrast `docs/skills/plan/scripts/plan-lint:58`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** the next person adding a schema-era rule, or anyone
  debugging why a plan is or is not exempt. Both documents are the ones
  `plan-lint`'s own row points at ("see `reference.md`, 'Which files the
  schema rules apply to'"), so the pointer lands on the wrong authority.
- **Rule:** n/a — `docs/hardening.md` covers no repo tooling. Rubric class:
  documentation that no longer matches the code.
- **Finding:** `SKILL.md:31` says the schema-era rules "run only where
  `frozen: false`" and `reference.md:50` says "`plan-lint` therefore checks
  the section set, the section order and the schema fields only where
  `frozen: false`". After `#F11` neither is true: `plan-lint:58` branches on
  `plan_manifest_frozen`, i.e. on a `docs/plans/.checksums` entry, and the
  `frozen:` field now only feeds a disagreement report. The two disagree in
  both directions and both directions are demonstrable — a `todo/` plan with
  `frozen: true` gets every era rule (that is `#F11`'s fix), and a `done/`
  file with `frozen: true` but no manifest entry does too. `#G5` in this file
  carries the same stale sentence, and cites `reference.md` as where the
  decision is "stated". So the change closed one two-definitions-of-frozen
  problem in code and left a second one between the code and its own
  documentation. Verified there is no third statement: `grep -rn 'frozen:
  false' docs/skills docs/agents AGENTS.md` returns only these two plus two
  literal frontmatter examples, and no doc mentions `plan_manifest_frozen`
  or the two new reports at all.
- **Fix risk:** none — it is prose. The wording has to name the manifest as
  the authority and say the field is now only cross-checked against it,
  otherwise the next schema rule gets written against the field again.


**FIXED 2026-09-07:** SKILL.md, reference.md and this plan's G5 now say the era rules gate on the checksum manifest, naming why -- only plan-freeze writes it and pre-commit enforces it -- rather than on the self-declared field

### F20 — `plan_manifest_frozen` matches the manifest by unanchored substring, on a `$rel` `plan_locate` never canonicalises

- **File:** `docs/skills/plan/scripts/lib.sh:189-193`;
  `docs/skills/plan/scripts/plan-lint:17,58`; same idiom at
  `docs/skills/plan/scripts/lib.sh:435` (`plan_do_freeze`)
- **Severity:** INFO
- **Confidence:** CONFIRMED by reproduction
- **Axis:** needed-used
- **Reachability:** a contributor or agent invoking `plan-lint` (or writing
  the active-plan marker via `plan-decide`/`plan-resolve`) with a legal but
  non-canonical path. No adversary is needed for the second half — a typo is
  enough — and no privilege is gained either way; the consequence is a wrong
  verdict from the gate, printed as an accusation.
- **Rule:** n/a — new-rule candidate: a lookup keyed on a path must anchor
  the key and canonicalise the input, or it is a substring search.
- **Finding:** two defects in one line, `grep -qF "  $2" "$manifest"`.
  1. **Unanchored.** The match succeeds anywhere in the line, so a `$rel`
     that is a strict *prefix* of a manifest entry reports frozen.
     Reproduced in a scratch tree: with the manifest holding one entry whose
     path is `<some-plan>.md.bak.md`, `plan_manifest_frozen` returns true for
     `<some-plan>.md`, which has no entry of its own. `-F` does close the
     metacharacter half — a `$rel` built from regex and glob metacharacters
     matched no entry — and no prefix pair exists among the 50 real entries
     (checked), so this is latent, not live. It is the same unanchored idiom
     `plan_do_freeze` uses to *delete* a line, where the direction is worse:
     freezing the shorter path would silently drop the longer path's
     manifest entry.
  2. **Non-canonical `$rel`.** `plan_locate`'s first arm returns its argument
     verbatim whenever it matches `docs/plans/*/*.md`, and a `case` `*`
     matches `/`, so `docs/plans/./done/<file>.md` is returned unchanged.
     Run against a real frozen plan on this branch, `plan-lint` then prints
     `frontmatter says 'frozen: true' but docs/plans/.checksums has no entry
     -- only plan-freeze may freeze a plan` plus five schema-era problems the
     file can never fix — a correctly frozen plan accused of self-freezing.
     The canonical path and the absolute path both report `OK`. This
     sensitivity is new: before this change `$rel` was only used for `-f`,
     `basename`/`dirname` and display, and nothing keyed a lookup on it.
- **Fix risk:** anchoring (`grep -qxF`-style on the whole line, or
  `awk -v p="$2" '$2 == p'`) changes no verdict on the current corpus — all
  50 entries are `<hash>  <canonical rel>` and `sha256sum -c` passes — but
  it must tolerate the two-space separator `sha256sum` writes and must not
  start reading the hash. Canonicalising in `plan_locate` is the wider change
  and touches every caller, including `plan_do_freeze`'s manifest writer, so
  the two are separable.


**FIXED 2026-09-07:** plan_manifest_frozen matches the manifest's path field exactly instead of any substring of the line, and normalises leading and embedded ./ segments first. Verified: docs/plans/./done/<frozen>.md now lints OK where it previously reported a self-freeze plus five unfixable era failures, a suffix of a recorded path no longer matches, and the exact path still does

### F21 — `#F12`'s first-wins fix has no regression guard: reverting it passes 90/90

- **File:** `docs/skills/plan/scripts/lib.sh:134-139`; `scripts/gate-tests`
  (no case names `plan_frontmatter`, a duplicate key, or first-wins)
- **Severity:** INFO
- **Confidence:** CONFIRMED by mutation
- **Axis:** needed-used
- **Reachability:** the next edit to `plan_frontmatter`. Same principal and
  same local-only blast radius as `#F18`.
- **Finding:** deleting the two lines that make the reader first-wins
  (`if (k in seen) next; seen[k] = 1`) leaves `./scripts/gate-tests` at 90
  passed, 0 failed. `#F12` was specifically a *two readers disagree* defect,
  the class this file records as recurring, and it is the one fix in the
  F11-F17 batch that came back with no assertion. The consequence of a
  silent revert is smaller than it was — `plan-lint` no longer takes the
  frozen exemption from the field, so last-wins would flip only the
  disagreement report and the `kind`/`priority`/`status` values, and in the
  `frozen` case it flips *stricter* — but it would also silently reopen the
  gap between `plan-lint` and `plan_get_field` that `#F12` closed, on the
  same key `plan-move` rewrites. Confirmed separately that the fix does work
  today: a `todo/` plan with an unterminated frontmatter block and a body
  line reading `frozen: true` lints `OK` rather than tripping the
  self-freeze report, precisely because the earlier `frozen: false` wins.
- **Fix risk:** a case is cheap and hermetic (two `frozen:` lines in a probe,
  assert `plan_frontmatter` prints the first) — but `#G8` records the harness
  at 0.98s against a one-second budget with no margin, so this lands after
  the fast/slow split, not before it.


**FIXED 2026-09-07:** gate-tests asserts the two frontmatter readers agree on a duplicated key. The first version of the probe read plan_frontmatter's first value and so agreed with plan_get_field even with first-wins deleted -- it now reads the last, which is how plan-lint's consumer loop reads it, and it fails under that mutation

### F22 — the sabotage sweep's "citations resolve" comment now sits above the plan-lint sweep it does not describe

- **File:** `scripts/gate-tests:731-739`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** the next person editing a sweep's success fragment, who
  reads the comment as being about the line under it.
- **Rule:** n/a. Third occurrence of the misattached-comment shape already
  filed twice in this file, as `#F6` and `#F15`.
- **Finding:** the comment block explaining why the fragment must be
  `"citations resolve"` and not `"plan-citations: OK"` — with its
  `2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#F15`
  citation — was already at `gate-tests:731-735`. The new
  `sabotage_sweep "plan-lint over a well-formed plan"` was inserted between
  it and the `plan-citations` sweep at line 739, so the comment now describes
  the line two below it. The reasoning it carries does not apply to
  `"lint-clean.md: OK"`, which is not a prefix of anything else `plan-lint`
  prints.
- **Fix risk:** none — move the new sweep above the comment, or the comment
  down onto its own sweep.

**Checked and clean (security, second pass, 2026-09-07).** Hardening axis is
empty again and plainly so: `git diff origin/master..HEAD --stat` is 59 files,
all under `docs/plans/`, `docs/skills/` and `scripts/`, with zero `.nix`,
`hosts/`, `modules/`, `secrets/`, `.sops.yaml`, firewall, systemd-unit or
capability content. No host, service, port or secret is touched, so there is
nothing to weigh against `docs/hardening.md`, and no `nix eval` against the
pinned nixpkgs was applicable. No secret was decrypted or read at any point.
The whole pass is on gate correctness.

Verified positively, not merely read, on commit `0ca8889`:

- **The corpus claims still hold after the F11-F17 fixes.** 18 of 102 plans
  fail `plan-lint`; exactly 1 of the 18 is manifest-frozen
  (`2026-08-28-homelab-zdata-pool-usb-uas-checksum-errors.md`, a
  non-sequential `G` id, era-independent as `#G5` says). The aggregate over
  the whole corpus is 17 missing-`## State`, 3 Progress-cites-a-missing-`G`
  and 11 non-sequential-`G` reports — **no file trips either new
  frozen-disagreement report**, so the both-directions check fires on nothing
  legitimate today.
- **No frozen plan was touched and the manifest verifies.** `sha256sum -c
  docs/plans/.checksums` passes on all 50 entries; `comm` of the 50 manifest
  paths against the 59 paths the commit changes is empty.
- **`plan_headings` and `plan_state_body` cannot disagree.** Differential
  fuzz of 4000 generated files over 17 fence and heading shapes (plain,
  tilde, four-backtick, two- and four-space indented, tab-indented,
  blockquote- and list-prefixed, info-string, an inline `` ``` `` `` ``` ``
  line, and `## State` with a trailing space): zero disagreements between
  "`plan_headings` emits `## State`" and "`plan_state_body` succeeds". Same
  comparison over all 102 real plans: zero. The fence state machines are
  byte-identical; the only asymmetry is `/^## /` versus `/^## State$/`, and
  every heading that splits them (`## State ` with a trailing space,
  `##State`, `## State foo`, a CR-terminated heading) makes *both* readers
  report the section missing.
- **Both fence directions are genuinely guarded.** Replacing `plan_headings`
  with the fence-blind `awk '/^## / { print FNR "\t" $0 }'` fails exactly the
  two new fence cases, including the reshaped false-failure one — so `#F13`'s
  note about the first version passing under its own mutation is closed for
  that case.
- **`#F17` and `#F14` are guarded.** Reverting `printf '%s\n'` to
  `printf '%s'` in `plan_field_refs`, and separately deleting the canonical
  filename regex, each fail the reference-list case. Edge inputs behave: a
  lone `,`, an all-whitespace value and an empty value all yield no
  references and exit 0; a value can never contain a newline because
  `plan_get_field` prints one line.
- **The `#F14` regex rejects nothing legitimate.** All 102 corpus filenames
  match `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9][a-z0-9-]*\.md$`. It also cannot
  be bypassed: the preceding `case */*|*..*` arm is strictly redundant with
  it (neither `/` nor a second `.` can match the character classes), so it
  only improves the message.
- **`plan_active_plan_problem` fails in the safe direction on every marker
  shape tried.** No marker and an empty marker are silent; a whitespace-only
  marker, a two-line marker, a marker naming a path outside `docs/plans/`, a
  marker that is a directory, and an unreadable marker all report a problem.
  `head -n 1` never fails open — worst case it prints an empty name after a
  `head:` error on stderr. Two cosmetic residues, not filed: a two-line
  marker's message names only the first line, so it can call a path "not a
  usable plan file" when that path exists and the second line is the fault;
  and the message echoes the marker's raw bytes, so control characters reach
  the terminal (writer is `plan_mark_touched`, so this needs worktree write
  access already).
- **`plan_frontmatter`'s `seen` array cannot be poisoned.** The key is
  everything before the first `:`, and `seen[k]` is set before the
  `^[A-Za-z_][A-Za-z0-9_]*$` shape test — but a key that fails that test can
  never be byte-equal to one that passes, so no malformed line can shadow a
  real key. Checked against `plan_get_field` on `frozen:true` (no space),
  `frozen : true`, `  frozen: true`, `a: frozen: true`, a `---` not on line
  1, and no frontmatter at all: same answer both ways. One divergence
  survives and is harmless today — `plan_frontmatter` strips trailing
  whitespace from a value and `plan_get_field` does not, so `frozen: true `
  reads as `true` in `plan-lint` and as not-frozen in `plan_is_frozen`; on a
  non-frozen file `plan-lint` reports it anyway, and on a frozen file the
  edit needed to introduce it is what `.githooks/pre-commit`'s checksum guard
  blocks.
- **`declare -A` subscripts cannot be steered by file content.** A plan whose
  headings are `## @` and `## *` lints `OK` with no bash diagnostic;
  `sec_line` and `fm_val`/`fm_seen` are all `declare -A`, so no arithmetic
  evaluation happens on a subscript taken from the file.
- **The freeze path has no legitimate mid-freeze window.** `plan-move ...
  done` `exec`s `plan-freeze`, and `plan_do_freeze` sets `frozen: true`, the
  manifest entry and the `git add` in one function with no intervening
  `plan-lint`; `plan-reject` uses the same helper. So the only way to reach
  either disagreement report is a hand edit or a partial merge — which is
  what the report is for.
- **`gate-tests` is hermetic and still under budget** at 90 passed, 0 failed,
  3 recorded residues in 0.96s. The four new `plan-lint` cases, the three
  marker cases and the new `plan-lint` sabotage sweep all run in the scratch
  repo; the sweep's baseline correctly requires `lint-clean.md: OK` and at
  least one shimmed `git` call, and `plan-lint` makes exactly one
  (`plan_repo_root`), which the sweep sabotages.
- **Blast radius is unchanged and small.** `plan-lint` still has exactly one
  automated caller, `verify-ladder`, which is local-only; `.github/workflows/`
  holds only `plan-gate.yml`, which does not lint, and no `.githooks/*` calls
  it. That is why every finding above is LOW or INFO.
- **One residue recorded, not filed:** a plan file whose frontmatter has no
  closing `---` still lints `OK` — `plan_frontmatter` and `plan_get_field`
  both scan to EOF. `#F11`'s fix-risk note offered "require a terminating
  `---`" as part of the cheaper alternative fix; the manifest fix was taken
  instead and this half was not. It is no longer a *bypass* (`#F12`'s
  first-wins makes the real `frozen: false` win over any body line), and it
  is pre-existing on `origin/master`, so it is a gap in the structural
  validator rather than a defect this change introduced.

_security finished 2026-09-07T23:27:30Z (code 832e3b086c764756) -- see Findings above._

**FIXED 2026-09-07:** the citations-fragment comment moved back onto the plan-citations sweep it explains

### F23 — the frozen exemption for path-form citations stopped resolving them at all

- **File:** `docs/skills/plan/scripts/plan-citations` (the `PATHFORM` arm)
- **Severity:** LOW
- **Confidence:** CONFIRMED by reading both branches against the loop they
  sit in, and by the record count.
- **Axis:** needed-used
- **Reachability:** no adversary. Every citation written in path form,
  which after `#D3` is the frozen half of the corpus only.
- **Rule:** n/a — a coverage regression introduced by this branch.
- **Finding:** the `PATHFORM` arm ended both of its paths with `continue`,
  which leaves the `while` loop before the resolution code below it. So a
  path-form citation was no longer checked for whether the plan it names
  exists, or whether its anchor exists. For a non-frozen file that is
  merely redundant with the report it does emit; for a frozen file, where
  the arm exits silently, the citation stopped being verified at all.
  That is the wrong half of the corpus to stop watching: `#G2` records
  that 24 of the 47 live `#G` citations resolve *into* frozen plans, which
  is exactly where a stale reference accumulates with no way to repair it.
  Nothing is broken today — the one affected record resolves — but the
  check that would have said so was removed.
- **Fix risk:** none. Dropping the `continue` falls through to the
  resolution the arm was skipping, and the frozen case counts rather than
  reports, which is the treatment `#F6` on the map plan already prescribed
  for a silently muted region in this same file: a mute with no diagnostic
  is easier to create than the noisy form the checker already catches.

**FIXED 2026-09-08:** the PATHFORM arm falls through to resolution instead of returning early, so a path-form citation is still checked for existence and anchor; the frozen case increments a counter that plan-citations prints on its OK line rather than exiting silently

### F24 — the manifest write had two homes, and the weaker path match was in both

- **File:** `docs/skills/plan/scripts/lib.sh` (`plan_do_freeze`),
  `docs/skills/plan/scripts/plan-repair`
- **Severity:** LOW
- **Confidence:** CONFIRMED by reading both against each other.
- **Axis:** needed-used
- **Reachability:** no adversary; whoever next corrects the manifest
  writer. There is an open plan to do exactly that
  (2026-09-06-make-the-frozen-plan-guard-survive-renames-and-stop-self-certifying.md).
- **Rule:** n/a.
- **Finding:** `plan-repair` reproduced `plan_do_freeze`'s nine-line
  manifest rewrite — checksum, `mktemp`, delete the old entry, append,
  `sort -k2`, `git add`. Both deleted the old entry with
  `grep -vF "  $rel"`, an unanchored substring match on a line, which is
  the same weaker-than-necessary comparison `#F20` had just replaced with
  an exact path test inside `plan_manifest_frozen`. So the fix for one
  would have had to be made twice, in two files, by someone who had no
  reason to look in the second. The two copies had already drifted:
  `plan_do_freeze` created the manifest if absent, `plan-repair` did not.
- **Fix risk:** low. `plan_record_checksum` is now the single writer and
  compares the path field exactly; `plan_do_freeze` and `plan-repair` both
  call it. `plan-repair` deliberately does *not* call `plan_do_freeze`
  itself, because that also runs `plan_mark_touched`, which would repoint
  `.claude/.active-plan` at a frozen `done/` plan — the marker class
  `#F10` is about. Separately, `plan-lint`'s `*/*|*..*` case arm was dead:
  every string it matched was already rejected by the filename regex below
  it, so it only ever changed the wording. Folded into one rule with one
  message. Manifest re-verified after the change: all 50 entries pass.

**FIXED 2026-09-08:** plan_record_checksum is the single manifest writer, matches the path field exactly, and is called by both plan_do_freeze and plan-repair; plan-lint's dead case arm folded into the regex it duplicated. All 50 frozen checksums still verify

### F25 — every number `## State` and `#G8` quote for the harness is one or more sessions old

- **File:** this plan's `## State` (the `gate-tests` paragraph, the
  migration bullet, the rung declaration, the pick-up point) and `#G8`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** re-measured on this worktree, five runs. The harness is
  **96 passed, 0 failed, 3 recorded residues** in **0.97s** (975-979 ms,
  spread 5 ms). `## State` said 92 assertions and "about 1.0s", its rung
  declaration said 90/0/3, its pick-up point said 92/0/3, and `#G8` said
  the harness "went 82 assertions to **97**" — four different counts for
  one number, none of them current, and 97 was never what the summary
  line printed. The migration bullet was stale in two further ways after
  `#D5` and `#D4`: it said "four keys added ... each netting exactly +4
  lines" when the shipped schema adds three (+3 against `origin/master`,
  verified by `--numstat`), and "the 50 frozen ones are untouched by
  construction" when 27 of them have since been repaired.
- **Fixed** in `## State`, which is the one section a later pass may
  rewrite: 96 assertions, 0.97s, 96/0/3, three keys, +3 lines, and a new
  bullet for the 27 repaired frozen plans (+8 lines each, 0 deletions,
  216 total, `sha256sum -c` green on all 50). `#G8`'s count is corrected
  in place with a strikethrough, per append-only. Cross-checked while
  there: `verify-ladder` end to end is **24.3s**, of which
  `nix flake check --no-build` is **22.9s** and `gate-tests` 0.97s — so
  `#G11`'s "4% of `verify-ladder`" holds and its 26.0s/23.5s are within
  run-to-run variance. The corpus sweep is still **18 of 102** failing.


**FIXED 2026-09-08:** re-measured on this worktree 2026-09-08: 96/0/3 in 0.97s over five runs, verify-ladder 24.3s of which nix flake check 22.9s. State's counts, key count and line deltas corrected; G8's 97 struck through to 96

### F26 — the freeze contract is stated as absolute in three places, and `plan-repair` is the exception it does not admit

- **File:** `docs/skills/plan/SKILL.md:36`, `docs/skills/plan/SKILL.md`'s
  `plan-lint` row, `docs/skills/plan/reference.md` ("Which files the
  schema rules apply to"), `docs/skills/plan/scripts/plan-lint:50-53`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** `SKILL.md` closed its script table with "All of them
  refuse to touch a frozen file" — the row directly above it is
  `plan-repair`, which refuses everything *except* a frozen file. The
  same file's `plan-lint` row and `reference.md`'s frozen-exemption
  paragraph both justify reading the manifest rather than the `frozen:`
  field with "only `plan-freeze` writes the manifest", and
  `plan-repair` now writes it too via `plan_record_checksum` (`#F24`) —
  in `reference.md` that claim sits two paragraphs above the new
  paragraph saying `plan-repair` re-records the checksum, so the file
  contradicted itself on one screen. `plan-lint`'s own comment carried
  the third copy.
- **Fixed:** all four now name both writers, and the closing line excepts
  `plan-repair` while restating its bound (it can only add an absent
  section). The justification is unaffected: what makes the manifest
  authoritative is that no *plan* writes it about itself.


**FIXED 2026-09-08:** SKILL.md, reference.md and plan-lint's comment now name plan-freeze and plan-repair as the manifest's writers, and the script table's closing line excepts plan-repair with its bound restated

### F27 — the two new lint gates are documented in `SKILL.md` and nowhere else

- **File:** `docs/skills/plan/reference.md` ("Freeze mechanics",
  "Rejecting a plan"), `docs/skills/plan/SKILL.md`'s `plan-reject` row
- **Axis:** docs accuracy (docs-updater)
- **Finding:** `reference.md`'s "Freeze mechanics" enumerates what
  `plan-freeze` refuses, in order, and is the long-form reference the
  `SKILL.md` table points at; it did not mention the `plan-lint` gate
  added under `#D4`. Its "Rejecting a plan" bullet list, whose whole
  point is which gates `plan-reject` waives, did not mention the gate it
  gained under `#G10` — so the only statement of the reject-side rule was
  a trailing clause on the *`plan-freeze`* row of the skill table, where
  a reader looking up `plan-reject` never arrives.
- **Fixed:** both lists now carry the lint refusal with its plan anchor,
  and the `plan-reject` row says it lints, with `rejected/` being as
  permanent as `done/` as the reason.


**FIXED 2026-09-08:** reference.md's Freeze mechanics and Rejecting-a-plan lists both carry the plan-lint refusal with its anchor, and plan-reject's SKILL.md row says it lints

### F28 — the bare-filename rule became blocking, and no doc that states the rule says so

- **File:** `docs/skills/plan/SKILL.md` ("The rule"),
  `docs/skills/plan/reference.md` ("Why bare-filename citations"),
  `docs/skills/workflow/SKILL.md` step 4,
  `docs/procedures/testing-changes.md`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** after `#D3`, `plan-citations` reports a path-form citation
  in every `*.md` and script it scans, and `verify-ladder` runs it on
  every pass — so writing `docs/plans/todo/x.md` in prose now blocks a
  commit. Every doc that states the rule still described it as a
  convention, and every doc that describes the gate still said
  `plan-citations` blocks only on a citation that no longer *resolves*.
  An agent hitting the new refusal had no doc to reconcile it against.
- **Fixed:** the rule statement in both skill docs now names the enforcer
  and the frozen-file exemption; `verify-ladder`'s description in
  `workflow/SKILL.md` and `testing-changes.md` names the second thing it
  blocks on.


**FIXED 2026-09-08:** plan/SKILL.md, plan/reference.md, workflow/SKILL.md and testing-changes.md all name plan-citations as the enforcer of the bare-filename rule and the frozen-file exemption

### F29 — `testing-changes.md`'s gate descriptions predate three sessions of harness growth

- **File:** `docs/procedures/testing-changes.md`, the `verify-ladder` and
  `gate-tests` bullets
- **Axis:** docs accuracy (docs-updater)
- **Finding:** the `gate-tests` bullet listed its coverage as
  "`plan-gate`, `required-agents`, `plan-citations`, and `lib.sh`'s
  fingerprint, file-listing and rung-declaration helpers". It also covers
  `plan-lint`, `plan-freeze`'s lint gate, `plan-repair`, both frontmatter
  readers and the active-plan marker — thirteen sections, five swept
  gates. The `verify-ladder` bullet described `plan-lint` as blocking on
  "a missing section, a duplicate or non-sequential id, or a Progress
  line citing a heading that does not exist", which predates the schema
  fields and the section-order rule, and said nothing about the dangling
  `.claude/.active-plan` marker now blocking (`#F10`) — the one new
  refusal a reader is most likely to meet without understanding it. Its
  "under a second" claim survives: 0.97s measured.
- **Fixed:** both bullets rewritten to what the scripts do now. Not
  changed: "Run from `verify-ladder` only — no git hook or CI step runs
  it yet", which is still true and is exactly what `#D2` is about.


**FIXED 2026-09-08:** gate-tests' coverage list and verify-ladder's plan-lint description rewritten to current behaviour, including the dangling active-plan marker block

### F30 — the map plan's `#D4` still specifies a four-field schema

- **File:**
  2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md,
  `### D4`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** `#D5` here dropped `superseded_by`, and the map plan's
  Progress item 2 was struck through and corrected to match. Its `### D4`
  — the decision text that item implements, and the anchor this plan and
  `reference.md` both cite as the authority for the schema — still reads
  "Frontmatter gains `priority`, `blocked_by`, `superseded_by`, and
  `kind`". A reader arriving at the anchor rather than at the checklist
  gets the pre-`#D5` schema.
- **Fixed:** a dated `**Corrected 2026-09-08:**` note appended to `D4`'s
  body, above its `ANSWERED` marker, naming three fields and pointing at
  `#D5`. Append-only respected — nothing was deleted.


**FIXED 2026-09-08:** dated correction appended to the map plan's D4 naming three fields and citing D5; the four-field text is left in place per append-only

### F31 — `plan-reject` moves and re-stamps the plan *before* it lints, so a refused rejection leaves the file half-rejected

- **File:** `docs/skills/plan/scripts/plan-reject:29-47`
- **Axis:** docs accuracy (docs-updater), reported not fixed
- **Finding:** the gate added under `#G10` sits after the `REJECTED`
  marker is appended, after `git mv` to `docs/plans/rejected/`, and after
  `plan_set_field ... status rejected`. When it fires, `plan_die` exits
  with the plan already in `rejected/`, already stamped `status:
  rejected`, and not frozen — a state no script put it in and none will
  clear, and the same disagreement class `#F11` and `#F20` are about.
  `plan-freeze` does not have this shape: it lints before
  `plan_do_freeze` and mutates nothing first. The docs say `plan-reject`
  "moves ... and freezes it"; on the refusal path it moves and does not
  freeze. `SKILL.md` and `reference.md` were updated to say it lints
  (`#F27`), which is true of both orderings, so no doc asserts the
  ordering either way.
- **Not fixed:** whether to lint before the move (cheap, since `plan-lint`
  reads `status` against the folder, so a pre-move lint judges the plan
  against `todo/`/`in-progress/` and would need the folder it is going to)
  or to roll back on refusal is a code decision with a real tradeoff, and
  picking one silently is what this pass is meant not to do.


**FIXED 2026-09-08:** the lint runs before the REJECTED marker, the git mv and the status field, so a refusal leaves the plan exactly where it was. Verified both ways in a scratch repo and guarded in gate-tests -- and the guard took three attempts: the first passed because the fixture had no rejected/ directory so git mv failed anyway, the second because the probe file was untracked so git mv failed anyway. Only the third, with the directory present and the file staged, goes red when the gate is moved back after the move

### F32 — extracting `plan_record_checksum` left `plan_do_freeze`'s docblock sitting on the new function

- **File:** `docs/skills/plan/scripts/lib.sh:436-441` before the fix
- **Axis:** docs accuracy (docs-updater)
- **Finding:** `#F24`'s extraction inserted `plan_record_checksum` and its
  comment *between* `plan_do_freeze`'s docblock and `plan_do_freeze`. The
  two blocks ran together with no blank line, so the file read as one
  five-line comment describing freezing followed by four lines describing
  the checksum writer, above a function that is only the second of those;
  `plan_do_freeze` itself was left undocumented two definitions further
  down. This is `#F6`'s shape exactly — the frozen-exemption comment that
  sat on the wrong declaration — reintroduced by the refactor that
  followed it, in the same file.
- **Fixed:** the `plan_do_freeze` docblock moved onto `plan_do_freeze`,
  and its body corrected while there: it now delegates the checksum write
  and also calls `plan_mark_touched`, which the old text did not mention
  and which is the reason `plan-repair` deliberately does not call it.

**FIXED 2026-09-08:** the plan_do_freeze docblock moved back onto plan_do_freeze and updated to name plan_mark_touched; plan_record_checksum keeps its own

### F33 — `plan-repair` is documented as adding "a required section"; it can only ever add `## State`

- **File:** `docs/skills/plan/SKILL.md` (`plan-repair` row),
  `docs/skills/plan/reference.md` ("The one exception, and its limits"),
  against `docs/skills/plan/scripts/plan-repair:27-30`
- **Axis:** docs accuracy (docs-updater)
- **Finding:** both docs describe the script as adding "a required
  section that is missing", which reads as a general repair tool taking a
  section. The script hardcodes `missing="## State"`, takes exactly one
  argument (the plan), and its own comment says widening the list means
  widening what a frozen file can become. The overstatement is the kind
  that gets acted on: a reader with a frozen plan missing `## Findings
  (F)` would reach for a capability that does not exist, and the natural
  next step — adding a section argument — is precisely the decision the
  script is written to force into the open.
- **Fixed:** both now name `## State` as the one repair, say the section
  is hardcoded rather than an argument, and keep the two refusals.

**FIXED 2026-09-08:** SKILL.md and reference.md now say plan-repair adds ## State specifically, hardcoded rather than an argument

_docs-updater finished 2026-09-08T19:05:54Z (code c4bab0aafd59760a) -- see Findings above._

### F34 — `plan-freeze`'s already-frozen guard reads the self-declared field, so a frozen plan can be edited and re-checksummed; only one untested `plan-lint` line stops it

- **File:** `docs/skills/plan/scripts/plan-freeze:20`
  (`plan_is_frozen "$root/$rel" && plan_die`), against
  `docs/skills/plan/scripts/lib.sh:192-207` (`plan_manifest_frozen`) and
  `docs/skills/plan/scripts/plan-lint:55-63`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (reproduced end to end in a throwaway clone)
- **Axis:** hardening
- **Reachability:** any principal that can write the checkout — a
  contributor, or a Claude Code session, since `plan/SKILL.md`'s
  `allowed-tools` pre-approves `Bash(${CLAUDE_SKILL_DIR}/scripts/plan-freeze *)`
  with no further prompt. Path: open a `docs/plans/done/*.md`, flip
  `frozen: true` to `frozen: false` in the frontmatter (an ordinary file
  edit), change any body text, run `plan-freeze <file>`. Line 20's guard
  is `plan_is_frozen`, which reads the *field* — the field the edit just
  cleared — so it does not fire, and `plan_do_freeze` rewrites the
  `docs/plans/.checksums` entry to the tampered content.
  `.githooks/pre-commit` then compares the tampered file against the
  rewritten entry and passes.
- **Rule:** n/a (this repo's own freeze contract, `docs/skills/plan/reference.md`,
  "The mutable corpus is migrated ...")
- **Finding:** `#F11` moved `plan-lint` from the field to the manifest
  because "the field is self-declared". `plan-freeze:20` was not moved
  with it and still asks the file about itself. What actually blocks the
  laundering today is a *side effect* of this branch's new lint gate:
  `plan-lint:57-58` reports "frontmatter says frozen 'false' but
  docs/plans/.checksums records this file as frozen", `plan-freeze:43`
  now refuses on any lint failure, and the freeze is declined. Verified:
  with the branch as it stands, the attempt above fails with that exact
  message and `pre-commit` still reports `BLOCKED`. But that is one
  `report` line carrying the whole contract, and nothing tests it —
  replacing `plan-lint:57-58` with `:` leaves `scripts/gate-tests` at
  **98 passed, 0 failed**, and the same laundering attempt then succeeds:
  `plan-freeze` exits 0, the manifest entry is rewritten to the tampered
  hash, and `.githooks/pre-commit` exits 0 with zero `BLOCKED` lines.
  These plan files are where the 2026-08-26 fleet audit's findings and
  every subsequent security review are recorded; the manifest is the only
  evidence they have not been rewritten after the fact.
- **Fix risk:** moving line 20 to `plan_manifest_frozen` changes
  `plan-freeze`'s behaviour for a plan whose manifest entry exists but
  whose field is false — today that is a refusal via lint, after the fix
  it is a refusal via the already-frozen guard, so the message changes
  and any test matching "is malformed" for that case would need
  rewording. `plan-move ... done` `exec`s `plan-freeze` on a file it has
  just created in `done/`, which has no manifest entry, so the happy path
  is unaffected. Needs a gate-tests case that asserts the *enforcement*
  (attempt the flip-edit-refreeze and require the manifest entry
  unchanged), not the warning — the same distinction `#F18` drew.


**FIXED 2026-09-08:** plan-freeze's already-frozen guard reads the checksum manifest instead of the file's self-declared frozen field, so flipping that field back and re-running cannot rewrite the recorded hash to a tampered one. Guarded in gate-tests by a probe that is the tamper itself -- recorded in the manifest with frozen: false and otherwise valid -- because a probe still saying frozen: true is refused by both guards and distinguishes nothing

### F35 — six mutations that each restore a defect this branch fixed still pass `scripts/gate-tests` 98/98

- **File:** `scripts/gate-tests:523-593` (the new `plan-repair` /
  `plan-freeze` / `plan-reject` section) and `:609-616` (the new
  path-form case)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (each mutation applied to a throwaway clone,
  `gate-tests` re-run, behaviour change confirmed separately)
- **Axis:** needed-used
- **Reachability:** the next agent or human to touch these scripts. The
  harness is `verify-ladder`'s step-4 hard gate, so a green run is what
  the workflow treats as "the gates still refuse what they must". Six
  ways to reintroduce a fixed defect are invisible to it.
- **Rule:** n/a — but it is the defect class `#G2` on
  2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md
  and `#F18`/`#F21` in this file already named, now at fifteen instances.
- **Finding:** enumerated, each verified to change real behaviour:
  1. **`#F23`'s fix is unguarded.** Putting `continue` back into
     `plan-citations`' `PATHFORM` arm (line 178) — the exact defect
     `#F23` records — passes 98/98. Demonstrated live: with a path-form
     citation to a nonexistent plan inside a frozen `done/` file, HEAD
     reports `no such plan file under docs/plans/*/` and exits 1, the
     mutant prints `plan-citations: OK (379 citations resolve; ...; 2
     path-form in frozen plans)` and exits 0. The new case
     ("plan-citations refuses a plan cited by path") uses a *non-frozen*
     file citing an *existing* plan, so it exercises neither the frozen
     exemption nor the still-resolves property — the two halves `#F23`
     is about.
  2. **`plan-repair` has no positive control at all.** Both its cases are
     `expect_fail`. Making its awk print the file unchanged while still
     exiting 0 passes 98/98: the harness cannot tell `plan-repair` from a
     no-op. `gate-tests`' own header says why this matters ("plus a
     positive control, because a gate nothing can satisfy is the other
     half of the same defect").
  3. **The insertion point is unguarded.** Changing `/^# /` to
     `/^## Progress/` (so `## State` lands *after* `## Original plan` and
     `## Progress`, violating `PLAN_SECTIONS` order) passes 98/98.
  4. **`plan-repair`'s checksum re-record is unguarded.** Deleting
     `plan_record_checksum "$root" "$rel"` (plan-repair:53) passes 98/98,
     and that is the line that keeps the manifest true — without it every
     repaired plan is permanently un-committable.
  5. **`#F24`'s exact path match is unguarded.** Reverting
     `plan_record_checksum`'s awk to the old
     `grep -vF "  $rel" ... || true` passes 98/98.
  6. **`#F11`'s enforcement is unguarded** — see `#F34`.
  For contrast, the mutations that *are* caught: dropping `plan-freeze`'s
  lint gate, dropping either `plan-repair` refusal, dropping the
  `PATHFORM` classification, and moving `plan-reject`'s gate back after
  the `git mv` each produce exactly one FAIL. So the new cases are not
  worthless — they cover the refusals and nothing else.
- **Fix risk:** each added case costs runtime on a harness `#G8` already
  records as over budget at 1.15s (measured 1.25s on this host). Items 1
  and 2 are cheap (no `git` calls, no sweep); item 6 needs a fixture
  manifest and must clean it up, since `gate-tests:576` already warns
  that a leftover `docs/plans/.checksums` makes later cases pass for the
  wrong reason.


**FIXED 2026-09-08:** the five mutations named for plan-repair and F23 are now all caught: a no-op write, a dropped checksum re-record, a moved insertion point, a dropped checksum precondition, and putting continue back in the PATHFORM arm. plan-repair has a positive control that asserts the section lands first, not merely that it exists -- the version asserting presence alone passed with the insertion point moved. F34's guard is covered too. 102 assertions

### F36 — `plan-reject` still leaves a half-state and exits 0 when `git mv` fails; `#F31` fixed the ordering, not the failure

- **File:** `docs/skills/plan/scripts/plan-reject:42-51`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (reproduced in a throwaway clone)
- **Reachability:** anyone running `plan-reject` — a contributor or an
  agent, `plan-reject *` being pre-approved in `plan/SKILL.md`'s
  `allowed-tools`. `git mv` fails when the destination already exists (a
  same-basename plan already in `rejected/`, which `plan_locate` does not
  catch for a path-form argument), when the source is untracked (a plan
  file written by hand or by an agent's Write rather than by `plan-new`),
  or when the index is locked by a concurrent git.
- **Axis:** hardening
- **Rule:** n/a — but it is `docs/hardening.md` rule 11's shape ("a guard
  that declines to act must be watched by something that measures the
  outcome, not the attempt") applied to a script instead of a unit.
- **Finding:** the script is `set -u` with no `set -e` and no `||` on
  line 46, so a failed `git mv` does not stop it. Reproduced with a
  placeholder file pre-placed at the destination: `git mv` printed
  `fatal: destination exists`, and `plan-reject` then went on to
  (a) leave the real plan in `todo/` carrying a
  `**REJECTED 2026-09-08:** abandoned` marker appended at line 42
  *before* the move, still `status: todo`, still `frozen: false`;
  (b) run `plan_do_freeze` against the unrelated placeholder, recording
  *its* checksum in `docs/plans/.checksums` — so a file no gate ever saw
  is now frozen as far as `plan_manifest_frozen` and
  `.githooks/pre-commit` are concerned; (c) repoint
  `.claude/.active-plan` at that placeholder; and (d) **exit 0**, printing
  `... rejected and frozen.` and echoing the destination path, so a caller
  or agent reads it as success. `#F31` moved the lint gate ahead of the
  marker, which closes the *refusal* path; the *failure* path still
  produces exactly the half-state `#F31`'s comment says it prevents ("a
  state no script put it in and none clears"). Note `plan-move:49` has
  the same unchecked `git mv`, but no prior file mutation, so it fails
  less destructively.
- **Fix risk:** adding `|| plan_die` after the `git mv` still leaves the
  REJECTED marker appended to the source; the marker append wants to move
  after the successful `git mv` (it is append-only either way), or the
  whole sequence needs an unwind. Test: reject with the destination
  occupied, with an untracked source, and the ordinary happy path;
  `gate-tests`' sabotage sweep does not currently cover `plan-reject` or
  `plan-freeze` at all, which `#G8` lists as still owed and which is
  exactly the sweep that would have caught this.


**FIXED 2026-09-08:** plan-reject checks its git mv and dies with the state named, instead of freezing and checksumming whatever sat at the destination and exiting 0

### F37 — `plan-repair` writes with an unchecked `cat > "$file"`, then reports success and re-records the checksum even when nothing was written

- **File:** `docs/skills/plan/scripts/plan-repair:46,53-55`
- **Severity:** LOW
- **Confidence:** CONFIRMED (reproduced: `chmod a-w` on the target)
- **Axis:** hardening
- **Reachability:** whoever runs `plan-repair` on a target the process
  cannot fully write — a read-only file (the 50 frozen plans are exactly
  the files most likely to be chmod-protected by a cautious operator), a
  full filesystem, or an interrupted write.
- **Rule:** n/a
- **Finding:** every other writer in this library renames a tempfile into
  place (`plan_set_field:120`, `plan_append_under_heading:294` both use
  `mv "$tmp" "$file"`). `plan-repair` alone truncates the target with a
  redirect and streams into it, and does not check the result. With the
  target read-only, the run prints
  `plan-repair: line 46: ...: Permission denied`, then
  `... added '## State' and re-recorded its checksum.`, echoes the path,
  and **exits 0** — having added nothing. `plan_record_checksum` runs
  regardless, so on a partial write (ENOSPC, SIGINT during `cat`) the
  manifest is updated to bless whatever truncated content is on disk and
  `git add`s it, which is the one outcome the freeze manifest exists to
  make impossible. `mv "$tmp" "$file"` would be atomic and would fail
  loudly; the `trap 'rm -f "$tmp"' EXIT` already in place makes the
  change free.
- **Fix risk:** none functional — `mv` across the same filesystem is a
  rename; `mktemp` uses `$TMPDIR`, which may be a different filesystem
  from the repo, in which case `mv` falls back to a copy and can still
  fail partway, so the status check is the load-bearing part, not the
  `mv`. Add a positive `gate-tests` case (see `#F35` item 2) that would
  notice.


**FIXED 2026-09-08:** plan-repair writes with mv, not cat, so a failed write is a failure rather than a success message over an unchanged file

### F38 — `plan-repair`'s title matcher is fence-blind, so it can insert `## State` inside a code fence, re-bless the checksum, and do it again on the next run

- **File:** `docs/skills/plan/scripts/plan-repair:35-45`, against
  `docs/skills/plan/scripts/lib.sh:160-171` (`plan_headings`, used two
  lines earlier at plan-repair:27)
- **Severity:** LOW
- **Confidence:** CONFIRMED (reproduced in a throwaway clone)
- **Axis:** hardening
- **Reachability:** an operator running `plan-repair` on a frozen plan
  whose first `^# `-anchored line is not its title — a shell comment at
  column 0 inside a fenced block, in a plan with no H1. Not reachable
  against today's corpus: all 50 frozen plans have an H1 immediately
  after the frontmatter (verified), and all 27 repairs landed exactly two
  lines below it (verified). This is about the script that stays in the
  repo, not about the 27.
- **Rule:** n/a — but it is the same defect class as `#F13` in this file,
  which is why the sibling reader was made fence-aware.
- **Finding:** line 27 asks `plan_headings` — deliberately fence-aware,
  per `#F13` — whether `## State` already exists. Line 36 then finds the
  insertion point with a bare `/^# /`, which is fence-blind *and*
  frontmatter-blind (it starts at line 1, so a `#` comment in the
  frontmatter would match too). Reproduced: on a frozen plan whose body
  opens with a fenced `sh` block whose first line is the shell comment
  `# a shell comment, not a title`, and no H1, `plan-repair` exits 0, splices the heading and its note into
  the middle of the code block, and re-records the checksum so
  `pre-commit` accepts the corruption. Because `plan_headings` correctly
  refuses to see a heading inside a fence, the "already has a section"
  refusal at line 27 does not fire on a re-run: running it a second time
  produced two `## State` headings and two notes, unbounded on repeat.
  The inserted note's own text — "no word of the original was changed" —
  and `SKILL.md`'s "it can only ever add a heading nobody wrote" are both
  false in this case; it changed the meaning of a code block.
- **Fix risk:** making the matcher fence-aware (reuse `plan_headings`'
  fence state machine, or reject any `# ` line before the frontmatter's
  closing `---`) would refuse a plan whose title is genuinely absent —
  which is already the intended behaviour, since line 45 exists to say
  so. Test against all 50 frozen plans to confirm the refusal set does
  not grow.


**FIXED 2026-09-08:** plan-repair finds its insertion point with the same fence-and-frontmatter-aware scan its guard already used, so the section cannot be spliced into a code block and then checksummed over

### F39 — `plan_record_checksum` does not normalise the path `plan_manifest_frozen` normalises, so one `./` in the argument writes a duplicate manifest entry and permanently blocks the file

- **File:** `docs/skills/plan/scripts/lib.sh:440-455` vs `:192-207`;
  `docs/skills/plan/scripts/plan-repair:21`
- **Severity:** LOW
- **Confidence:** CONFIRMED (reproduced in a throwaway clone)
- **Axis:** needed-used
- **Reachability:** anyone invoking `plan-repair`, `plan-freeze` or
  `plan-reject` with a path containing a `.` segment — the exact spelling
  `#F20` names as arriving in practice
  (`docs/plans/./done/x.md`), which `plan_locate` passes through
  unchanged because its `case` glob's `*` matches `/`.
- **Rule:** n/a
- **Finding:** `#F20` fixed the *reader*: `plan_manifest_frozen` strips
  `./` and collapses `/./` before matching. `#F24` extracted the *writer*
  and its comment claims "the path field is compared exactly, as in
  `plan_manifest_frozen`" — but it compares against the raw `$rel` with
  no normalisation. So with a `./` argument the reader finds the
  canonical entry (the file is frozen, the repair proceeds) while the
  writer fails to match it and appends a second line. Reproduced: after
  one `plan-repair "docs/plans/./done/<x>.md"` the manifest holds both
  `docs/plans/./done/<x>.md` (new hash) and `docs/plans/done/<x>.md`
  (stale hash). `.githooks/pre-commit:29` matches `$2==f` with git's
  canonical path, so it reads the stale entry and prints
  `BLOCKED: ... is frozen`, permanently — and `plan-repair` now refuses a
  second run because the section exists, so the only remedy is the
  hand-edit of `docs/plans/.checksums` that having a single writer was
  supposed to remove. Separately, `plan_record_checksum` leaves both its
  `awk ... > "$tmp"` and its `sort -k2 "$tmp" > "$checksums"` unchecked:
  a failure of either truncates or thins the freeze manifest, and a
  thinned manifest fails *open* — `plan_manifest_frozen` returns false
  and every affected plan silently stops being frozen.
- **Fix risk:** the normalisation is three lines already written at
  `lib.sh:199-200`; lift them into a `plan_norm_rel` both functions call,
  or normalise once in `plan_locate` so every caller gets it. Normalising
  in `plan_locate` changes what `plan-lint`/`plan-gate` echo back, which
  a test matching the argument verbatim would notice.


**FIXED 2026-09-08:** plan_normalise_rel is shared by plan_manifest_frozen and plan_record_checksum, so the reader and the writer agree on which manifest entry a path names

### F40 — `plan-repair` never checks that the file still matches its recorded checksum, so it launders any other edit sitting in the working tree

- **File:** `docs/skills/plan/scripts/plan-repair:21-53`;
  `docs/skills/plan/reference.md`, "The one exception, and its limits";
  `docs/skills/plan/SKILL.md`, the `plan-repair` row
- **Severity:** INFO
- **Confidence:** CONFIRMED (observed as a side effect of the `#F37`
  reproduction: a stripped `## State` section was re-blessed into the
  manifest even though the repair write itself had failed)
- **Axis:** hardening
- **Reachability:** not reachable against today's corpus — all 50 frozen
  plans now have `## State`, so `plan-repair` refuses every one of them
  (verified by running it against all 50: 50 refusals, 0 repairs). It
  becomes reachable the moment any frozen plan lacks the section again,
  which `#F33`/`#G6` note is what a future `PLAN_SECTIONS` addition
  produces.
- **Rule:** n/a
- **Finding:** both docs state the refusals as making the script safe —
  "it refuses a plan that is not frozen and refuses one that already has
  the section, which means it can only ever add a heading nobody wrote",
  "it cannot edit a word of anyone's text". Neither refusal looks at
  content. `plan-repair` reads the file, inserts, and re-records — so any
  *other* modification present in the working tree at that moment is
  re-blessed into the manifest along with the repair, and
  `.githooks/pre-commit` will then accept it. The claim that should be
  made is narrower: it can only add a heading, *to the content that is
  there when it runs*. Comparing `plan_checksum "$root/$rel"` against the
  manifest entry before writing would make the stated claim true, and
  costs one `sha256sum` on a script that runs 27 times in its life.
- **Fix risk:** the pre-check would refuse a plan whose recorded checksum
  is already stale for an unrelated reason (e.g. after `#F39` has
  happened), turning one broken state into a refusal — which is the right
  direction but needs a message that says which of the two problems it
  is.

**Checked and clean (third `security` pass, `#D1`, over `39ac74f..10469cf`).**
Verified positively rather than merely read: the 27 `docs/plans/done/*.md`
repairs really are +8/-0 each, byte-identical in the seven inserted lines,
and every one landed with `## State` exactly two lines below an `# ` title
that is itself two lines below the frontmatter's closing `---` — no plan
was damaged and no existing section moved relative to another
(mechanically checked across all 27). `docs/plans/.checksums` changed by
exactly 27 modified lines and no additions or deletions. `superseded_by`
was removed from exactly 52 files and nothing else; no script, hook,
workflow or doc still reads, writes or requires it, and
`PLAN_SCHEMA_FIELDS` derives from `PLAN_REF_FIELDS` so `plan-lint` and
`plan-new` could not half-land the removal. `plan-freeze`'s new lint gate
sits after the rung check and before `plan_do_freeze`, and the file is
correctly still judged as editable at that point because its manifest
entry does not yet exist. `plan-reject`'s gate genuinely runs before the
marker append, the `git mv` and the status change — a refused rejection
leaves the plan byte-identical in `todo/` (confirmed against a live
malformed plan; 17 of 52 non-frozen plans fail lint today, matching
`#G10`'s count). `plan-citations` at HEAD resolves 379 citations with 3
ignored regions and 2 muted path-forms, and a path-form citation to a
missing plan is still reported from both a frozen and a non-frozen file.
The `PATHFORM` prefix test matches the leading-`./`, markdown-link and
`../` spellings; its `[a-z-]+` folder class covers every folder that
exists today and the planned `superseded/`. `plan_record_checksum`'s awk
handles a path containing two consecutive spaces correctly (the first
double-space is the separator and `substr(i+2)` takes the rest of the
line), and prefix/suffix path relationships between entries do not
collide under the exact comparison. `plan_do_freeze`'s behaviour is
unchanged for `plan-freeze`, `plan-move ... done` and `plan-reject`: same
three steps in the same order, `plan_mark_touched` still last.
`scripts/gate-tests` is 98 passed / 0 failed / 3 known residues, 1.25s on
this host. Nine mutations were applied and re-run: four are caught
(`#F35` lists them), six are not.

**Hardening axis: empty, and stated plainly.** The diff contains no
`.nix` file, no host or module directory, no systemd unit, no firewall
rule, no `.sops.yaml` and no `secrets/*` — verified by pathspec over the
whole range. Nothing under `docs/hardening.md`'s eleven standing rules is
reachable from this change, and no secret was decrypted or read. The pass
was spent on gate correctness, per the brief.

_security finished 2026-09-08T19:25:24Z (code 94fdc82c1dc7e8e7) -- see Findings above._

**FIXED 2026-09-08:** plan-repair refuses unless the file still matches its recorded checksum, so it cannot certify an edit it did not make -- which is what makes the docs' 'it cannot edit a word of anyone's text' true rather than merely intended

### F41 — seven guards in `scripts/gate-tests` do not guard what they name

- **File:** `scripts/gate-tests` — the rung fixtures (`:129-149`), the
  presentation invariants (`:755-800`), the `plan-lint` section
  (`:361-500`), the `plan-repair`/`plan-reject` section (`:523-660`)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — each found by `scripts/gate-mutants`
  reintroducing the named defect and observing the named case stay green,
  and each re-run red after the fix
- **Axis:** needed-used
- **Reachability:** anyone touching `lib.sh` or a `plan-*` script. The
  harness is `verify-ladder`'s step-4 hard gate, so a green run is what the
  workflow reads as "the gates still refuse what they must".
- **Rule:** n/a — this is `#G12`'s six principles applied mechanically for
  the first time, and the seven are instances of principles 2 and 4.
- **Finding:** enumerated, mutation then fix.
  1. **`nested fence, odd count`** closed `## State` with a `## Progress`
     *before* the fence, so the declaration was already out of scope and the
     case refused whatever the fence logic did. Replacing
     `plan_state_body`'s length-and-character close rule with a toggle on
     any marker — the exact `#F17` defect on
     2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md
     — changed no verdict. The nest now sits inside `## State`.
  2. **`a denial stays refused at any wrap`** used "... not verified to rung
     4 yet, because ...". The trailing word refuses that paragraph on its
     own, so deleting the matcher's leading `^` anchor — which accepts every
     denial — left the invariant green. The fixture now ends the sentence at
     the rung.
  3. **`a denial survives any decoration`** had the same shape ("... rung 3
     yet."), and the same fix.
  4. **`quoting the phrase never declares it`** was satisfied by the
     backtick rule, not the fence rule: with no blank line inside the fence,
     the fence markers join the declaration's block and the backticks refuse
     it. Dropping `skip-fences` from `plan_rung_problem` entirely left it
     green. Blank lines inside the fence now make the declaration its own
     paragraph, so the case tests the property it is named for.
  5. **Nothing asserted that `plan-lint` enforces section order.** The only
     order-adjacent case was a *positive* one (a correct file that quotes the
     template must pass), which stays green with the order check deleted. A
     negative case was added: every section present, one pair swapped.
  6. **Nothing asserted the freeze manifest is keyed on a whole path.** All
     three of `#F20` (reader matched anywhere in the line), `#F24` (writer
     deleted any line the path appeared in) and `#F39` (writer skipped the
     `./` normalisation the reader applied) were invisible to every case.
     Three assertions added, at the library level, with no `git` in two of
     them; the `#F20` case is the strict-prefix reproduction that finding
     records.
  7. **`plan-repair`'s fence-aware title matcher was unguarded** (`#F38`).
     The fixture had no fence, so a bare `/^# /` found the same line; and the
     positive control located `## State` with `grep`, which calls a section
     spliced *inside* a fence the first one. The fixture gained a fenced H1
     before the real title, and the control now reads headings through
     `plan_headings`.
  Two further entries escaped for a reason that is not a suite defect and
  were corrected in the catalogue instead: one named a case that guards a
  different property (`mid-sentence mention` turns on the `^` anchor, not on
  the trailing-word rule), and one is recorded under `#F44`.
- **Fix risk:** low, and mostly paid in fixtures rather than assertions —
  five of the seven were closed by making an existing case's fixture able to
  reach the failure, at no runtime cost. The three additions cost 0.13s
  total against `#G8`'s budget; see `#G13` and `#G11` for what that budget is
  worth.

**FIXED 2026-09-08:** all seven closed, each verified by `gate-mutants`
observing the named case go red under the mutation that restores the defect.
`gate-tests` 110/0/3; the catalogue is 39 caught, 0 escaped

### F42 — `gate-mutants`' own mutation verbs cleared the executable bit, so six entries reported CAUGHT on "cannot execute"

- **File:** `scripts/gate-mutants` (the four mutation verbs)
- **Severity:** HIGH — against the meta-test's whole purpose
- **Confidence:** CONFIRMED by reproduction: a hand-applied mutation of
  `plan-reject` produced `env: '.../plan-reject': Permission denied`
- **Axis:** needed-used
- **Reachability:** every catalogue entry targeting an executable, which is
  all but the `lib.sh` ones.
- **Rule:** n/a — it is principle 3 in `#G12` ("key the assertion on the
  symptom a bypass removes"), turned on the instrument itself.
- **Finding:** each verb wrote its output to a temporary and `mv`'d it over
  the target. `mv` replaces the inode, so the mutant arrived mode 644 and
  every gate script mutation became "the script cannot be run" rather than
  the defect it names. The first full run reported 28 caught; the red counts
  give it away in hindsight — `plan-lint` entries showed *6 of 105 red*
  where the honest number is 1, because six cases invoke a `plan-*` script
  by path. `gate-tests` did catch it, through the diagnostic fragment
  `expect_fail` requires: the case reported "refused, but not for the stated
  reason", which is exactly what `#F3` on
  2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md
  installed that check for.
- **Fix risk:** low. The verbs now `cp` into the existing file, which keeps
  the destination's mode, and the worker asserts mode parity against the
  pristine copy before running anything — so this cannot recur silently even
  if a future verb writes some other way. Note this is the opposite choice
  from `#F37`, which required `mv` over `cat >` in `plan-repair`: there the
  hazard was a partial write reported as success, here it is a lost mode, and
  the two files have different failure costs.

**FIXED 2026-09-08:** verbs write through `mut_write` (`cp` into place); the
worker reports BROKEN if a pristine-executable target comes back
non-executable. Re-run honest: 28 caught, 10 escaped, and the inflated red
counts collapsed to 1

### F43 — a multi-line mutation body truncated the catalogue record, so two entries reported CAUGHT while asserting nothing

- **File:** `scripts/gate-mutants` (record splitting in `--run-one`)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — both entries printed `0 case(s)` in their own
  detail line
- **Axis:** needed-used
- **Reachability:** any entry whose mutation takes more than one verb, which
  is how the `#F31` "gate runs after the move" mutation has to be written.
- **Rule:** n/a.
- **Finding:** a catalogue record is `id`, target, mutation code and then one
  field per expected case, joined by `US`. It was split with
  `IFS="$US" read -r -a rec`, and `read` stops at the first newline — so for
  the two entries with a multi-line mutation body, every case name after it
  was dropped. The worker then looped over an empty expectation array,
  missed nothing, and printed CAUGHT. **The meta-test had the defect it
  exists to find**, and it was visible only because the detail line prints
  the count. Split with `read -r -d ''` now, and an entry naming no case is
  refused as `NO-CASE` in the parent rather than dispatched.
- **Fix risk:** low. With it fixed, `plan-reject/gate-after-move` — the
  entry for the defect that took three attempts to guard — reports honestly,
  and is caught.

**FIXED 2026-09-08:** `read -r -d ''`, plus a `NO-CASE` verdict so an entry
that claims nothing can never be counted as a catch

### F44 — an unnumbered anchor mutated the first of three identical sites, and the entry read as an escape

- **File:** `scripts/gate-mutants` (`lib/state-body-fence-toggle`)
- **Severity:** LOW
- **Confidence:** CONFIRMED by reading the three sites and re-running with
  the occurrence numbered
- **Axis:** needed-used
- **Reachability:** any anchor text that appears more than once in a target.
- **Rule:** n/a — new-rule candidate: a literal anchor that is not unique in
  its file must name its occurrence, or the entry is about a different
  function than the one it names.
- **Finding:** the CommonMark fence close rule
  (`else if (substr(m, 1, 1) == substr(open, 1, 1) && ...)`) appears verbatim
  three times in `lib.sh` and `plan-repair`. The entry named
  `plan_state_body`; occurrence 1 is `plan_headings`, some 180 lines earlier.
  So the mutation applied — not `INERT` — to a function whose behaviour the
  named case does not depend on, and the entry reported `ESCAPED`. The
  suite was not at fault; the catalogue was. Worth recording because the
  failure is silent in the direction that costs time: it looks exactly like
  a real coverage gap, and the fix for a real gap (write a new case) would
  have been wasted work.
- **Fix risk:** low; the entry now names occurrence 2 and is caught.

**FIXED 2026-09-08:** occurrence numbered, and the hazard noted in the
catalogue beside the entry

### F45 — the sabotage shim's shebang is written at runtime, so the suite cannot run anywhere without `/usr/bin/env`

- **File:** `scripts/gate-tests` (the `fakebin/git` shim)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — the first build of `checks.gate-tests`
  reported 105 passed, 5 failed, and the five were exactly the sabotage
  sweeps
- **Axis:** needed-used
- **Reachability:** any environment without `/usr/bin/env`, which is every
  Nix build sandbox — so it blocked the very thing `#D2` decided to build.
- **Rule:** n/a — new-rule candidate: a file a test *generates* is not
  covered by whatever rewrites the shebangs of files the repo checks in.
- **Finding:** the shim is written with
  `printf '#!/usr/bin/env bash\n'` at run time. `patchShebangs` rewrites
  checked-in scripts before the suite starts and cannot see a file that does
  not exist yet, and the sandbox provides `/bin/sh` but not `/usr/bin/env`.
  The shim therefore failed to exec on every git call, each swept gate
  refused with nothing sabotaged, and all five sweeps reported
  `the gate already refuses with nothing sabotaged; the sweep would prove
  nothing`. That message is the `#F3` baseline check on
  2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md
  doing its job: without it the sweeps would have reported `ok` five times
  over an instrument that never intercepted anything, which is `#F6` on that
  same plan exactly.
- **Fix risk:** low. The shim now takes `$BASH`, the absolute path of the
  interpreter already running the suite, which is defined in every bash and
  needs no external resolution.

**FIXED 2026-09-08:** `printf '#!%s\n' "$BASH"`. `checks.gate-tests` builds
green at 110/0/3 in the sandbox, and the suite is unchanged outside it

### F46 — `#D2`'s chosen option says to drop `verify-ladder`'s direct `gate-tests` call, which would have left nothing running the suite before a commit

- **File:** this plan's `#D2` — its first option, and the `ANSWERED` note
  restating it — and `docs/skills/workflow/scripts/verify-ladder`
- **Severity:** MEDIUM — it would have removed a gate while reading as
  wiring one up
- **Confidence:** CONFIRMED — `nix flake check --help` documents
  `--no-build` as "Do not build checks", and `verify-ladder` passes it
- **Axis:** needed-used
- **Reachability:** whoever implemented `#D2` as written, which was the next
  session's stated task.
- **Rule:** n/a.
- **Finding:** both `#D2`'s option text and `#G11`'s argument for it rest on
  "it runs inside `nix flake check`, which `verify-ladder` already runs
  last, so the tier keeps running locally on every pass". `verify-ladder`
  runs `nix flake check --no-build`, which evaluates checks and does not
  build them. So a `checks.*` entry runs in CI and on a full `nix flake
  check`, and never before a commit. Dropping the direct call "or the
  harness runs twice per pass" would have traded one run for zero — the
  "nothing runs them at all" outcome `#G8` names as strictly worse than
  being over budget. The decision itself is unaffected: `checks.*` over a
  GitHub Actions step was the right call and is what landed. Only the
  implementation note attached to it was wrong.
- **Fix risk:** low, and it is the cheaper direction: keep the direct call
  and add the checks. The cost is one extra 1.2s run in the rare case
  someone runs a full `nix flake check` in the same session as
  `verify-ladder`.

**FIXED 2026-09-08:** `verify-ladder` keeps its direct call, with the
`--no-build` reason recorded beside it; `checks.gate-tests` and
`checks.gate-mutants` added. Both build green

### F47 — `plan_die` inside a command substitution exits the subshell, so 23 call sites carried on with an empty repo root

- **File:** every `plan-*` script plus `required-agents`, `plan-gate` and
  `verify-ladder` — 23 sites across 13 files; the fail-open path was proved
  through `docs/skills/plan/scripts/plan-move`
- **Severity:** HIGH
- **Confidence:** CONFIRMED — the new `plan-move` sabotage sweep reported
  `call 1 failed; gate still exited 0 saying: docs/plans/in-progress/`
- **Axis:** needed-used
- **Reachability:** any `git` failure at the first call a plan script makes:
  a corrupt index, a missing `.git`, a hook running with the wrong `GIT_DIR`.
  No adversary needed.
- **Rule:** n/a — new-rule candidate: a helper whose error path is
  `plan_die` cannot be called in `$( )` without checking its status, because
  the `exit` lands in the subshell.
- **Finding:** `plan_repo_root` and `plan_locate` both end in `plan_die`,
  which is `printf >&2; exit 1`. Every caller invokes them as
  `root="$(plan_repo_root)"`. The `exit` ends the command substitution's
  subshell, the assignment succeeds with an empty value, and the script runs
  on. In `plan-move` that produced a run which moved nothing, staged
  nothing, printed `docs/plans/in-progress/` and **exited 0**. The suite did
  not catch it before because the swept gates were all read-only ones, and
  in those the empty root happens to make a later `plan_die` fire at top
  level — so they refused, for the wrong reason, and looked correct.
  Compounding it, `plan-move` left both its `git mv` and its `git add`
  unchecked, so even a checked root would have reported success over a
  failed move — the same defect `#F36` fixed in `plan-reject` and did not
  fix in its sibling. `plan_record_checksum`'s `git add` was unchecked too,
  which is a freeze whose evidence never reaches the commit.
- **Fix risk:** low. `|| exit 1` on all 23, and `|| plan_die` on the three
  writes. `plan_die` already prints, so no diagnostic is lost.

**FIXED 2026-09-08:** 23 call sites checked, `plan-move`'s mv and stage
checked, `plan_record_checksum`'s stage checked. Three new sabotage sweeps
cover it, and `gate-mutants` carries the entry that restores it

### F48 — `.githooks/pre-commit` skipped its frozen-plan check, and its binary probe, whenever the git call underneath failed

- **File:** `.githooks/pre-commit`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — the new sweep found all three, one per
  iteration, each fixed before the next surfaced
- **Axis:** needed-used
- **Reachability:** whoever commits while git cannot read the index — and
  the frozen-plan check is the one that makes a frozen plan permanent.
- **Rule:** the file's own stated stance, three lines further down:
  "anything else that cannot be read is still fail-closed". Two of its own
  reads did not follow it.
- **Finding:** three, in the order the sweep surfaced them.
  1. `if manifest="$(git show ':docs/plans/.checksums' 2>/dev/null)"` cannot
     tell "no manifest, nothing is frozen yet" from "git failed". On failure
     the whole frozen-plan check was skipped and the hook still exited 0.
     Now it asks `git ls-files --error-unmatch` first and treats any status
     other than a clean 0 or 1 as fatal, which also moves the `git show`
     out of a condition so `set -e` covers it.
  2. The gitlink probe read the staged mode unchecked; an unreadable mode
     made the "not a gitlink" branch win by default. It now blocks, like the
     content read beside it.
  3. The binary probe was `git show | grep -qaP`. Its status is unusable:
     `pipefail` reports the rightmost non-zero status, and grep's "no match"
     is also 1, so a failed read is indistinguishable from a text file. It
     now writes the blob to a temporary file, checks git's own status, and
     greps the file — which also keeps the reason the second read exists at
     all, that a command substitution strips the NUL bytes it looks for.
- **Fix risk:** low, and all three make the hook stricter rather than
  looser. The third adds one `mktemp` and a trap.

**FIXED 2026-09-08:** all three; `.githooks/pre-commit` is now swept, and
three `gate-mutants` entries restore them individually

### F49 — the contract phase's "once no reference remains" test is `plan-citations`, which cannot see the references that actually break

- **File:** this plan's `#G4` (the expand—contract design), and the batch-1
  file, 2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — found while contracting batch 1, and one of
  the missed references was caught by `plan-citations` only because it
  happened to be in anchored form
- **Axis:** needed-used
- **Reachability:** every future batch. This is the gate `#G6` makes the
  contract phase wait on, and it does not measure what the phase risks.
- **Rule:** n/a — new-rule candidate: a migration's completeness check must
  cover every form the thing being migrated is written in, not the one form
  a checker already parses.
- **Finding:** `#G4` says to delete a `### G<N>` pointer "once no reference
  remains", and `#G6` names `plan-citations` as the check. `plan-citations`
  resolves `<file>.md#anchor`. It does not see a bare `` `G17` `` in prose,
  which is how a plan file refers to its *own* items — and this file's
  bodies were full of them: **seven references to its own migrated ids**,
  which contracting would have pointed at headings that no longer exist,
  silently and with the checker green. Two more looked identical and had to
  be left alone, because they name a different plan's ids (`` `G7`/`D14`
  references``, explicitly "this session's own meta plan") or quote
  historical text. So the classification is per-reference judgment, not a
  substitution. Separately, one anchored citation *was* missed by my own
  survey: `docs/skills/plan/scripts/plan-citations:47` cites `#G31`, and
  the survey grepped `--include='*.md' --include='*.sh'` while the plan
  scripts have no extension. `plan-citations` caught that one, which is
  exactly the half of the problem it does cover.
- **Fix risk:** low for batch 1, now done. For later batches the cost is
  real: each file's own prose references must be read and classified before
  its pointers can go.

**FIXED 2026-09-09:** batch 1 contracted — seven prose references migrated,
two deliberately left, the missed `#G31` citation corrected, six lessons
renumbered `G1`-`G6` with the old numbers recorded in the file. The rule for
later batches is written into `#G4`

### F50 — `reference.md` still gave `plan-citations` green as the contract phase's completeness test, which `#G4`'s own amendment had just withdrawn

- **File:** `docs/skills/plan/reference.md:87-92` (the expand—contract
  paragraph under "`kind`, and the two shapes a plan comes in")
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED by reading the paragraph against `#G4` as
  amended 2026-09-09 and against `#F49`.
- **Axis:** doc-code
- **Reachability:** every future contract batch. `reference.md` is the
  document an agent reads to learn the pattern; `#G4` is the one it would
  only reach by following a citation the paragraph did not carry.
- **Rule:** n/a — the same rule `#F49` proposes: a migration's completeness
  check must cover every form the thing being migrated is written in.
- **Finding:** the paragraph read "remove the old form only once the
  checker reports zero unresolved references for that batch ... `blocked_by`
  plus `plan-citations` already supply both halves." `#F49` established, by
  contracting batch 1, that `plan-citations` resolves `<file>.md#anchor` and
  is blind to the bare `` `G<N>` `` a plan uses for its own items — seven of
  which would have been silently pointed at deleted headings with the
  checker green. `#G4` was amended to spell out the three-step check;
  `reference.md` was not, so the only reader-facing statement of the pattern
  still named the test that does not measure what the phase risks.
- **Fix risk:** low, documentation only.

**FIXED 2026-09-09:** the paragraph now says a batch's old form goes only
once every form the reference is written in has been checked, names
`plan-citations` green explicitly as *not* that test, and cites `#G4` for the
three steps. The "both halves" claim is narrowed to the mechanical half

### F51 — every harness number in `testing-changes.md` and `verify-ladder` was a session old again, and `gate-mutants`' header still called its own home blocked

- **File:** `docs/procedures/testing-changes.md:218,248`;
  `docs/skills/workflow/scripts/verify-ladder:51`; `scripts/gate-mutants:36-38`
- **Severity:** LOW
- **Confidence:** CONFIRMED by measurement on this host — `gate-tests` 1.57s,
  1.59s, 1.59s over three runs and 114 assertions; `gate-mutants` 46 entries,
  9.8s across 16 jobs.
- **Axis:** doc-code
- **Reachability:** anyone deciding whether they have budget to add a case,
  or where the slow tier runs. `#G8`'s budget argument is made from these
  figures.
- **Rule:** n/a — this is `#F25` recurring one branch later, which is the
  point: a measured number written into prose goes stale at the next commit
  that adds a case.
- **Finding:** `testing-changes.md` said `gate-tests` measured 1.20s (it is
  1.59s) and `gate-mutants` had 39 entries costing about 7s (it is 46 and
  about 10s); `verify-ladder`'s comment said ~1.2s. Separately,
  `gate-mutants`' header still said "its server-side home is blocked on
  `#D2` alongside the fast/slow split" — `#D2` was answered, and the same
  branch wired the script up as `checks.gate-mutants` in
  `modules/flake/gate-checks.nix`, so the header described the script as
  unhomed in the commit that homed it.
- **Fix risk:** low, comments and prose only.

**FIXED 2026-09-09:** the three figures re-measured and corrected, the
assertion count added beside the timing so the two stale together,
and `gate-mutants`' header now states where it runs instead of what it is
blocked on

### F52 — `plan_manifest_frozen`'s docblock was stranded above `plan_normalise_rel`, leaving the function it describes undocumented

- **File:** `docs/skills/plan/scripts/lib.sh:187-197` before the fix
- **Severity:** LOW
- **Confidence:** CONFIRMED by reading the file — the block ending
  `# plan: ...#F11` sat directly above `plan_normalise_rel() {`, and
  `plan_manifest_frozen() {` six lines below had no comment at all.
- **Axis:** doc-code
- **Reachability:** anyone reading `lib.sh` to find out which authority
  decides frozen. The stranded block is the only place that says it is the
  manifest and not the self-declared field.
- **Rule:** n/a — third instance in this plan of the same shape (`#F6`,
  `#F15`, `#F32`): a function inserted between a docblock and its
  definition silently reassigns the docblock.
- **Finding:** `plan_normalise_rel` was extracted during `#F39` and inserted
  between `plan_manifest_frozen`'s docblock and `plan_manifest_frozen`
  itself. The result reads as one function documented twice, under two
  names, with two plan citations — and `plan_manifest_frozen`, the reader
  every era-gated lint rule depends on, documented nowhere.
- **Fix risk:** low, comment move only; no code touched.

**FIXED 2026-09-09:** the `plan_manifest_frozen` block moved down onto its
own definition, leaving `plan_normalise_rel` with the `#F39` block that
describes it

### F53 — `vm-testing.md`'s "Adding a check" recipe sends a non-VM check to the wrong registration file

- **File:** `docs/procedures/vm-testing.md:97-98` ("register it in
  `modules/flake/checks.nix`")
- **Severity:** LOW
- **Confidence:** CONFIRMED — this branch added `tests/gate-script-check.nix`,
  which boots no VM and registers in `modules/flake/gate-checks.nix`, while
  the only doc that says where a `tests/` file gets registered names
  `checks.nix` unconditionally.
- **Axis:** doc-code
- **Reachability:** the next person adding anything to `tests/`. Following
  the recipe would collide with `gate-checks.nix`'s stated reason for
  existing — one `checks` key per file.
- **Rule:** n/a
- **Finding:** `vm-testing.md` is scoped to `runNixOSTest` throughout, so
  nothing in it is false, but `tests/` is no longer VM-tests-only and the
  document is the only map of that directory. `#D2` put the gate checks in
  their own file deliberately; that split was recorded in
  `gate-checks.nix`'s own header and in `testing-changes.md`, and in neither
  place a reader of `tests/` would look.
- **Fix risk:** low, documentation only.

**FIXED 2026-09-09:** one paragraph added under "Adding a check" naming
`gate-checks.nix` as the home for a check that boots nothing, and the reason

_docs-updater finished 2026-09-09T16:53:59Z (code 29bbbe5005a7873b) -- see Findings above._

### F54 — `plan_record_checksum` rewrites the freeze manifest with three unchecked steps, so one failure empties it, stages the empty file, and still prints "frozen"

- **File:** `docs/skills/plan/scripts/lib.sh:454-460` (the `awk`/`printf`/`sort`
  sequence inside `plan_record_checksum`); callers `plan-freeze`,
  `plan-reject` and `plan-repair` all run `set -u` only, no `-e`, no
  `pipefail`.
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (reproduced in a scratch fixture under
  `$TMPDIR`, never against this repo)
- **Axis:** hardening
- **Reachability:** anyone who later wants to alter a frozen plan, and any
  agent that edits one by accident. The path does not need an attacker to
  start it: `sort -k2 "$tmp" > "$checksums"` truncates the manifest *before*
  `sort` runs, so an ENOSPC on the repo filesystem, a full `$TMPDIR`, a
  SIGINT landing between the truncate and the write, or an `awk` that cannot
  read the manifest leaves the file empty or partial. `git add` then stages
  it — successfully, because staging an empty manifest is not an error — and
  `#F47`'s new `|| plan_die` never fires. `.githooks/pre-commit` treats an
  empty manifest as "nothing is frozen" (see `#F55`), so from that commit on
  every one of the 50 frozen plans can be edited and committed with the hook
  exiting 0.
- **Rule:** new-rule candidate — the same class `#F47` and `#F48` closed
  ("a gate must not report success over a write it could not make"), left
  open in the one function that writes the freeze evidence.
- **Finding:** measured, not argued. In a scratch repo with three manifest
  entries and `sort` replaced by a shim that exits 1, `plan-freeze` printed
  `docs/plans/done/...-h.md frozen.` and exited 0 while
  `docs/plans/.checksums` went from 2 entries to 0 both on disk and in the
  index — including the entry it had just claimed to write. None of `awk`,
  `printf` or `sort` is checked, and the rewrite is not atomic: the manifest
  is truncated in place rather than written to a temp file and renamed. The
  `git add` that *is* checked runs after the damage and reports success over
  it. Nothing downstream notices, because `sha256sum -c` passes vacuously on
  an empty manifest and no gate runs it anyway (`#F57`).
- **Fix risk:** low. Writing the new manifest to a temp file and `mv`-ing it
  into place, with every step checked, changes no interface; `plan-freeze`,
  `plan-reject`, `plan-repair` and the `lib/record-checksum-*` mutants in
  `scripts/gate-mutants` all exercise it. A `gate-tests` case would need to
  make `sort` or `awk` fail — a PATH shim in the fixture, the same technique
  the sabotage sweep already uses for `git`.


**FIXED 2026-09-09:** plan_record_checksum now checks the awk, the printf and the sort, sorts into a second temporary and replaces the manifest by mv rather than by a redirect onto itself, and refuses outright to write a manifest with fewer entries than it had. gate-tests asserts it with a failing sort forced onto PATH; gate-mutants restores both the redirect and the shrink guard's removal

### F55 — `.githooks/pre-commit` cannot tell "nothing is frozen yet" from "the manifest was just deleted", so staging its removal switches the frozen-plan check off and the hook exits 0

- **File:** `.githooks/pre-commit:36-46`
- **Severity:** LOW
- **Confidence:** CONFIRMED (reproduced in a scratch fixture)
- **Axis:** hardening
- **Reachability:** anyone writing the commit — in practice an agent taking
  a shortcut, or a merge/rebase that drops the file. `git rm --cached
  docs/plans/.checksums` staged alongside an edited frozen plan: the tampered
  plan is staged, the hook prints nothing and exits 0. Verified against a
  control run (manifest left in place) that blocked correctly.
- **Rule:** n/a — the same fail-open shape `#F48` set out to close, one case
  further out.
- **Finding:** `#F48` made the *read* fail-closed: `git ls-files
  --error-unmatch` first, anything but exit 0 or 1 fatal. Exit 1 still means
  "untracked", which is correct for a repo with nothing frozen yet and wrong
  for a repo whose manifest is staged for deletion — and the hook has the
  evidence to tell them apart, since HEAD still carries the file. This
  matters mostly because it is what makes `#F54` silent: an emptied or
  removed manifest and a repo that has never frozen anything are the same
  input to this hook. The stated design ("deletions are allowed... this only
  guards against silent content drift") covers deleting a *plan*; it does not
  say the freeze evidence itself may be deleted without comment.
- **Fix risk:** low, but not zero: a repo that legitimately deletes the
  manifest (removing the whole plan system) would need `--no-verify` once, or
  the check would have to compare against HEAD and allow the case where no
  `docs/plans/*/*.md` is staged. The `pre-commit/manifest-read-swallowed`
  mutant covers the read, not the deletion, so a new `gate-tests` case is
  needed too.


**FIXED 2026-09-09:** the hook now asks whether the manifest's deletion is staged and blocks if it is. The first version of this fix reintroduced the same defect one call later -- the git diff ran in a pipeline, where its own failure is indistinguishable from grep's no-match -- and the sabotage sweep caught that immediately, which is the second time this session a fix for a fail-open read was itself a fail-open read. It is an assignment now, so set -e covers it

### F56 — `plan_require_not_frozen` still reads the self-declared `frozen:` field, so `plan-move` will carry a manifest-frozen plan out of `done/` and pre-commit then accepts any edit to it

- **File:** `docs/skills/plan/scripts/lib.sh:233-235`; callers
  `docs/skills/plan/scripts/plan-move:21` and
  `docs/skills/plan/scripts/plan-reject:22`. Contradicts
  `docs/skills/plan/reference.md`'s "Which files the schema rules apply to",
  which states the manifest is what "frozen" means repo-wide.
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (reproduced in a scratch fixture)
- **Axis:** hardening
- **Reachability:** any committer or agent that wants a frozen plan editable,
  in three commands and one commit. Flip `frozen: true` to `false` in the
  working tree (uncommitted, so the hook never sees that edit), run
  `plan-move <the done/ plan> in-progress`, then edit freely and commit. In
  the fixture `plan-move` exited 0, the file landed in `in-progress/`,
  `docs/plans/.checksums` kept its now-orphaned `done/` entry, and
  `.githooks/pre-commit` exited 0 over appended content — because the hook
  looks the file up by its *new* path, which has no manifest entry, and
  `--diff-filter=ACMRT` reports a rename under the new name only.
- **Rule:** violates the invariant `#F11`/`#F34` established and
  `reference.md` now documents — "frozen" is the manifest, never the file's
  own field.
- **Finding:** `#F34` converted `plan-freeze` and `#F11` converted
  `plan-lint`, and `plan-repair` was written against the manifest from the
  start. `plan_require_not_frozen` — the guard on the two scripts that can
  *move* a plan, which is the operation that separates a file from its
  manifest entry — was not converted, and is now the only enforcement point
  left reading the self-declaration. A hand-run `git mv` reaches the same
  end state, so this is not the only route; what makes it a finding is that
  the sanctioned tool performs it, reports success, and leaves a manifest
  entry naming a path that no longer exists, which nothing reports (`#F57`).
- **Fix risk:** low for `plan_require_not_frozen` itself (switch it to
  `plan_manifest_frozen`, which needs `$root` as well as the file path, so
  the signature changes and both call sites plus any future one must pass
  it). The larger question — whether the manifest should be rewritten to
  follow a legitimately renamed plan, or whether renaming a frozen plan
  should be refused outright — is a decision, not a patch, and pre-commit's
  "deletions are allowed" note should be re-read against whichever way it
  goes.


**FIXED 2026-09-09:** plan_require_not_frozen takes root and rel and consults the manifest first, then the field; all five callers updated. This was the last enforcement point still trusting the self-declared field, closing the class F11 and F34 opened

### F57 — nothing audits the freeze manifest itself: no gate verifies its checksums, that every frozen plan has an entry, or that every entry names a file that still exists

- **File:** `docs/skills/workflow/scripts/verify-ladder:65-79` (lints the
  active plan only); `.githooks/pre-commit:46-60` (checks only entries whose
  file is staged); `.github/workflows/plan-gate.yml` (runs `plan-gate` only).
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** no adversary needed — this is the reason `#F54` and
  `#F56` are silent rather than noisy. A manifest that lost 49 of its 50
  entries, or that names a path nothing occupies, passes every gate in the
  repo. `sha256sum -c docs/plans/.checksums` is the detector and it is run by
  a human, by hand, and only appears in `scripts/gate-tests`' own fixture.
  It also passes vacuously on an empty manifest, so it is only half a
  detector even when run.
- **Rule:** `docs/hardening.md` rule 11 in spirit — "a guard that declines to
  act must be watched by something that measures the outcome, not the
  attempt". `.githooks/pre-commit` declines to act on every plan with no
  manifest entry, and nothing measures how many entries there should be.
- **Finding:** the freeze gate's whole authority is one 50-line tracked
  file, and its integrity is assumed everywhere and checked nowhere. The
  cheap version is a `gate-tests`-style assertion over the real corpus, or a
  flake check: every `*.md` under `done/` and `rejected/` has exactly one
  entry, every entry names an existing file, and `sha256sum -c` passes with a
  non-zero line count.
- **Fix risk:** low, but it must run over the *real* corpus rather than a
  fixture, which is a new shape for `gate-tests` (it is otherwise
  hermetic, and `scripts/gate-mutants` copies only `TREE_PATHS`, which does
  not include `docs/plans/`). A flake check reading `inputs.self` fits better.

**Checked and found clean (security pass, 2026-09-09).** Reviewed the whole
of `cfe6106..HEAD`. `.githooks/pre-commit`: the `mktemp`/`trap` pair is
correctly scoped — `$blob` is truncated by the `>` redirection on every
iteration so no previous file's bytes can be read as the current one's, a
failed redirection or `git show` is fail-closed with `fail=1`, and the EXIT
trap covers all four `exit 1` paths. The temp file does put a staged blob on
a filesystem for the first time, but `boot.tmp.useTmpfs = true` in
`modules/profiles/default.nix:270` is effective on every real host (verified
with `nix eval` over `nixosConfigurations`: homelab, thinkpad, torrent and
vps all tmpfs; only `isoimage` is not, and it does not run hooks), and the
same bytes are already in `.git/objects` by the time the hook runs, so this
is not new exposure. `git ls-files -s` returning 0 with empty output for an
unindexed file falls through to the content read, which is fail-closed. All
23 `|| exit 1` additions check out: every `$(plan_repo_root)` and
`$(plan_locate ...)` call site in the repo now has one, `plan_die` reached
through `plan_append_under_heading` is only ever called as a statement, and
`subagent-stamp` — the one hook that must never fail the session — was
correctly left alone with its own `git rev-parse` and its `|| exit 0` ladder
intact. `scripts/gate-tests` and `scripts/gate-mutants` were run from a copy
under `/tmp`: 114 passed / 0 failed / 4 residues, and 46 mutants all CAUGHT,
0 escaped / inert / broken. Write containment holds — `git status
--porcelain` on this worktree was byte-identical before and after, every
fixture path roots at a checked `mktemp -d`, `$scratch` is asserted non-empty
before any `rm -rf`, the sabotage shim is on `PATH` only for the swept
command, and both fixtures pin `core.hooksPath`/`commit.gpgsign` and unset
the `GIT_*` channels that would let a caller's environment reach the real
repo. `gate-mutants`' `eval "$code"` and its four mutation verbs write only
to `$work/$target` and `$f.mut` inside a per-mutant `mktemp -d`; the
catalogue is a literal in the script and `--only`/`--jobs` reach no shell,
so there is no untrusted input path into the `eval`. `nix build
.#checks.x86_64-linux.gate-tests` succeeds, and `set -eu` at
`pkgs/stdenv/generic/setup.sh:4` in the pinned nixpkgs confirms the check
cannot `touch $out` over a failing suite. No frozen file was altered outside
`plan-repair`'s permitted `## State` insertion: the manifest's path set is
byte-identical to `cfe6106`, exactly 27 hashes changed for the 27 repaired
plans, and `sha256sum -c docs/plans/.checksums` passes on all 50.
`plan-citations` is green (414 resolve, 1 muted path-form in a frozen plan)
and `plan-lint` is clean on this plan. `plan_frontmatter` filters keys to
`^[A-Za-z_][A-Za-z0-9_]*$` and every array it feeds is `declare -A`, so no
plan file's content can reach an arithmetic array subscript or the
`declare -n` in `plan-lint`; that reader and `plan_get_field` agree on
leading whitespace, quoted keys and duplicates. No secret was read or
decrypted at any point in this review.

_security finished 2026-09-09T17:07:21Z (code d9389c184df201a9) -- see Findings above._

**FIXED 2026-09-09:** the decision now lives in plan_manifest_problem, which verify-ladder calls as a hard gate -- the F10 pattern, a helper so the decision is testable where gate-tests can reach it. One correction to this finding as written: GNU sha256sum -c exits 1 on a file with no checksum lines, so an empty manifest does not pass vacuously. The empty check is a clearer message and defence in depth, not the load-bearing test, and gate-mutants carries a note saying why it has no entry of its own

### F58 — the freeze-manifest step is not in any doc that enumerates what `verify-ladder` blocks on, and both harness counts were a session old again

- **File:** `docs/procedures/testing-changes.md:183,218,248`;
  `docs/skills/workflow/SKILL.md:31-40`;
  `docs/skills/workflow/scripts/verify-ladder:2-12,51`;
  `modules/flake/gate-checks.nix:29`
- **Severity:** LOW
- **Confidence:** CONFIRMED by measurement on this host — `gate-tests` 121
  assertions in 1.72s, `gate-mutants` 51 entries in 12.6s across 16 jobs
  (`nproc` = 16).
- **Axis:** doc-code
- **Reachability:** anyone reading what the pre-commit floor covers, or
  deciding whether there is budget to add a case. Three separate places
  enumerate `verify-ladder`'s steps and all three stopped at three.
- **Rule:** n/a — `#F25`/`#F51` recurring a third time, one commit after
  `#F51` corrected the same two figures. The enumeration half is new: a
  gate that grows a step leaves every list of its steps wrong.
- **Finding:** `99aa7ef` added a `== freeze manifest ==` step that can set
  `fail=1`, and none of `testing-changes.md` ("Runs three repo-level gates
  first"), `docs/skills/workflow/SKILL.md`'s step 4, or `verify-ladder`'s
  own header listed it. `gate-tests`' coverage list in `testing-changes.md`
  also omitted `.githooks/pre-commit` and the freeze-manifest helpers, both
  of which it now exercises.
- **Fix risk:** low, prose and comments only.

**FIXED 2026-09-09:** the step named in all three enumerations, the two
harness figures re-measured (121/1.72s, 51/~13s), `verify-ladder`'s ~1.6s
comment corrected, and `gate-tests`' documented coverage list extended to
what it actually exercises. `gate-checks.nix`'s "~40x the suite" restated
as one run per catalogue entry, so it does not go stale per entry added

### F59 — two comments state that `sha256sum -c` exits 0 on an empty file, which the same session's own correction and a direct measurement both contradict

- **File:** `docs/skills/plan/scripts/lib.sh:223-224` before the fix;
  `scripts/gate-tests:794,803` before the fix
- **Severity:** LOW
- **Confidence:** CONFIRMED by measurement — `: > f && sha256sum -c f` on
  coreutils 9.11 prints `no properly formatted checksum lines found` and
  exits **1**.
- **Axis:** doc-code
- **Reachability:** anyone deciding whether `plan_manifest_problem`'s
  `[ -s "$manifest" ]` guard is load-bearing. Told that `sha256sum -c`
  passes vacuously on an empty file, a reader concludes removing the guard
  reopens `#F54`'s silent path; it does not.
- **Rule:** n/a — the same claim appears three times in this branch and the
  three disagree: `scripts/gate-mutants:377-381` and `#F57`'s own FIXED note
  both carry the correction, while `lib.sh` and `gate-tests` kept the
  original wording from `#F54`'s body.
- **Finding:** the belief came from `#F54` ("`sha256sum -c` passes vacuously
  on an empty manifest") and was corrected while `gate-mutants` was written
  — that is why that file explains why it has *no* entry for the guard —
  but the two comments the correction did not reach still assert it. Both
  sit directly above the code a reader would change.
- **Fix risk:** low, comments and one fixture failure message; no assertion
  renamed, so no `gate-mutants` entry can go `UNKNOWN-CASE`.

**FIXED 2026-09-09:** both comments now say what the empty check is for —
a clearer message for a case `sha256sum -c` also reports, not a case it
would miss — matching `gate-mutants`' note and `#F57`'s correction

### F60 — `plan_manifest_problem` verifies the entries the manifest has, and its docblock and `verify-ladder`'s step comment both read as though it verified the corpus

- **File:** `docs/skills/plan/scripts/lib.sh:215-232`;
  `docs/skills/workflow/scripts/verify-ladder:65-79`
- **Severity:** LOW
- **Confidence:** CONFIRMED by reading the code — the function tests
  `[ -s "$manifest" ]` and `sha256sum -c` over the manifest's own lines, and
  nothing enumerates `docs/plans/{done,rejected}/*.md` to find a plan with
  no entry.
- **Axis:** doc-code
- **Reachability:** anyone reading `#F57` as closed. The docblock says
  "prints why the freeze manifest cannot be trusted, empty if it can", the
  step comment gives "a manifest that lost entries" as its motivation, and
  the success line prints "N frozen plan(s) verify" where N is however many
  lines the manifest happens to hold.
- **Rule:** n/a — the residue of `#F57`, which named three gaps (checksums
  verified, every frozen plan has an entry, every entry names a file that
  exists). Two are closed: `sha256sum -c` covers the hashes and reports a
  missing file as `No such file or directory`. The middle one is not, and
  `plan_record_checksum`'s shrink guard only catches a manifest that loses
  entries *through that function* — a hand edit or a bad merge does not go
  through it.
- **Finding:** delete 49 of 50 lines from `docs/plans/.checksums` and
  `verify-ladder` prints `docs/plans/.checksums: 1 frozen plan(s) verify.`
  and passes; `.githooks/pre-commit` then accepts any edit to the other 49,
  since it skips a staged plan with no manifest entry by design.
- **Not fixed:** only the two comments and `reference.md` were corrected to
  state what is and is not checked. Closing the gap means a check over the
  real `docs/plans/` corpus rather than a fixture, which `#F57` itself
  notes is a new shape for `gate-tests` and probably belongs in
  `modules/flake/gate-checks.nix` — a decision, not a doc edit.

_docs-updater finished 2026-09-09T17:33:30Z (code 12a1595177f8a204) -- see Findings above._

**FIXED 2026-09-09:** closed rather than left recorded: plan_manifest_problem now checks coverage too -- every file in docs/plans/done/ and rejected/ must have an entry, verified against the manifest's exact path field in one awk pass. The invariant holds exactly today (50 entries, 50 done/ files, 0 rejected/, none uncovered). The reverse direction was written and then removed: sha256sum -c already reports an entry whose file is gone as FAILED open or read, so a separate check can never be the guard that fires, and gate-mutants proved it unreachable by escaping. verify-ladder blocks on all of it

### F61 — `plan-gate` still reads the self-declared `frozen:` field, so a plan that writes `frozen: true` into its own frontmatter turns every missing review stamp from BLOCKED into NOTE and the PR gate goes green

- **File:** `docs/skills/workflow/scripts/plan-gate:176-177` (`frozen=0;
  plan_is_frozen "$root/$rel" && frozen=1`) and `:139-145`
  (`stamp_problem`); `docs/skills/workflow/scripts/subagent-stamp:36` reads
  the same field. Contradicts this plan's own `#F56` FIXED note ("This was
  the last enforcement point still trusting the self-declared field").
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (reproduced end to end in a scratch repo under
  `~/.cache`, never against this repo)
- **Axis:** hardening
- **Reachability:** anyone opening a PR, and any agent that would rather not
  wait for a review. `.github/workflows/plan-gate.yml` is the *only*
  automated gate this repo runs in CI, and it runs `plan-gate` from a copy
  pinned to the base branch precisely so a PR cannot neuter its own gate by
  editing the script. The pinning is irrelevant here: the switch is not in
  the code, it is one line of frontmatter in the PR's own plan file, which
  is data the pinned script reads. Measured: a scratch range that changed a
  `modules/*.nix` file and cited an `in-progress/` plan printed two BLOCKED
  lines and exited 1; adding `frozen: true` to that same plan's frontmatter
  and nothing else turned both into NOTE and the run ended `plan-gate: all
  cited plans (1) have their findings resolved and their obliged reviews
  stamped.`, exit 0 — with no `security` or `docs-updater` review having
  run. `plan-lint` does report this (`only plan-freeze may freeze a plan`,
  `plan-lint:61-62`), but `verify-ladder` runs `plan-lint` on the *active
  plan only* and is skill-invoked, so it does not backstop a commit made
  outside the `workflow` skill — which `docs/procedures/testing-changes.md`
  states explicitly. Nothing in CI runs `plan-lint` at all.
- **Rule:** n/a — the `#F11` class ("a plan may not exempt itself by
  self-declaring frozen"), closed in `plan-lint`, `plan-freeze`,
  `plan-repair` and, this session, `plan_require_not_frozen`, and still
  fully open in the one gate that CI actually executes.
- **Finding:** the fix that landed for `#F56` is correct as far as it goes
  and its closing claim is false. Two workflow scripts still decide
  frozenness from `plan_get_field ... frozen`. `subagent-stamp`'s read is
  defensible on its own (it exits 0 without writing, and its comment says
  the two readers must agree), but `plan-gate` converts that same field into
  a downgrade of the review requirement, so the pair is a self-service
  waiver. Note the unresolved-findings check is unaffected and still blocks;
  only the stamp obligation is waived, which is the half that survives an
  agent simply not running the review.
- **Fix risk:** moderate, and the reason the field is read here is real —
  `plan-gate:169-175` argues that blocking on a frozen plan is an unfixable
  gate whose cheapest escape is dropping the `Plan:` trailer. Switching to
  `plan_manifest_frozen "$root" "$rel"` keeps that property for genuinely
  frozen plans (every `done/`/`rejected/` plan has a manifest entry, checked
  by `plan_manifest_problem` as of this session) while removing the
  self-declared route. It needs `$root`, which `plan-gate` already has, and
  CI's pinned `lib.sh` already carries the reader. Must be tested against a
  pre-stamp-era `done/` plan, which is the case the NOTE branch exists for.


**FIXED 2026-09-09:** plan-gate and subagent-stamp both read plan_manifest_frozen now, not the self-declared field. My F56 note claimed this class was closed and it was not -- F56 fixed plan_require_not_frozen only, and plan-gate is the one gate CI runs, where frozen *relaxes* the stamp requirement so the field bought leniency. gate-tests asserts a self-declared frozen plan is still made to carry stamps; gate-mutants restores the field read

### F62 — `plan-carry` is the sixth writer and has no frozen guard, so it silently appends to a manifest-frozen plan and permanently invalidates its checksum

- **File:** `docs/skills/plan/scripts/plan-carry:17-45` — no
  `plan_require_not_frozen`, then `plan_append_under_heading "$root/$rel"`
  and an unchecked `git -C "$root" add "$rel"` on the *original* plan.
  `docs/skills/plan/reference.md:235-238` enumerates the guarded writers as
  "`plan-move`, `plan-reject`, `plan-decide`, `plan-resolve` and
  `plan-tick`", presenting that set as complete.
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED (reproduced in a scratch repo under `~/.cache`)
- **Axis:** hardening
- **Reachability:** any agent or human following the documented deferral
  workflow. `plan-carry <plan> D<N>` requires only that `D<N>` carry a
  DEFERRED marker with no CARRIED marker. A `done/` plan cannot normally be
  in that state, because `plan-move ... done` refuses unresolved decisions —
  but `plan-reject` deliberately waives exactly that gate ("this does NOT
  require every decision to be resolved"), so every `rejected/` plan may
  hold a DEFERRED-without-CARRIED decision, and picking up a parked question
  from an abandoned plan is the documented reason `plan-carry` exists.
  Measured: against a frozen `rejected/` fixture with a manifest entry that
  verified, `plan-carry` created the new todo plan, appended `**CARRIED
  ...**` to the frozen file, staged it, printed the new path and exited 0;
  `sha256sum -c` went from `OK` to `FAILED` in the same command.
- **Rule:** n/a — the `#F56` class, one script further out.
- **Finding:** the five call sites `#F56` fixed are the five that already
  had a guard. `plan-carry` never had one, so it was not on the list to
  update, and it is the only remaining `plan-*` script that writes into an
  existing plan without asking whether that plan is frozen (`plan-repair`
  writes into frozen plans on purpose and re-records; `plan-freeze` and
  `plan-lint` consult the manifest; `plan-new` creates). The damage is
  fail-closed downstream — `.githooks/pre-commit` then blocks the file
  forever and `plan_manifest_problem` blocks every `verify-ladder` pass —
  but it is silent at the moment it happens, it is staged, and there is no
  in-system remedy: `plan-repair` refuses a frozen file that no longer
  matches its checksum, so recovery is a manual `git checkout` of a file the
  operator has not been told was touched.
- **Fix risk:** low. `plan_require_not_frozen "$root" "$rel"` after
  `plan_locate`, before the DEFERRED/CARRIED probes, matches the other five
  exactly. It does change behaviour: carrying a decision *out of* a frozen
  plan becomes impossible, so the deferral would have to be restated in the
  new plan by hand rather than appended back to the frozen one. That is the
  same trade the freeze rule already makes everywhere else, and it should be
  said in `reference.md` next to the enumeration this finding contradicts.
  A `gate-tests` case needs a `rejected/`-shaped fixture, since a `done/`
  one cannot reach the precondition.


**FIXED 2026-09-09:** plan-carry calls plan_require_not_frozen. It was a sixth writer my grep for existing callers could not find, because it had no call to find. reference.md's list of guarded scripts now names six, and gate-mutants deletes the guard to prove the case goes red

### F63 — the manifest can still be neutered in the same commit as a tampered frozen plan, by emptying it, dropping one entry, or replacing it with a symlink; only outright deletion is refused

- **File:** `.githooks/pre-commit:36-77`
- **Severity:** LOW
- **Confidence:** CONFIRMED (four fixtures in a scratch repo under
  `~/.cache`, with a control)
- **Axis:** hardening
- **Reachability:** whoever writes the commit — in practice an agent taking
  a shortcut, or a merge that mangles the manifest. Measured, each staged
  alongside a tampered `done/` plan: manifest **deleted** blocks (the
  `#F55` fix works); manifest **renamed away** blocks (pathspec limiting
  runs before rename detection, so the source still reports as `D` — worth
  recording, it is not obvious); manifest **truncated to empty** commits
  clean, exit 0; manifest with **only the tampered plan's entry removed**
  commits clean, exit 0; manifest **replaced by a symlink** to `/dev/null`
  commits clean, exit 0. The last three all pass through `ls_rc=0` and then
  either `[[ -n "$manifest" ]]` (empty and symlink cases) or the
  `[[ -z "$recorded" ]] && continue` arm (dropped-entry case).
- **Rule:** n/a — the same fail-open shape `#F48` and `#F55` closed, three
  doors further out.
- **Finding:** the `#F55` comment at `:41-45` calls staging the deletion
  "the cheapest cover for a tampered frozen plan". It is not the cheapest —
  `: > docs/plans/.checksums` and a one-line `sed -i` are both cheaper, both
  are ordinary staged *modifications* of a tracked file, and both produce
  exactly the outcome the deletion check exists to prevent. The symlink case
  is worse in kind: the index entry is mode `120000` and `git show` returns
  the link target as blob content, so `manifest` is a short non-empty string
  that no `$2==f` lookup ever matches, and every frozen file is skipped
  while the hook looks like it checked them. `plan_manifest_problem` catches
  all three, but only inside `verify-ladder`, which is skill-invoked; the
  hook is the layer this repo documents as applying "to any tool or human".
- **Fix risk:** low but not free. The dropped-entry case needs the hook to
  do what `plan_manifest_problem` now does — assert that every staged
  `docs/plans/{done,rejected}/*.md` has an entry — which is a new class of
  block for a repo mid-reorganisation; the empty and symlink cases need the
  index *mode* checked (`100644`) and an empty manifest treated as an error
  whenever HEAD had a non-empty one, not as "nothing is frozen". The hook
  must not gain a dependency on `lib.sh`; it is deliberately standalone.


**FIXED 2026-09-09:** pre-commit now refuses a manifest staged as anything but a regular file (the symlink case, index mode 120000, where git show returns the link target and the file parses as no entries), and refuses a staged manifest that drops an entry for a plan not itself being deleted -- which covers truncation and single-entry removal together. The HEAD comparison is rc-discriminated rather than swallowed: that was the third time on this branch a fix for a fail-open read was itself one, and the sabotage sweep caught it before it landed

### F64 — `plan_record_checksum`'s `mv` is a cross-device copy on this fleet, so the replace is not atomic and it resets the manifest to mode 0600

- **File:** `docs/skills/plan/scripts/lib.sh:513-537`; `mktemp` with no `-p`
  or `TMPDIR`, and `modules/profiles/default.nix:270`
  (`boot.tmp.useTmpfs = true`).
- **Severity:** LOW
- **Confidence:** CONFIRMED (`df -T` shows `/tmp` as `tmpfs` and the
  checkout on `zroot/local/home`; the mode change measured directly with a
  scratch `mv`)
- **Axis:** hardening
- **Reachability:** no adversary needed — the same accident class `#F54`
  named (SIGINT, ENOSPC, a crash) during any `plan-freeze`, `plan-reject` or
  `plan-repair`. The comment at `:515-520` says the manifest is now
  "replaced by a rename rather than by a redirect onto itself", and on every
  host in this fleet it is not a rename: `/tmp` is a tmpfs and the repo is on
  ZFS, so `mv` falls back to open-truncate-copy-unlink on the destination.
  The window is smaller than the redirect's (the copy is one write of ~4 KB
  rather than a truncate followed by `sort`'s whole run) but it is the same
  window, and the shrink guard cannot see it because it runs *before* the
  `mv`. Second, measured effect: `mv` across filesystems carries the source
  mode, and `mktemp` creates 0600, so `docs/plans/.checksums` becomes
  owner-only on disk after any freeze. git tracks only the executable bit,
  so this never shows up in a diff.
- **Rule:** n/a — new-rule candidate, the general form being "a temp file
  written for an atomic replace must be created in the destination's own
  directory".
- **Finding:** stated plainly because the plan's `#F54` FIXED note records
  "replaces the manifest by mv rather than by a redirect onto itself" as the
  fix, and a later reader will take that as meaning the write is atomic. It
  is atomic only if `TMPDIR` happens to be on the same filesystem as the
  checkout, which on this fleet it never is.
- **Fix risk:** low. `mktemp -p "$(dirname "$checksums")"` (or `TMPDIR`
  pointed there) makes both temporaries land beside the manifest, which
  makes the `mv` a real `rename(2)` and preserves nothing surprising about
  the mode — but it puts two short-lived `tmp.XXXX` files inside
  `docs/plans/`, so `plan_worktree_files`, `plan-citations` and the
  `git add` paths should be checked for anything that would pick them up,
  and the `EXIT`-less cleanup in this function means a `plan_die` between
  the two `mktemp`s must still remove them (it does today).


**FIXED 2026-09-09:** both temporaries are created beside the manifest, so mv is a rename on the same filesystem rather than a cross-device copy, and the manifest's own mode is restored with chmod --reference before the move. gate-tests asserts the mode survives

### F65 — the new shrink guard permanently refuses to re-record any path the manifest holds twice, and blames the wrong cause

- **File:** `docs/skills/plan/scripts/lib.sh:530-536`
- **Severity:** LOW
- **Confidence:** CONFIRMED (reproduced in a scratch repo under `~/.cache`)
- **Axis:** needed-used
- **Reachability:** no adversary; a merge or a hand-edit. The manifest is an
  append-mostly sorted file, so two branches that each freeze a plan conflict
  in it, and the natural resolution — keep both sides — can duplicate a line.
  `#F39` produced exactly this shape from a `./` spelling before it was
  fixed. Measured: with three entries of which two name the same path,
  `plan_record_checksum` on that path dies with `refusing to write a
  docs/plans/.checksums with fewer entries than it had; the freeze evidence
  would be lost.` and exits 1, every time, because the `awk` legitimately
  drops both duplicates and the `printf` adds back one.
- **Rule:** n/a
- **Finding:** the answer to "can the refusal be turned into a denial of
  service" is yes, for one shape, and it fails closed — the manifest is left
  untouched, no evidence is lost, and only that one path is affected. The
  real cost is the message: it names the one cause that is not what
  happened, and the operator's obvious next move (re-run `plan-freeze`, or
  `plan-repair`, which is the only sanctioned way to touch a frozen file) is
  also blocked, so the plan becomes unrepairable until someone notices the
  duplicate by eye. Every other legitimate write was checked and is accepted:
  a first freeze grows the manifest by one, a re-record leaves it the same
  size, and both temporaries are removed on all seven exit paths in the
  function.
- **Fix risk:** low. Comparing distinct path counts rather than line counts,
  or simply saying "the manifest holds N entries for this path" when the
  `awk` removed more than one, keeps the guard's strength and removes the
  wrong diagnosis. Whichever is chosen, the `lib/manifest-may-shrink` mutant
  must still be CAUGHT.


**FIXED 2026-09-09:** the guard compares the set of paths, not the line count, so a manifest legitimately holding one path twice collapses to one entry without being refused. Fixing it introduced a second defect the suite caught immediately: the awk used the NR == FNR idiom, which silently breaks when the first file is empty -- FNR never advances, so every record of the second file matches too and a first freeze reported its own new entry as lost. Keyed on FILENAME now

### F66 — both harness counts are a session old again, and two docs now describe the coverage gap that this same range closed

- **File:** `docs/procedures/testing-changes.md:221` ("121 assertions"),
  `:252` ("51 entries"), `:189-192` ("the entries present, not the corpus,
  so a *dropped* entry still passes"), `docs/skills/plan/reference.md:240-242`
  ("Neither checks that every frozen plan still *has* an entry"),
  `docs/skills/workflow/SKILL.md:37-40`.
- **Severity:** INFO
- **Confidence:** CONFIRMED (measured: `scripts/gate-tests` prints `122
  passed, 0 failed, 4 recorded residue(s)`; `scripts/gate-mutants --list`
  and `grep -c '^mutant '` both give 52)
- **Axis:** needed-used
- **Reachability:** anyone reading the testing procedure to decide whether
  the corpus is verified. Two separate errors in one range. First, the
  numbers: `9ba1799` added an assertion and a catalogue entry and updated
  neither count, so the doc says 121/51 against a measured 122/52 — the
  third consecutive recurrence of the class `#F51` and `#F58` already
  record. Second, and worse than a stale number, the prose in
  `reference.md` and `testing-changes.md` was written in `5d05887` to
  document the `#F60` gap, and `9ba1799` closed that gap four commits later
  without revisiting either sentence. They now state the opposite of the
  code: `plan_manifest_problem` does check that every file under
  `docs/plans/done/` and `docs/plans/rejected/` has an entry, and
  `verify-ladder` blocks on it.
- **Rule:** n/a
- **Finding:** the direction of the error is the safe one (the docs
  understate what is enforced), but it is the direction that invites the
  next session to re-add the check that already exists, or to decide the
  invariant cannot be relied on. `SKILL.md` step 4 describes the freeze
  step as hash-only for the same reason.
- **Fix risk:** none — doc edits. The counts are the recurring half; the
  standing answer in this plan is that a number a human retypes goes stale,
  so if it is worth stating it is worth having `gate-tests` print it and the
  doc cite the command instead.


**FIXED 2026-09-09:** counts re-measured (128 assertions, 2.1s; 56 entries, 17s) and reference.md rewritten: it described the coverage gap 9ba1799 had already closed, and listed five guarded scripts where there are now six

### F67 — `out` is not declared `local` in `plan_record_checksum`, in a file its own siblings declare it local in

- **File:** `docs/skills/plan/scripts/lib.sh:507` (`local root="$1" rel sum
  checksums tmp` — `out` missing), against `:712` (`plan_code_fingerprint`:
  `local out r`).
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** no live caller today, which is why this is INFO:
  `plan_do_freeze`, `plan-freeze`, `plan-reject` and `plan-repair` use
  `lint_out`/`reject_out`, not `out`. But `scripts/gate-tests` sources
  `lib.sh` into its own top-level shell (`:18`) and keeps a global `out` in
  its assertion helper (`:262`), so the day a case calls
  `plan_record_checksum` directly rather than through the `ev()`/`mf()`
  subshells it uses today, the manifest writer silently clobbers the
  variable the harness reports failures from.
- **Rule:** n/a
- **Finding:** a one-word omission with no current effect, recorded because
  the function is the single writer of the freeze evidence and because the
  same file gets this right five lines' worth of functions away.
- **Fix risk:** none.


**FIXED 2026-09-09:** out added to the local declaration in plan_record_checksum

### F68 — `checks.gate-mutants` is executed by nothing: the only CI workflow is `plan-gate`, and the only `nix flake check` in the repo passes `--no-build`

- **File:** `modules/flake/gate-checks.nix:29-32`,
  `docs/skills/workflow/scripts/verify-ladder:195`,
  `.github/workflows/` (contains `plan-gate.yml` only),
  `docs/procedures/testing-changes.md:254-256`.
- **Severity:** INFO
- **Confidence:** CONFIRMED (`ls .github/workflows`; the only `nix flake
  check` call site in the tree is `verify-ladder:195`, with `--no-build`)
- **Axis:** needed-used
- **Reachability:** anyone relying on the sentence "it runs as
  `checks.gate-mutants` under `nix flake check`" to believe the mutation
  catalogue is enforced. `#D2` chose `gate-checks.nix` over a GitHub Actions
  step on the reasoning that "a check runs on any machine, in any CI, and
  locally". Today no CI runs `nix flake check` at all, and the one local
  caller documents that `--no-build` "does not build checks" — the note
  `verify-ladder:56-60` makes about `gate-tests`, which is why `gate-tests`
  is *also* called directly. `gate-mutants` has no such direct call by
  design, so the enforcement is a human remembering.
- **Rule:** n/a
- **Finding:** the flake check is not wrong, it is unreached, and the doc
  reads as though it were a gate. The same is true of `checks.gate-tests` as
  a *check* — what actually runs before a commit is the direct call. Either
  a workflow runs `nix flake check` (no `--no-build`) on PRs, or the docs
  should say plainly that the slow tier is manual.
- **Fix risk:** low for the doc half. Running `nix flake check` in CI pulls
  in every other check in `checks.nix`, including the VM tests, which cost
  minutes each — so it would need `nix build .#checks.<system>.gate-mutants`
  specifically, not a blanket `nix flake check`.

---

**Second security pass on this branch, 2026-09-09** — checked and clean, for
the record of what was covered. Reviewed the whole of `cfe6106..HEAD` with
emphasis on `99aa7ef..HEAD` and `5d05887..HEAD`. Verified directly, and
found correct: no file under `docs/plans/done/` or `docs/plans/rejected/`
was touched after `5d05887`, and `sha256sum -c docs/plans/.checksums`
reports 50 of 50 `OK` with 50 entries against 50 `done/` files and an empty
`rejected/`. `plan_record_checksum`'s five steps are each checked, both
temporaries are removed on every failure path, and the shrink guard accepts
every legitimate shape (first freeze grows by one, re-record stays equal) —
the one refusal it gets wrong is `#F65`. All five `plan_require_not_frozen`
call sites (`plan-move:21`, `plan-reject:22`, `plan-decide:23`,
`plan-resolve:28`, `plan-tick:19`) pass `"$root" "$rel"` in that order, with
`rel` from `plan_locate`, i.e. repo-root-relative — no site passes a full
path or transposes the arguments; `plan-carry` is the one that passes
nothing, which is `#F62`. `plan_manifest_problem`'s coverage `awk` was
attacked with the crafted paths the brief names and holds: it splits on the
*first* two-space run, so a filename containing two spaces still matches;
`find` is rooted at the two directories so no `./` prefix can appear on
either side; a missing `rejected/` is handled (`find` writes to the
suppressed stderr and still lists `done/`); a filename with a newline or a
backslash fails *closed*, reported as uncovered, because `sha256sum` escapes
it in the manifest and `find` does not. An unreadable manifest makes the
`getline` loop exit with an empty `have`, i.e. everything uncovered — also
closed. The removal of the "entry naming a deleted file" check is safe and
measured: GNU `sha256sum -c` prints `FAILED open or read` (plus a stderr
warning) for a missing file, `Is a directory` for a directory, and `no
properly formatted checksum lines found` for an empty or garbage manifest —
all three land in `bad` through the `2>&1 | grep -v ': OK$'`, so a separate
check genuinely could never fire first. The `#F59` correction is confirmed
too: `sha256sum -c` on an empty file exits 1, not 0. In `.githooks/pre-commit`
the `ls_rc` case analysis is sound for the deletion it was written for, and
a manifest staged as a *rename* also blocks (pathspec limiting precedes
rename detection, so the source still reports `D`) — the three shapes that
do not block are `#F63`. `scripts/gate-tests` runs green at 122/0 with 4
recorded residues in ~1.7s and writes nothing outside `$TMPDIR`; its new
freeze-manifest section asserts what it claims, including the failing-`sort`
PATH shim and a trimmed-manifest fixture that first proves the trimmed
manifest still verifies. Every fixture in this review was built under
`~/.cache/`, outside every checkout; no `secrets/*` file was read, decrypted
or referenced, and nothing in the range touches `.sops.yaml`, a
`sops.secrets.*` reference, a firewall rule, a systemd unit or a service
account, so `docs/hardening.md`'s host-facing rules have no surface here.

_security finished 2026-09-09T17:50:14Z (code c6ffc5dbb5dfa536) -- see Findings above._

**CORRECTED 2026-09-09:** the first fix for this was dead code, and pushing
it is what showed that. `changed_files` in `.githooks/pre-push` comes from a
diff pathspec-limited to `hosts/ modules/ files/ flake.nix flake.lock` --
what decides the host build set -- so a change to a gate script never
appears in it, and the hook returns at the empty-`changed_files` check
before reaching the block anyway. It now takes its own checked diff over
`scripts/ docs/skills/ .githooks/` and runs above that early return.
Verified by feeding the hook a real ref range on stdin and watching it
build.

**FIXED 2026-09-09:** the slow tier has an actual runner now. .githooks/pre-push builds checks.gate-mutants whenever the pushed range touches scripts/, docs/skills/ or .githooks/ -- beside a host build 17s is nothing, before every commit it would be too much, and verify-ladder's nix flake check passes --no-build so it never built any check. D2's answer chose the flake over a workflow file; this is what makes that choice actually run

### F69 — `lost` is not declared `local` in `plan_record_checksum`, reintroducing F67's exact defect in the same function that F67 named

- **File:** `docs/skills/plan/scripts/lib.sh:507` (`local root="$1" rel sum
  checksums tmp out` — `lost` missing), assigned at `:546`.
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** identical to F67's — `scripts/gate-tests` sources
  `lib.sh` into its own top-level shell, so a case that ever calls
  `plan_record_checksum` outside the `ev()`/`mf()` subshells would have a
  global `lost` written under it. No live caller today.
- **Rule:** n/a
- **Finding:** the F65 fix replaced the line-count guard with a
  set-of-paths guard and introduced a new variable without adding it to the
  `local` list — the same one-word omission F67 recorded, in the same
  declaration, one commit after that declaration was edited to fix it.
- **Fix risk:** none; add `lost` to the existing `local` line.


**FIXED 2026-09-09:** lost added to plan_record_checksum's local declaration. F67's exact defect in the same line one commit later, because F65's set-of-paths guard introduced the variable without extending the declaration

### F70 — four docs describing the freeze manifest and `pre-push` went stale inside this range: one asserted the coverage gap F60 had just closed, three predate `pre-push`'s new gate-mutants responsibility

- **File:** `docs/procedures/testing-changes.md:169-199,247-260`,
  `docs/GIT_WORKFLOW.md:63-70`, `docs/skills/workflow/SKILL.md:33-41`,
  `docs/skills/plan/reference.md:244-249`.
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** `testing-changes.md` is the doc `verify-ladder`'s own
  failures point a reader at, and it stated the opposite of the shipped
  behaviour: "the entries present, not the corpus, so a *dropped* entry
  still passes". `plan_manifest_problem` has refused an uncovered
  `done/`/`rejected/` plan since F60, and `gate-mutants`'
  `lib/manifest-problem-ignores-uncovered` entry proves it.
- **Rule:** n/a
- **Finding:** fixed directly, docs-only, no script touched. (1) the
  `verify-ladder` bullet now names `plan_manifest_problem` and its three
  properties instead of claiming a dropped entry passes; (2) the
  `pre-commit` bullet now lists the three manifest guards F63 added
  (staged deletion, non-regular file, dropped entry); (3) the `pre-push`
  bullet in both `testing-changes.md` and `GIT_WORKFLOW.md` records the
  second, separate diff over `scripts/ docs/skills/ .githooks/` that
  builds `checks.gate-mutants`; (4) the `gate-mutants` bullet no longer
  says `nix flake check` is the only thing that runs it; (5)
  `workflow/SKILL.md`'s freeze-manifest parenthetical gained the
  no-entry-at-all case; (6) the `gate-tests` coverage list names all six
  plan writers, so no reader can carry away the retired "five writers"
  count. Counts re-measured rather than trusted: `gate-tests` 128 passed
  in 2.03s (doc said 128 / 2.1s, kept), `gate-mutants` 56 caught in 15.6s
  across 16 jobs (doc said ~17s, corrected).
- **Fix risk:** none; `docs/**/*.md` is outside `plan_code_fingerprint`.


**FIXED 2026-09-09:** the four stale docs were corrected in the same pass that found them: testing-changes.md's verify-ladder bullet asserted the coverage gap F60 had already closed, and three more predated pre-push's gate-mutants responsibility

### F71 — `docs/agents/docs-updater.md` and `docs/agents/security.md` still tell agents to test a plan's self-declared `frozen:` field, which F56/F61 established is not the authority

- **File:** `docs/agents/docs-updater.md:16`, `docs/agents/security.md:49`.
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** both instruct a subagent to decide "is this plan
  frozen?" from `frozen: true` in the frontmatter. Every script now asks
  `docs/plans/.checksums` instead, precisely because the field is
  self-declared — F61 showed that trusting it let a plan buy leniency from
  `plan-gate` by writing one line about itself. An agent following these
  briefs literally would read a hand-set field and reach the opposite
  answer from every gate.
- **Rule:** n/a
- **Finding:** not fixed here, deliberately, and this is the ambiguity
  worth surfacing rather than resolving unilaterally: neither file is
  touched by this branch's diff, and `docs/agents/*` is inside
  `plan_code_fingerprint`'s covered set, so editing them invalidates every
  review stamp and restarts the loop this pass is trying to converge. The
  correct wording is "recorded in `docs/plans/.checksums`", or simply
  "under `docs/plans/{done,rejected}/`", in both places.
- **Fix risk:** none to behaviour; the cost is one more review cycle.


**FIXED 2026-09-09:** both agent briefs now say frozen means recorded in docs/plans/.checksums, and name the frozen: field as the thing a plan can write about itself. Fixed rather than deferred: these briefs are what the review subagents read, so leaving them would have every future pass reach the opposite answer from every gate -- and docs/agents/* being inside the fingerprint is a reason to sequence the edit, not to leave it wrong

### F72 — `.githooks/pre-commit`'s F63 comment narrates the session rather than the mechanism

- **File:** `.githooks/pre-commit:52-60`.
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** n/a — comment only.
- **Rule:** `docs/style-guide.md`, "Inline comments" and "Why context: the
  plan file, not comments".
- **Finding:** the sentence moved here verbatim from
  `.githooks/pre-commit:57-58` is a report on the work, not on the code:
  "That is the third time on this branch a fix for a fail-open read was
  itself one, so it is spelled out here". The rest of that block is
  legitimate mechanics — `rev-parse --verify --quiet` answers 1 for an
  unborn HEAD and 128 when git itself fails, and the two reads after it
  are plain assignments `set -e` covers — and should stay. Not edited:
  `.githooks/*` is inside `plan_code_fingerprint`, so a style-only comment
  edit restarts the review loop, and the style-guide rule is not worth
  that on this pass. Drop the sentence the next time that file is opened
  for a real reason.
- **Fix risk:** none.

_docs-updater finished 2026-09-09T18:15:55Z (code 5cf9e1bed22ecb09) -- see Findings above._

**FIXED 2026-09-09:** the session-narrative sentence moved out of .githooks/pre-commit; the rev-parse rc mechanics it introduced stay, because those explain the code

### F73 — `.githooks/pre-push` swallows `git merge-base`'s status, so a range it cannot resolve collapses to a working-tree diff and *both* the host build and the new gate-mutants build silently skip

- **File:** `.githooks/pre-push:18-19` (the fallback), `:32-35` and `:42-45`
  (the two checked diffs that consume it), `:59-66` (the gate block).
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED — reproduced twice in scratch repos with `nix`
  and `nixos-rebuild` stubbed on `PATH`.
- **Axis:** hardening
- **Reachability:** anyone pushing a branch whose merge-base with
  `origin/master` cannot be computed. Two no-sabotage paths: an orphan or
  otherwise unrelated-history branch (`merge-base` exits 1 with no output),
  and any clone or worktree where the ref `origin/master` is simply absent
  (remote renamed, `--single-branch` of another branch, a second remote, a
  fetch that has not happened yet). Neither needs `--no-verify` and neither
  prints anything.
- **Rule:** new-rule candidate. It is the same fail-open class this range
  closed at every other diff call site — and `.githooks/pre-push:28-31`, the
  comment three lines below the defect, asserts it is closed: "an
  unresolvable range read as 'no host config changed' and pushed unbuilt --
  the fail-open this branch closed at every other diff call site".
- **Finding:** `range="$(git merge-base origin/master "$local_sha"
  2>/dev/null || true)..$local_sha"` discards merge-base's exit status. When
  it produces nothing the guard on the next line rewrites `range` to the bare
  `$local_sha`, and `git diff --name-only <sha> -- <paths>` is not a range at
  all — it is *working tree vs that commit*, which on a clean checkout is the
  empty set and exits 0. Both diffs then succeed with no output, so neither
  `if !` fires, `gate_files` is empty so the mutation catalogue is not built,
  `changed_files` is empty so the hook returns at `:68-70`, and the push is
  accepted. Measured: a new branch adding both `hosts/h/c.nix` and
  `scripts/gate-tests` gave `hook rc=0` with the `nix` and `nixos-rebuild`
  stubs never invoked, in both the missing-`origin/master` case and the
  orphan-branch case; the same fixture with `origin/master` present ran
  `build --no-link .#checks.x86_64-linux.gate-mutants` and `build --flake
  .#h` as intended. The comment at `:17` also mis-describes the fallback as
  diffing "against empty tree if master itself", which `git diff <sha>` does
  not do.
- **Fix risk:** checking the status and blocking converts today's silent pass
  into a hard refusal for anyone whose `origin/master` ref is missing, which
  is a real local state (a fresh worktree before the first fetch), so the fix
  needs a message that says which ref is missing rather than a bare BLOCKED.
  If the intended empty-tree fallback is wanted it has to be spelled
  explicitly (`git diff --name-only $(git hash-object -t tree /dev/null)
  <sha>`), not by dropping the left-hand side. Test with the stub-`PATH`
  fixture above: missing ref, orphan branch, and the working positive
  control, since only the third passes today for the right reason.


**FIXED 2026-09-09:** pre-push checks git merge-base's status instead of swallowing it with || true. It discriminates: 1 means no common ancestor and falls back to the empty tree, so the whole branch is examined, and anything else blocks. The defect predated the gate-mutants block and disabled it too -- a collapsed range makes both diffs working-tree diffs, empty on a clean checkout

### F74 — the gate-mutants trigger pathspec omits the two files that decide whether `checks.gate-mutants` runs anything

- **File:** `.githooks/pre-push:42` (`scripts/ docs/skills/ .githooks/`),
  `tests/gate-script-check.nix:37-48`, `modules/flake/gate-checks.nix:23-33`,
  `docs/skills/workflow/scripts/verify-ladder:195` and `:205`.
- **Severity:** LOW
- **Confidence:** CONFIRMED — pathspecs read directly; `nix flake check
  --help` on the pinned nix confirms `--no-build` is "Do not build checks";
  `nix eval .#checks.x86_64-linux.gate-mutants.drvPath` resolves, so the
  check exists and only `pre-push` ever builds it.
- **Axis:** needed-used
- **Reachability:** an agent or contributor editing the check *plumbing*
  rather than a gate script. `tests/gate-script-check.nix` is the file whose
  `bash ${script}` line is the entire execution of the catalogue; it appears
  in neither pre-push pathspec (`hosts/ modules/ files/ flake.nix flake.lock`
  for the host build, `scripts/ docs/skills/ .githooks/` for the gate build)
  and in neither of verify-ladder's (`changed_all` uses the host set), so a
  commit that changes it to `bash ${script} || true` builds nothing, runs
  nothing, and passes every gate — `nix flake check --no-build` evaluates the
  derivation and stops. Once landed, the next gate-touching push runs the
  neutered check and reports green. `modules/flake/gate-checks.nix` is
  half-covered: `modules/` triggers full host builds, which never build a
  flake check, so repointing `gate-mutants` at `scripts/gate-tests` has the
  same property.
- **Rule:** n/a — same family as `#F68`, which established that a check
  nothing builds is not a gate.
- **Finding:** the trigger set for the slow tier names the *scripts* and not
  the two files that decide what the slow tier executes, so the one thing
  that runs the catalogue can be switched off without ever running it.
- **Fix risk:** low. Adding `tests/` and `modules/flake/` to the gate
  pathspec costs the ~16s build on pushes that touch them; `modules/` already
  triggers a full host build, so the marginal cost there is nil. Check
  nothing else under `tests/` is edited often enough to make the hook
  annoying — `tests/` currently holds VM checks that already gate elsewhere.


**FIXED 2026-09-09:** the gate pathspec gained tests/ and modules/flake/, where the check derivation and its registration live

### F75 — the runner of the mutation catalogue is the one gate with no `gate-tests` case and no `gate-mutants` entry

- **File:** `.githooks/pre-push:59-66`; `scripts/gate-tests` (no occurrence
  of `pre-push`); `scripts/gate-mutants:51` (`TREE_PATHS`) and `:123-127`
  (the target list).
- **Severity:** LOW
- **Confidence:** CONFIRMED — `grep -n pre-push scripts/gate-tests
  scripts/gate-mutants` returns nothing; the suite's own run reports 128
  assertions, none naming `pre-push`.
- **Axis:** needed-used
- **Reachability:** anyone editing `.githooks/pre-push`, including a future
  pass of this same loop. Every other enforcement point in this system —
  `plan-gate`, `required-agents`, `plan-citations`, `plan-lint`,
  `plan-freeze`, `plan-repair`, the six plan writers, `.githooks/pre-commit`
  — has both a failure-mode case and a mutant. `pre-push` has neither, so
  rewriting `if [[ -n "$gate_files" ]]` to `if false` leaves the suite at 128
  passed and the catalogue at 0 escapes, while `checks.gate-mutants` returns
  to being run by nothing.
- **Rule:** n/a — new-rule candidate: "the runner of a gate is part of the
  gate", the same reasoning `#F68` used to give the catalogue a runner at
  all.
- **Finding:** `.githooks` is inside `TREE_PATHS`, so the mutation harness
  copies `pre-push` and would fingerprint it, but no catalogue entry mutates
  it and no test invokes it. The gate that decides whether the mutation
  catalogue runs is the only one whose own failure modes are unmeasured.
- **Fix risk:** a test has to feed the hook push refs on stdin and stub `nix`
  and `nixos-rebuild` on `PATH` (both were straightforward in a scratch repo
  while writing `#F73`); a sabotage sweep over it needs the same stubs, or it
  measures nix rather than git.


**FIXED 2026-09-09:** gate-tests now covers pre-push, with nix and nixos-rebuild stubbed onto PATH and the assertion being whether they were reached: a positive control over an ordinary range, and the F73 case over a range whose merge base cannot be computed. gate-mutants carries the merge-base mutant

### F76 — of the three manifest guards `#F63` produced, the drop check is the one with neither a test nor a mutant

- **File:** `.githooks/pre-commit:50-86` (the guard),
  `scripts/gate-tests:1296-1316` (cases for its two siblings),
  `scripts/gate-mutants:406-420` (mutants for its two siblings).
- **Severity:** INFO
- **Confidence:** CONFIRMED — no string from the guard's message ("drops
  entries", "restore the lines") appears anywhere under `scripts/`; the two
  siblings are asserted by name.
- **Axis:** needed-used
- **Reachability:** anyone editing `.githooks/pre-commit`. The guard itself
  is correct — verified in a scratch repo across five cases: dropping an
  entry for a live plan blocks, dropping one whose plan is deleted in the
  same commit passes, truncating the manifest blocks and names every plan,
  tampering with a covered plan still blocks on the frozen check, and a
  `git mv` of a frozen plan with a matching manifest rewrite blocks (the
  conservative direction). So this is coverage, not correctness.
- **Rule:** n/a.
- **Finding:** `#F63` named three ways to neuter the manifest in the same
  commit — emptying it, dropping one entry, replacing it with a symlink. Two
  of the three fixes got a `gate-tests` case *and* a `gate-mutants` entry;
  the drop check, which is the largest and the only one with non-trivial awk,
  got neither. The sabotage sweep does exercise the block's four new git
  calls (and `sabotage_sweep` fails when `base_count > max`, so the block
  cannot have outgrown its budget of 30 unnoticed), but nothing asserts the
  decision the awk makes.
- **Fix risk:** none. The case is the same six lines as the symlink one
  beside it: `mreset`, drop a line from the staged manifest, `expect_fail
  ... "drops entries"`, plus the mirror case that a drop paired with a staged
  deletion passes.


**FIXED 2026-09-09:** the drop check has a case and a mutant now, matching its two siblings

### F77 — `.githooks/pre-commit`'s frozen check is the last manifest reader keyed on `$2`, so a frozen plan whose path contains a space is skipped by the only always-on enforcement

- **File:** `.githooks/pre-commit:116` (`awk -v f="$f" '$2==f{print $1}'`)
  against `.githooks/pre-commit:74-75`,
  `docs/skills/plan/scripts/lib.sh:210` (`plan_manifest_frozen`), `:247`
  (`plan_manifest_problem`), `:528` and `:547` (`plan_record_checksum`).
- **Severity:** LOW
- **Confidence:** CONFIRMED — demonstrated end to end in a scratch repo: a
  frozen plan named `docs/plans/done/a b.md`, recorded in the manifest and
  reported `FROZEN` by `plan_manifest_frozen`, was tampered with, staged, and
  `.githooks/pre-commit` exited 0.
- **Axis:** hardening
- **Reachability:** any plan file whose name contains a space and is later
  frozen. `plan-new` slugifies, but nothing forces a plan to be created by
  `plan-new` — `plan_locate` accepts any `docs/plans/*/*.md`, and
  `plan-freeze`/`plan-move ... done` will record whatever path it is given.
  After that, the manifest reader that every *script* consults calls the file
  frozen and refuses, while the hook that is the one unconditional gate on
  every commit by every tool silently skips it: `$2` is the first
  whitespace-delimited token of the path, so it never equals the full name
  and `recorded` comes back empty, which line 117 treats as "not a frozen
  file plan-freeze knows about". The same line skips any entry whose hash
  field is empty (see `#F78`).
- **Rule:** n/a — it is `#F20`'s own rule, "exact match on the path field,
  not a substring/field of the line", applied to `plan_manifest_frozen`,
  `plan_record_checksum`, `plan_manifest_problem`, `plan-repair` and this
  same hook's new drop guard, and not applied here.
- **Finding:** this range left three different parsers of one file. Two use
  `index($0, "  ")` and agree; the third decides whether a commit is allowed
  and does not. Under `core.quotePath=false` a path with a space is emitted
  unquoted by `git diff --name-only`, so nothing upstream normalises it away.
- **Fix risk:** low. Rewriting `:116` in the `index($0, "  ")` form the other
  readers use is behaviour-identical for all 50 current entries (all verify
  before and would after), and it closes the empty-hash skip at the same
  time. Worth a `gate-tests` case using a fixture filename with a space, or
  the change certifies itself.


**FIXED 2026-09-09:** pre-commit looks the manifest entry up by exact path field, like plan_manifest_frozen and the guard above it. The fixture gained a frozen plan whose name contains a space, which is what awk's default field splitting could not match

### F78 — `plan_checksum` swallows `sha256sum`'s failure, so `plan_record_checksum`'s first step is the one step it does not check

- **File:** `docs/skills/plan/scripts/lib.sh:499` (`plan_checksum`), `:507-509`
  (the unchecked call), `:520-526` (the docblock claiming "Every step
  checked").
- **Severity:** LOW
- **Confidence:** CONFIRMED for the mechanics: `s="$(plan_checksum
  /nonexistent/x.md 2>/dev/null)"` measured `rc=0 val=[]`, because the
  pipeline's status is `awk`'s; no plan script sets `-e` or `pipefail`
  (checked across all 20 under `docs/skills/*/scripts/`), so nothing upstream
  catches it either. The trigger is an I/O condition rather than an
  adversary.
- **Axis:** hardening
- **Reachability:** not adversary-driven — the plan file unreadable or gone
  at the instant of the freeze (a concurrent `plan-move`, ENOSPC, a mode
  change between `plan_set_field` and here). What follows is the part worth
  recording: `printf '%s  %s\n' "" "$rel"` writes a hash-less entry `␣␣<path>`,
  and that entry *satisfies* `plan_manifest_frozen` (`index` finds the
  separator at 1, the path field matches) and *satisfies*
  `plan_manifest_problem`'s new coverage arm (same parse), so the plan reads
  as covered and frozen everywhere. `.githooks/pre-commit:116` skips it
  (`$2` is empty), so the commit gate does not protect that plan. The one
  thing that does catch it is `sha256sum -c`'s "WARNING: 1 line is improperly
  formatted", which `plan_manifest_problem` captures via `2>&1` and
  `verify-ladder` blocks on — measured, including that a manifest of one
  hash-less line exits 1 with "no properly formatted checksum lines found".
  So the net today is: verify-ladder blocks, pre-commit does not, and the
  loss guard cannot see it because no path was lost.
- **Rule:** n/a — the same "checked, not swallowed" rule `#F54`, `#F47` and
  `#F48` applied to every other step of this function.
- **Finding:** the function whose docblock is "Every step checked" does not
  check the step that produces the value the manifest exists to record.
- **Fix risk:** small but not zero-effort: `sum="$(plan_checksum ...)" ||
  plan_die` does not work as written, because `plan_checksum`'s
  `sha256sum | awk` already returns 0. The fix is in `plan_checksum` —
  drop the pipe (`read`-and-cut, or `set -o pipefail` inside a subshell) —
  and every other caller of `plan_checksum` (`plan-repair:34`) inherits the
  new failure mode, so check that a missing file there still produces the
  intended "does not match its recorded checksum" refusal rather than a die
  with a worse message.

**Checked and clean (security, third pass, 2026-09-09).** Reviewed the whole
`cfe6106..b19b424` range with attention to what landed after the second pass
(`99aa7ef..HEAD`). Verified independently, not from the diff's own claims:
all 50 `docs/plans/.checksums` entries verify (`50 OK`, 0 not-OK), `done/`
holds exactly 50 `.md` files and `rejected/` 0, so
`plan_manifest_problem`'s coverage arm has nothing uncovered; every
`docs/plans/done/` file touched in the range is touched by exactly the
8-line `plan-repair` insertion with zero deleted lines, and no frozen plan
changed at all since `99aa7ef`; `scripts/gate-tests` runs 128 passed / 0
failed / 4 recorded residues, matching what `testing-changes.md` now claims;
`plan-citations` reports 448 citations resolving; the worktree is clean after
both runs. `nix eval .#checks.x86_64-linux.gate-mutants.drvPath` resolves,
and the pinned `nix flake check --help` confirms `--no-build` is documented
as "Do not build checks", so `verify-ladder`'s claim that its flake-check
step does not run the suite is correct and `pre-push` really is the only
runner. Examined and found sound: `.githooks/pre-commit`'s three manifest
guards, exercised against five hand-built scratch-repo cases (drop-with-live-
plan blocks, drop-with-staged-deletion passes, truncation blocks naming every
plan, symlink mode blocks, tampered covered plan blocks) — the guard logic is
right, only its test coverage is not (`#F76`); the `head_rc` discrimination,
which correctly separates unborn HEAD (1) from git failure (>1);
`plan_record_checksum` end to end, whose `local` list is now complete, whose
temporaries are same-directory so the `mv` is a real rename, whose mode is
carried by `chmod --reference` with a 644 fallback, and whose loss guard is
correctly keyed on `FILENAME` rather than `NR == FNR` and correctly compares
*paths* rather than line counts (a duplicated path collapsing is not refused,
verified by the suite's own case); `plan_manifest_problem`'s coverage `find`
+ `awk`, including that a `cd` failure cannot reach it (the `-s` test above
would have fired first), that an unreadable manifest makes `getline` return
-1 and reports every plan uncovered rather than none, and that the removed
reverse-direction check really is unreachable because `sha256sum -c` reports
a missing file as `FAILED open or read`; `plan-carry`'s new
`plan_require_not_frozen` call, placed after `plan_locate` and before the
first write; `plan-gate` and `subagent-stamp` switching to
`plan_manifest_frozen`, which is right in both directions — in `plan-gate`
"frozen" *relaxes* the stamp requirement, so reading a self-declared field
there was a one-line self-exemption. On the two agent briefs I was asked to
judge: `docs/agents/security.md` and `docs/agents/docs-updater.md` are
correct as changed — the manifest is what `plan-gate`, `subagent-stamp`,
`plan_require_not_frozen`'s first arm, `plan-repair` and `.githooks/pre-commit`
all consult, and both cite the plan by bare filename so `plan-citations`
stays green. One narrowing to be aware of rather than a defect:
`plan_require_not_frozen` refuses on the manifest entry *or* the `frozen:`
field, so the briefs now state a rule slightly narrower than the tooling
enforces. Nothing diverges today — no `todo/` or `in-progress/` plan declares
`frozen: true`, and all 50 `done/` plans both declare it and have an entry —
so the two answers agree on every current file. No secret was decrypted or
read, no file outside this plan was written, and no host was rebuilt.

_security finished 2026-09-09T18:28:51Z (code 330be557084f24d8) -- see Findings above._

**FIXED 2026-09-09:** plan_checksum checks sha256sum's status rather than returning awk's, and plan_record_checksum refuses rather than writing an entry with no hash

### F79 — every doc claim about `pre-push`'s trigger set and both harness counts went stale again inside this range, and nothing yet said `plan_record_checksum` can refuse

- **File:** `docs/procedures/testing-changes.md:186-196,222-226,244,274-278`,
  `docs/GIT_WORKFLOW.md:70-72`, `docs/skills/plan/reference.md:246-249`.
- **Severity:** LOW
- **Confidence:** CONFIRMED — every number re-measured in this pass rather
  than read off the diff: `./scripts/gate-tests` prints `136 passed, 0
  failed, 4 recorded residue(s)` in 2.11s real; `./scripts/gate-mutants`
  prints `60 caught, 0 escaped, 0 inert, 0 broken, 0 unknown` in 17.06s
  real, `nproc` 16.
- **Axis:** documentation
- **Reachability:** `testing-changes.md` is the doc `verify-ladder` and
  `pre-push` point a reader at when they block, and it named a trigger set
  two paths short of the one `.githooks/pre-push:63` actually uses. A
  reader trusting it would conclude that editing only
  `tests/gate-script-check.nix` or `modules/flake/gate-checks.nix` — the
  check derivation and its registration, i.e. exactly the files that decide
  *how* the catalogue runs — skips the mutation build, which `#F74` closed.
  The same doc gave 128 assertions against a suite that runs 136, and 56
  mutants against a catalogue of 60.
- **Rule:** n/a
- **Finding:** fixed directly, docs-only, no script touched. (1) both
  `pre-push` bullets (`testing-changes.md`, `GIT_WORKFLOW.md`) now name all
  five trigger paths and say why the last two are in the set, citing
  `#F74`; (2) `testing-changes.md`'s `pre-push` bullet gained the
  new-branch case `#F73` created — the hook takes the merge base with
  `origin/master` and refuses the push outright rather than deciding either
  build set from a merge-base it could not compute, which is a `BLOCKED`
  message a reader can now hit and previously could not have looked up;
  (3) the `gate-mutants` bullet no longer restates the trigger paths in its
  own words, which is how they drifted — it points at the `pre-push` bullet
  above it, so there is one spelling of that set in the doc; (4) counts
  corrected to 136 assertions / 60 entries / 17.0s; (5) the `gate-tests`
  coverage list gained `.githooks/pre-push`'s choice of what to build (a
  new section of three assertions) and `lib.sh`'s checksum helper, both of
  which the suite now covers and the list did not name; (6)
  `reference.md`'s manifest-guard paragraph records that
  `plan_record_checksum` also refuses to record an entry for a file it
  cannot hash — before `#F78` it could not fail, and the paragraph read as
  though it still could not.
- **Fix risk:** none; `docs/**/*.md` is outside `plan_code_fingerprint`, so
  this pass costs no review stamp.


**FIXED 2026-09-09:** the four stale docs were corrected in the pass that found them: pre-push's trigger set was two paths short, its new-branch refusal was undocumented, gate-mutants' bullet restated the trigger paths in its own words rather than pointing at the one spelling, and both counts were stale

### F80 — `verify-ladder`'s gate-tests timing note and `gate-mutants`' header both predate the runners they describe, and neither is worth a fingerprint cycle on its own

- **File:** `docs/skills/workflow/scripts/verify-ladder:52`,
  `scripts/gate-mutants:36-37`.
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** neither misleads a reader into a wrong action, which is
  why this is a finding rather than an edit. `verify-ladder:52` says the
  suite costs `~1.7s`; it now costs 2.11s, measured, and
  `testing-changes.md` already carries the accurate figure with the
  explicit note that it is knowingly over the one-second budget.
  `gate-mutants:36-37` says the catalogue "stays out of verify-ladder's
  pre-commit path and runs as `checks.gate-mutants` under `nix flake
  check`" — true, but written before `#F68` made `.githooks/pre-push` the
  thing that actually builds that check, so the header names the
  registration and not the runner.
- **Rule:** `docs/style-guide.md`, "Inline comments".
- **Finding:** not fixed here, deliberately. Both files are inside
  `plan_code_fingerprint`'s covered set (`*/scripts/*`, `scripts/*`), so
  either edit invalidates every review stamp and restarts a loop that is
  otherwise converging, and neither claim is load-bearing: one is an
  approximate cost note off by 0.4s, the other is incomplete rather than
  wrong. Fold both into the next commit that opens those files for a real
  reason — `~1.7s` to `~2.1s`, and one clause naming `pre-push` as the
  runner.
- **Fix risk:** none to behaviour; the cost is one more review cycle, which
  is the whole reason to defer.


**FIXED 2026-09-09:** fixed rather than deferred: plan-gate blocks on unresolved findings as well as on stale stamps, so deferring one is not available without the user's ACCEPTED sign-off. verify-ladder's cost note is 2.1s, and gate-mutants' header now names .githooks/pre-push as what builds it rather than only the registration

### F81 — `docs/agents/docs-updater.md`'s rubric still glosses "frozen" as `docs/plans/done/`, which is the gloss `#F71` corrected 86 lines above it

- **File:** `docs/agents/docs-updater.md:102` (rubric), against `:16-19`
  (the same file's own, correct, statement).
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** `#F71` fixed the brief's step 2 to say frozen means
  recorded in `docs/plans/.checksums`; the rubric at the end of the same
  file still says "a frozen (`docs/plans/done/`) plan file". `plan-reject`
  freezes into `docs/plans/rejected/` and records a manifest entry there
  the same way, so an agent reading only the rubric could conclude a
  `rejected/` plan is fair game. The consequence is bounded — the writer
  guards and `.githooks/pre-commit` both refuse on the manifest entry, so
  the attempt fails at the gate rather than succeeding — which is why this
  is INFO and not a defect.
- **Rule:** n/a
- **Finding:** not fixed here. `docs/agents/*` is inside
  `plan_code_fingerprint`, and this is one parenthetical that contradicts
  nothing a gate enforces, in a file whose authoritative sentence is
  already correct. The wording, when that file is next opened: "a frozen
  plan file (one with an entry in `docs/plans/.checksums`)".
- **Fix risk:** none to behaviour; the cost is one more review cycle.

_docs-updater finished — see Findings above._

_docs-updater finished 2026-09-09T18:39:29Z (code be8abf6465e53739) -- see Findings above._

**FIXED 2026-09-09:** the rubric gloss now says frozen means recorded in docs/plans/.checksums, which covers rejected/ exactly as it covers done/

---
slug: revise-the-plan-file-schema-state-first-four-frontmatter-fields
created: 2026-09-07
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
superseded_by:
---

# revise the plan-file schema: State first, four frontmatter fields, defects become F

## State

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
- **51 non-frozen plans migrated** — four keys added, `## State` moved
  above `## Original plan`, each netting exactly +4 lines, which is what
  says no file lost content. The 52nd changed file is this plan, which
  `plan-new` generated in the new shape. The 50 frozen ones are untouched
  by construction, and `sha256sum -c` still passes on all of them.
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

`gate-tests` grew from 82 assertions to **92**, covering `plan-lint`, the
active-plan marker and the two frontmatter readers; each new case was
observed failing under the mutation that reintroduces its defect. It runs
in about 1.0s against a one-second budget — see `#G8`, which is now the
next thing to do to it, not a later one.

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

Not started: the G-to-F reclassification. Its design is settled in
`#G4`, its first batch is chosen (the file `#D4` names, 42 `G` items),
and nothing has been moved yet.

Verified to rung 3 (ran it locally, output inspected): `verify-ladder`
passes with the lint genuinely running over this plan, `gate-tests` is
90/0/3 and hermetic, `plan-citations` resolves every citation,
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
pass, `gate-tests` is 92/0/3, and `verify-ladder` passes end to end with
the lint genuinely running over this plan.

**One thing blocks the PR, and it is a decision, not work.** `plan-gate`
refuses on a stale `security` stamp, because fixing `#F18`-`#F22` changed
code after `security` last looked. By D7's letter a third pass is owed;
by D7's own recurrence rule this is where sign-off replaces another loop,
since the same shape has now returned eight times and each fix was
confirmed by mutation rather than by re-reading. Either run `security`
once over `git diff 0ca8889..HEAD` and resolve what it finds, or record
the sign-off. Do not self-issue a stamp.

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
- [ ] G-to-F expand for the first batch, the file `#D4` names, with the
      old `### G<N>` left as a resolving pointer
- [ ] migrate the citations of that batch

Contract, only once `plan-citations` reports zero unresolved references
for a batch:

- [ ] drop the pointer headings for migrated batches
- [ ] remaining batches of the 25 non-frozen files with `G` headings


## Decisions (D)


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
`SKILL.md` already states it repo-wide. Measured before proposing it: **60
path-form references exist in the repo today**, a mix of real citations and
ordinary prose paths. Moving the rule would fail all 60, so it needs its own
decision and a pass over them, not a ride-along in a cleanup.

### G8 - gate-tests is now at 0.98s against a one-second budget, with no margin

The harness grew from 82 assertions to 90 covering `plan-lint` and the
active-plan marker, and from 0.81s to 0.98s. `2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#G2`
sets the budget at "under a second", because `verify-ladder` runs this before
every non-trivial commit and a gate people learn to bypass is worse than no
gate.

It is still under. It will not survive the next addition, and the sweep of
`subagent-stamp`, `plan-freeze`/`plan-move` and `.githooks/*` is still owed.
`#G2` already names the remedy — split a fast tier from a slow one rather
than letting the whole thing get skipped — and that split is the next thing
to do to this harness, before more cases go in.

The cost is concentrated in the sabotage sweeps: each runs the gate once for
the baseline and once per git call, so a gate making eight calls costs nine
invocations. `plan-gate` alone is nine.

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
  already measured as failing 60 existing path-form references.


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

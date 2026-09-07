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

**The review loop ran in full, and found seventeen things.** Four
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

`gate-tests` grew from 82 assertions to **90**, covering `plan-lint` and
the active-plan marker; each new case was observed failing under the
mutation that reintroduces its defect. It now runs in 0.98s against a
one-second budget — see `#G8`, which is the next thing to do to it.

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
the schema era are checked where `frozen: false`, and rules that do not —
core frontmatter, status against folder, id sequencing, Progress citations —
are checked everywhere. Corpus failures went 45 to 18, and the single
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

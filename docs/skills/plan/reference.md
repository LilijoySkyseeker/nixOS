# `plan` skill reference

## Filename and frontmatter

`docs/plans/<status>/<YYYY-MM-DD>-<slug>.md`

- `<YYYY-MM-DD>`: creation date, fixed forever -- moving folders never
  touches the filename. Leads the filename (not the slug) so a plain
  directory listing sorts chronologically.
- `<slug>`: kebab-case, chosen once by `plan-new`, never renamed. Capped
  at 70 characters, backing up to the last word boundary rather than
  cutting mid-word.
- Frontmatter mirrors the folder for greppability. The scripts write all of
  it except `blocked_by`, which is hand-set (below):
  ```yaml
  ---
  slug: add-tailnet-build-fleet
  created: 2026-08-27
  status: todo         # mirrors the folder (todo|in-progress|done|rejected)
  frozen: false        # true only once, set by plan-freeze
  kind: task
  priority: normal
  blocked_by:          # comma-separated bare plan filenames
  ---
  ```
  The block above is a shape example, not the vocabulary. What `kind` and
  `priority` may contain, which keys are core and which the map plan's
  `#D4` added, and which vocabulary governs which field, are the
  `PLAN_*` arrays in `docs/skills/plan/scripts/lib.sh` — `plan-lint`
  reads them from there, so read the arrays rather than a prose copy of
  them. `status` is the exception: it has no array, it is checked
  against the folder name.

  There is no `superseded_by` field. It was in the first draft of this
  schema and came out again: nothing writes it until `plan-supersede` and
  `docs/plans/superseded/` exist, and both are unbuilt
  (2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#D5).
  It lands with that tool, not ahead of it. `priority` stays on different
  grounds — its reader is the person triaging the backlog, not a
  script (2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#D5).

- `blocked_by` makes a map's dependency edges readable without parsing
  its Progress prose.

### Which files the schema rules apply to

**The mutable corpus is migrated to the current schema whenever the
schema changes; frozen files are exempt by definition.** "Frozen" means
recorded in `docs/plans/.checksums`, which only `plan-freeze` and
`plan-repair` write and which `.githooks/pre-commit` enforces — not the
file's own `frozen:` field, which a plan could otherwise set about itself
to switch off every rule below. `plan-lint` reports the two disagreeing,
in either direction. A frozen plan cannot be edited, so every rule added
after it froze is one it can never satisfy, and a gate nothing can clear
is what teaches the bypass. `plan-lint` therefore checks the section set,
the section order and the schema fields only on a plan
`docs/plans/.checksums` does not record as frozen, and checks the rules
that do not depend on the era — core frontmatter, status against folder,
id sequencing, Progress citations — everywhere.

**The one exception, and its limits.** `plan-repair` may add `## State`
to an already-frozen plan that has none, and re-record its checksum. That
section is hardcoded, not an argument: it refuses a plan that is not
frozen and refuses one that already has the section, so it can only ever
add a heading nobody wrote — it cannot edit a word of anyone's text. It
exists because 27 `done/` plans were frozen before `## State` existed, and
nothing checked a plan at the moment it stopped being fixable. Both freeze doors now lint
first (`plan-freeze` and `plan-reject`), so the backlog it was written to
clear cannot grow again.

This is the rule to follow at the next schema revision, not a one-off
for this one. See
2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#G1
and `#G5`.

## `kind`, and the two shapes a plan comes in

- **`task`** — the default. One piece of work, its own decisions, its own
  close-out.
- **`map`** — a plan whose Progress items are *other plans*. Children are
  created at the frontier rather than all at once, so the map records
  what is blocked by what and the child records how it was done.

A map child that would break live citations runs as
**expand—contract**: add the new form beside the old one, migrate the
references in batches, and drop a batch's old form only once *every form
the reference is written in* has been checked. `plan-citations` green is
not that test — it resolves `<file>.md#anchor` and is blind to the bare
`` `G<N>` `` a plan uses for its own items, which is the form contracting
breaks
(2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#G4
sets out the three steps). That ordering is the map pattern. It needs no
skill of its own: it is a blocking-edge graph, and `blocked_by` plus
`plan-citations` supply the mechanical half; the prose references are
classified by hand, one at a time.

## `G` is a lesson, `F` is a defect

`D` has `plan-decide` and `F` has `plan-resolve`. `G` has neither, which
is correct for a lesson — something learned, with nothing to drain — and
wrong for a defect, which needs a terminal state. Record a defect as an
`F` even when you found it yourself rather than a review agent.

Plans written before this rule carry defects as `G`. Non-frozen ones
migrate under
2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md;
frozen ones keep `#G` anchors forever, so `#G` stays a valid citation
form permanently and is not being retired.

## Why bare-filename citations

<!-- plan-citations: ignore-start (the example filenames below resolve to nothing on purpose) -->

A plan physically moves between `todo/`/`in-progress/`/`done/` as work
progresses, and a `done/` plan is frozen forever the moment it lands there.
If a citation encoded the folder (`docs/plans/done/foo.md#D1`), then either
every citation would need rewriting on every move, or a `done` file citing
a plan that later moves would go permanently stale with no legal way to
fix it (frozen means frozen). Citing by bare filename instead
(`2026-08-27-foo.md#D1`) sidesteps both problems: the filename never
changes, so the citation is valid the instant it's written and stays valid
forever, regardless of where the file currently sits. Resolving one is a
single `git grep -rl '2026-08-27-foo.md'` or an editor's "quick open."

<!-- plan-citations: ignore-end -->

`plan-citations` enforces this: a plan cited by path is reported, in every
`*.md` and script it scans, not just in frontmatter. Frozen files are
exempt, since they cannot be edited to comply -- it counts them on its OK
line instead
(2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#D3).

## The three decision states, precisely

A `### D<N>` heading records a question that needs the user's actual
input -- never the agent's inference. Exactly three ways to record
progress on it:

- **`answered`** -- the user gave a real, final answer. Terminal: this
  alone satisfies `plan-freeze`.
- **`discussed`** -- talked through, but not yet a final answer. Real
  progress worth keeping, but **does not** let the plan freeze -- prevents
  an open question from quietly riding into an unfixable frozen file.
- **`deferred`** -- explicitly punted for now. Not terminal by itself:
  `plan-freeze` also requires a matching `plan-carry`, which spins the
  item into a new `docs/plans/todo/` plan and appends a `**CARRIED**`
  marker next to the original `**DEFERRED**` one. This guarantees a
  deferred question always resurfaces as live backlog instead of
  disappearing.

`plan-freeze` (and therefore `plan-move ... done`) walks every `### D<N>`
heading and refuses if any one of them isn't `ANSWERED`, or
`DEFERRED`-with-`CARRIED`.

## The three finding states, precisely

A `### F<N>` heading records something `security`/`docs-updater` (or a
fleet-wide `security-audit` finding graduating into this plan, see below)
raised that needs closing out -- never left to just sit there. Exactly
three terminal states exist, recorded via `plan-resolve`, mirroring `D`'s
three states above:

- **`fixed`** -- the underlying issue was actually fixed. Cite the commit
  in the note.
- **`accepted`** -- the user knowingly accepted the risk rather than
  fixing it now. Requires the user's own sign-off, exactly like a `D`'s
  `answered` -- an agent must never accept risk on the user's behalf. The
  note should say who accepted and why, the same shape as
  `docs/accepted-risks.md`'s entries.
- **`moot`** -- no longer applicable (e.g. the code it was about got
  removed for an unrelated reason).

Unlike `D`, there is no non-terminal `discussed`-equivalent and no
`deferred`-then-`carry` path -- a finding that needs more time is not yet
resolved, full stop, and `plan-freeze`/`plan-move ... done` refuse until
every `F` is `fixed`, `accepted`, or `moot`.

### Findings graduating from a fleet-wide security audit

`docs/skills/security-audit/` findings use a different, per-part scheme
(`F-P<n>-NN`) from this skill's per-file `F<N>` -- the two are deliberately
not unified, since fleet findings are numbered per audit part and task
findings are numbered per plan file. When a fleet finding turns into
task-scoped follow-up work, it gets a **fresh, local `F<N>`** in the new
plan -- never renamed to fit the fleet scheme, never given the fleet ID
directly. Cite the origin in the heading so the audit trail survives the
handoff:

```markdown
### F1 -- <title> (from F-P3-07)
```

## Rejecting a plan (abandoned or superseded work)

`docs/plans/rejected/` is a fourth, equally permanent terminal state,
alongside `done/` -- for work that was started and then abandoned, or
superseded by a different approach. `plan-reject <file> "<reason>"`:

- Only accepts a source file currently in `todo/` or `in-progress/`.
- Requires a mandatory reason (cite the superseding plan's bare filename
  in the reason text if there is one), appended as a dated
  `**REJECTED <date>:**` marker -- append-only, same as everything else.
- Does **not** require every decision to be resolved first, unlike
  `plan-move ... done` -- abandoning the work legitimately moots open
  questions rather than obligating them to be answered.
- Runs `plan-lint` first and refuses a malformed plan, exactly like
  `plan-freeze` -- `rejected/` is as permanent, and the file stays
  citeable evidence
  (2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#G10).
- Freezes the file permanently, exactly like `done/` (same checksum
  manifest, same git-level enforcement).

If someone later reconsiders a rejected idea, there's no dedicated
"revive" script -- `plan-new` a fresh plan and cite the old rejected
file's bare filename in its "Original plan" section. That's enough; this
is rare enough not to need its own mechanic.

## Freeze mechanics

`plan-freeze`:
1. Refuses if already frozen, if the file isn't under `docs/plans/done/`,
   if any decision or finding is unresolved (above), if `## State` is
   missing or empty, if `## State` declares no verification rung
   (`Verified to rung <N> ...` -- see
   `docs/procedures/testing-changes.md`, "Declaring the rung"), or if
   `plan-lint` reports the file malformed -- freezing makes a structural
   fault permanent, and `plan-repair` is the only way back
   (2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#D4).
2. Sets `frozen: true`.
3. Records a `sha256sum`-format line (`<hash>  <relpath>`) in
   `docs/plans/.checksums`, which the git-level `pre-commit` hook
   uses to detect any later attempt to modify a frozen file, from any
   tool or human.

The manifest, not the file's own `frozen:` field, is what every script
that edits a plan asks -- `plan-move`, `plan-reject`, `plan-decide`,
`plan-resolve`, `plan-tick` and `plan-carry` all refuse on a manifest
entry, so setting `frozen: false` by hand buys nothing
(2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F56,
2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F62).
`plan-gate` and `subagent-stamp` read it too, rather than the field
(2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F61).

Three things guard the manifest itself. `pre-commit` refuses a commit
that stages its deletion, stages it as anything but a regular file, or
drops an entry for a plan that is not itself being deleted.
`plan_record_checksum` refuses any write that would lose a path, and
refuses to record an entry at all for a file it cannot hash -- an empty
hash would otherwise read as covered and frozen while matching nothing
(2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F78).
`verify-ladder` checks three properties on every pass through
`plan_manifest_problem`: the manifest is non-empty, every entry's file
still hashes to what it records, and every file in `done/` and `rejected/`
has an entry at all -- the last being the one a hash check cannot see,
since dropping an entry leaves what remains verifying perfectly
(2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F60).

## Citeable IDs

`D1, D2, …` decisions; `G1, G2, …` gotchas/lessons; `F1, F2, …` findings
(populated by the `security`/`docs-updater` subagents, or graduated from a
fleet-wide `security-audit` finding -- see above). Sequential per type per
file -- the filename already disambiguates across files, so no global
numbering is needed. `plan-lint <file>` checks sequencing (no gaps, no
duplicates) mechanically.

## Citing a plan from a code comment

Per `docs/style-guide.md`, "Why context: the plan file, not comments":
non-obvious rationale belongs in the plan, and a comment just cites it,
anchored to the specific section, not the whole file --
`# plan: <date>-<slug>.md#D2`. The anchor is what makes the citation point
at one decision/gotcha/finding instead of forcing a reader to search the
whole file; a bare filename with no anchor is an under-citation and should
be tightened when you're the one adding it, though existing bare-filename
citations predate this rule and aren't retrofitted (append-only applies to
history, not just to plan files -- past commits aren't rewritten either).

## Append-only editing

Never delete text in an unfrozen plan. To correct something:
`~~strike it through~~` and add a new line below it explaining why, dated.

## Worked example

<!-- plan-citations: ignore-start (a fictional plan file; its citations resolve to nothing on purpose) -->

```markdown
---
slug: add-tailnet-build-fleet
created: 2026-08-27
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# Add tailnet-wide distributed Nix builders

## State
**2026-08-27, mid-work.** build-worker.nix landed and is live on homelab.
build-fleet.nix is drafted but not yet wired into any host (blocked on
D1, now answered -- next step is applying it). One finding (F1) from the
`security` subagent is still open.

## Original plan
Wire nix.distributedBuilds/buildMachines so homelab/thinkpad/torrent can
build for each other over Tailscale.

## Progress
- [x] build-worker.nix drafted
- [ ] build-fleet.nix drafted (see D1)
- [ ] F1

## Decisions (D)
### D1 -- which host is the primary submitter?
**ANSWERED 2026-08-27:** homelab -- user confirmed always-on matters more
than raw throughput.
### D2 -- should thinkpad ever be a build machine?
**DEFERRED 2026-08-27:** not needed for the initial rollout.
**CARRIED 2026-08-27:** see `2026-08-27-thinkpad-build-machine-followup.md`

## Gotchas (G)
### G1 -- nixos-anywhere --vm-test can't exercise cross-host SSH auth
Needs a real two-host runNixOSTest instead.

## Findings (F)
### F1 -- build-worker.nix's SSH key has no passphrase and is world-readable
**ACCEPTED 2026-08-27:** user accepted -- key is scoped to the tailnet-only
build user with no shell, and the whole fleet is behind Tailscale ACLs
already; a passphrase would break unattended builds for no real gain here.
```

<!-- plan-citations: ignore-end -->

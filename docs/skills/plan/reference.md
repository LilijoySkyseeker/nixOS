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
*residence*: everything under `done/` and `rejected/` is permanently
un-editable, enforced by `.githooks/pre-commit`, `verify-ladder` and
`plan-gate`'s CI range check, with git history as the integrity record
(ADR-0002; the old checksum manifest is gone). The `frozen:` frontmatter
field is an informational marker `plan-freeze` sets on the way in;
`plan-lint` reports it disagreeing with the folder, in either direction.
A frozen plan cannot be edited, so every rule added after it froze is one
it can never satisfy — `plan-lint` therefore checks the section set, the
section order and the schema fields only on non-frozen plans, and checks
the era-independent rules — core frontmatter, status against folder, id
sequencing, Progress citations — everywhere. All of it warns rather than
blocks: the schema is the house convention, not a gate.

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

- **`answered`** -- the user gave a real, final answer. `**ANSWERED**`
  means *the user confirmed*, never "the agent assumed" -- that
  provenance is the marker's whole value.
- **`discussed`** -- talked through, but not yet a final answer. Real
  progress worth keeping.
- **`deferred`** -- explicitly punted for now. Pair it with `plan-carry`,
  which spins the item into a new `docs/plans/todo/` plan and appends a
  `**CARRIED**` marker next to the original `**DEFERRED**` one, so a
  deferred question resurfaces as live backlog instead of disappearing.

`plan-freeze` (and therefore `plan-move ... done`) walks every `### D<N>`
heading and **warns** about any that isn't `ANSWERED` or
`DEFERRED`-with-`CARRIED` -- a nudge to resolve or carry before the file
becomes permanent, not a block (ADR-0002).

## The three finding states, precisely

A `### F<N>` heading records something `security`/`docs-updater` (or a
fleet-wide `security-audit` finding graduating into this plan, see below)
raised. Three terminal states exist, recorded via `plan-resolve`,
mirroring `D`'s states above:

- **`fixed`** -- the underlying issue was actually fixed. Cite the commit
  in the note.
- **`accepted`** -- the user knowingly accepted the risk rather than
  fixing it now. Requires the user's own sign-off, exactly like a `D`'s
  `answered` -- an agent must never accept risk on the user's behalf. The
  note should say who accepted and why, the same shape as
  `docs/accepted-risks.md`'s entries.
- **`moot`** -- no longer applicable (e.g. the code it was about got
  removed for an unrelated reason).

A finding that reaches none of those states is **parked**: it stays open
on the record, `plan-gate` and `plan-freeze` list it as a NOTE/WARNING,
and nothing blocks on it. The one exception is a `security` finding whose
body carries `**Severity:** CRITICAL` or `HIGH` -- that class cannot be
parked: `plan-gate` refuses the merge and `plan-freeze`/`plan-move ...
done` refuse the close until it is `fixed`, `accepted` (the user's own
sign-off), or `moot` (ADR-0002).

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
- Does **not** require decisions or findings to be resolved first --
  abandoning the work legitimately moots open questions rather than
  obligating them to be answered.
- Freezes the file permanently, exactly like `done/` (same
  frozen-by-residence enforcement).

If someone later reconsiders a rejected idea, there's no dedicated
"revive" script -- `plan-new` a fresh plan and cite the old rejected
file's bare filename in its "Original plan" section. That's enough; this
is rare enough not to need its own mechanic.

## Freeze mechanics

Frozen means *residence*: everything under `done/` and `rejected/` is
permanently un-editable, and git history is the integrity record
(ADR-0002). One rule, enforced at three boundaries -- no modification or
deletion of anything under the two permanent folders, additions pass:

- `.githooks/pre-commit` refuses the staged change, for any tool or
  human, not just a Claude Code session.
- `verify-ladder` flags a working-tree edit before the commit is even
  attempted.
- `plan-gate` refuses the PR range in CI, which is the check that
  survives skipped local hooks.

`plan-freeze` itself (run by `plan-move ... done`) refuses if the file
isn't under `docs/plans/done/`, if `## State` is missing or empty, if
`## State` declares no verification rung (`Verified to rung <N> ...` --
see `docs/procedures/testing-changes.md`, "Declaring the rung"), or if a
CRITICAL/HIGH security finding is unresolved; it warns about open
decisions and ordinary findings, sets `frozen: true` (informational --
the folder is the authority), and stages the file. Every script that
edits a plan (`plan-move`, `plan-reject`, `plan-decide`, `plan-resolve`,
`plan-tick`, `plan-carry`, `subagent-stamp`) refuses a file in a
permanent folder, so setting `frozen: false` by hand buys nothing.

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

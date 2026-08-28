# `plan` skill reference

## Filename and frontmatter

`docs/plans/<status>/<YYYY-MM-DD>-<slug>.md`

- `<YYYY-MM-DD>`: creation date, fixed forever -- moving folders never
  touches the filename. Leads the filename (not the slug) so a plain
  directory listing sorts chronologically.
- `<slug>`: kebab-case, chosen once by `plan-new`, never renamed. Capped
  at 70 characters, backing up to the last word boundary rather than
  cutting mid-word.
- Frontmatter mirrors the folder for greppability but is only ever written
  by the scripts:
  ```yaml
  ---
  slug: add-tailnet-build-fleet
  created: 2026-08-27
  status: todo        # todo | in-progress | done | rejected
  frozen: false        # true only once, set by plan-freeze
  ---
  ```

## Why bare-filename citations

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
- Freezes the file permanently, exactly like `done/` (same checksum
  manifest, same git-level enforcement).

If someone later reconsiders a rejected idea, there's no dedicated
"revive" script -- `plan-new` a fresh plan and cite the old rejected
file's bare filename in its "Original plan" section. That's enough; this
is rare enough not to need its own mechanic.

## Freeze mechanics

`plan-freeze`:
1. Refuses if already frozen, if the file isn't under `docs/plans/done/`,
   or if any decision is unresolved (above).
2. Sets `frozen: true`.
3. Records a `sha256sum`-format line (`<hash>  <relpath>`) in
   `docs/plans/done/.checksums`, which the git-level `pre-commit` hook
   uses to detect any later attempt to modify a frozen file, from any
   tool or human.

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

```markdown
---
slug: add-tailnet-build-fleet
created: 2026-08-27
status: in-progress
frozen: false
---

# Add tailnet-wide distributed Nix builders

## Original plan
Wire nix.distributedBuilds/buildMachines so homelab/thinkpad/torrent can
build for each other over Tailscale.

## State
**2026-08-27, mid-work.** build-worker.nix landed and is live on homelab.
build-fleet.nix is drafted but not yet wired into any host (blocked on
D1, now answered -- next step is applying it). One finding (F1) from the
`security` subagent is still open.

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

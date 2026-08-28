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

## The State section

`## State` is the plan's cold-resumability entry point -- what a session
with zero memory of this task should read first to know where things
stand, without reconstructing it from the sections below. Mandatory on
every plan (`plan-new` creates the heading; `plan-freeze`/`plan-move ...
done` refuse if it's empty). Unlike every other section, it is **rewritten
in place**, not appended to -- see SKILL.md, "Append-only, always -- except
`## State`".

This works precisely because it is not the plan's only record of what
happened. `Progress`, `Decisions (D)`, `Gotchas (G)`, and `Findings (F)`
remain exactly as append-only as before, and stay the actual source of
truth. `State` is a derived summary over them, safe to overwrite because
nothing is lost by overwriting it -- the underlying facts are still there,
dated, below.

For a plan finished in one sitting, a line is enough: `Done -- see
Decisions.` For a plan that spans sessions, rewrite it whenever the
picture changes materially (not on every tick): what's actually true right
now, what's blocking, what a cold reader needs to know before touching
anything. `docs/audits/2026-08-26/RESUME.md` on the security-audit branch
is the pattern this generalizes from -- read it (`git show
worktree-worktree-security-audit-plan:docs/audits/2026-08-26/RESUME.md`)
for a worked example of how much a State-shaped summary can carry for a
genuinely long-running effort. For most plans it will be much shorter than
that.

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

## Finding resolution states, precisely

A `### F<N>` heading records something the `security` or `docs-updater`
subagent found. Exactly three ways to resolve one, all terminal --
recorded with `plan-resolve <file> F<N> fixed|accepted|moot "<note>"`:

- **`fixed`** -- the underlying issue was fixed and verified (not just
  built).
- **`accepted`** -- the user explicitly accepted the risk. Say why. For a
  systemic risk worth remembering fleet-wide, also cross-file it into
  `docs/accepted-risks.md`; a plan-local `ACCEPTED` marker on its own is
  enough for anything narrower than that.
- **`moot`** -- the code or config the finding was about was removed or
  replaced outright, so the finding no longer has a target. Say what
  removed it (a commit, a later decision in the same plan).

`plan-freeze` (and therefore `plan-move ... done`) walks every `### F<N>`
heading exactly as it walks `### D<N>` and refuses if any one isn't
`FIXED`, `ACCEPTED`, or `MOOT`. Unlike decisions, there's no non-terminal
state analogous to `DISCUSSED` -- a finding is either resolved one of these
three ways or it isn't.

### Findings that started outside this plan

The fleet-wide `security-audit` skill numbers findings per audit report
(`F-P<n>-NN`, e.g. `F-P3-04`) -- a different, larger-scoped scheme, because
one audit spans nine report files and dozens of findings. When one of
those findings is deferred into a task-scoped plan (`security-audit`
SKILL.md, Phase 4), it gets a **fresh, plan-local `F<N>`** in the new
plan's `Findings (F)` section, same as any other finding -- don't try to
reuse or renumber the fleet id. Cite the origin instead, in the entry's
first line: `originally F-P3-04, docs/audits/2026-08-26/P3-....md`. This
keeps the two schemes in their own scopes (per-report vs. per-plan) rather
than merging them, while still making the connection findable.

## Rejecting a plan (abandoned or superseded work)

`docs/plans/rejected/` is a fourth, equally permanent terminal state,
alongside `done/` -- for work that was started and then abandoned, or
superseded by a different approach. `plan-reject <file> "<reason>"`:

- Only accepts a source file currently in `todo/` or `in-progress/`.
- Requires a mandatory reason (cite the superseding plan's bare filename
  in the reason text if there is one), appended as a dated
  `**REJECTED <date>:**` marker -- append-only, same as everything else.
- Does **not** require every decision or finding to be resolved, or a
  State section to exist, unlike `plan-move ... done` -- abandoning the
  work legitimately moots open questions rather than obligating them to
  be answered.
- Freezes the file permanently, exactly like `done/` (same checksum
  manifest, same git-level enforcement).

If someone later reconsiders a rejected idea, there's no dedicated
"revive" script -- `plan-new` a fresh plan and cite the old rejected
file's bare filename in its "Original plan" section. That's enough; this
is rare enough not to need its own mechanic.

## Freeze mechanics

`plan-freeze`:
1. Refuses if already frozen, if the file isn't under `docs/plans/done/`,
   if any decision or finding is unresolved (above), or if `## State` is
   missing or empty.
2. Sets `frozen: true`.
3. Records a `sha256sum`-format line (`<hash>  <relpath>`) in
   `docs/plans/done/.checksums`, which the git-level `pre-commit` hook
   uses to detect any later attempt to modify a frozen file, from any
   tool or human.

## Citeable IDs

`D1, D2, …` decisions; `G1, G2, …` gotchas/lessons; `F1, F2, …` findings
(populated by the `security`/`docs-updater` subagents). Sequential per
type per file -- the filename already disambiguates across files, so no
global numbering is needed. See "Finding resolution states, precisely" for
how `F<N>` gets closed out.

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

## State
In progress -- build-fleet.nix drafted, D1 answered, D2 deferred and carried.

## Original plan
Wire nix.distributedBuilds/buildMachines so homelab/thinkpad/torrent can
build for each other over Tailscale.

## Progress
- [x] build-worker.nix drafted
- [ ] build-fleet.nix drafted (see D1)

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
### F1 -- build-fleet.nix opens the builder port to the whole tailnet, not just the submitting host
**FIXED 2026-08-27:** scoped `networking.firewall.interfaces.tailscale0` to
the specific peer IPs instead of the full tailnet CIDR.
```

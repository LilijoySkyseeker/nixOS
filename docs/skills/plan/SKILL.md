---
name: plan
description: Conventions and scripts for creating, updating, and closing citeable plan files under docs/plans/{todo,in-progress,done,rejected}/ -- the repo's replacement for TODO.md/docs/DONE.md. Use whenever creating a new plan, recording a decision/gotcha/finding, ticking progress, moving a plan between todo/in-progress/done, or rejecting/abandoning one.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/plan-new *) Bash(${CLAUDE_SKILL_DIR}/scripts/plan-move *) Bash(${CLAUDE_SKILL_DIR}/scripts/plan-decide *) Bash(${CLAUDE_SKILL_DIR}/scripts/plan-carry *) Bash(${CLAUDE_SKILL_DIR}/scripts/plan-freeze *) Bash(${CLAUDE_SKILL_DIR}/scripts/plan-tick *) Bash(${CLAUDE_SKILL_DIR}/scripts/plan-reject *) Bash(${CLAUDE_SKILL_DIR}/scripts/plan-resolve *) Bash(${CLAUDE_SKILL_DIR}/scripts/plan-lint *)
---

Read `reference.md` in this skill's directory for the full citation-ID
vocabulary, the append-only editing rules, and a worked example -- this
file stays short on purpose (progressive disclosure).

## The rule

Every plan file lives at `docs/plans/<status>/<created-date>-<slug>.md` and
is cited **everywhere else in the repo by its bare filename + anchor**,
never by folder path: `<date>-<slug>.md#D3`. This is deliberate (see
`reference.md`, "Why bare-filename citations") -- it's what makes a
citation survive the file moving between folders. Never write
`docs/plans/...` into a citation.

## Scripts (all in `${CLAUDE_SKILL_DIR}/scripts/`)

| Script | Purpose |
|---|---|
| `plan-new "<title>"` | Create a new plan in `docs/plans/todo/`. Prints its path. |
| `plan-move <file> in-progress\|done` | Move between folders. Moving to `done` auto-freezes (below) and refuses if any decision is unresolved. |
| `plan-decide <file> D<N> answered\|discussed\|deferred "<note>"` | Record a decision's status. Only `answered` (from an actual user confirmation) or a `deferred`-then-`plan-carry`'d item let the plan later freeze -- `discussed` alone does not. |
| `plan-resolve <file> F<N> fixed\|accepted\|moot "<note>"` | Record a finding's resolution. Exactly mirrors `plan-decide` for findings -- see "The three finding states" in `reference.md`. |
| `plan-carry <file> D<N> ["<new title>"]` | Spin a `deferred` decision into a brand-new `docs/plans/todo/` plan, so it resurfaces as backlog instead of disappearing into a frozen file. |
| `plan-freeze <file>` | Called automatically by `plan-move ... done`. Marks the file permanently un-editable and records its checksum. Refuses if already frozen, if any decision or finding is unresolved, or if `## State` is missing/empty. |
| `plan-tick <file> <D\|G\|F><N>` | Check off that ID's line in the Progress section. |
| `plan-lint <file>` | Read-only structural check: frontmatter, required sections (including `## State`), sequential/non-duplicate D/G/F ids, and that every Progress citation resolves to a real heading. Not a gate on anything yet -- run it yourself when unsure a plan is well-formed. |
| `plan-reject <file> "<reason>"` | For work started and then abandoned or superseded. Moves a `todo/`/`in-progress/` plan to `docs/plans/rejected/` and freezes it. Unlike `plan-move ... done`, does **not** require decisions or findings to be resolved -- abandoning the work legitimately moots open questions. A reason is mandatory instead. |

Every script exits non-zero and prints a clear reason on failure -- read
the message, don't guess. All of them refuse to touch a frozen file.

## Never hand-edit these mechanics

Don't hand-write `frozen: true`, hand-move a file with `mv`/`git mv`, or
hand-write an `**ANSWERED/DISCUSSED/DEFERRED**` or
`**FIXED/ACCEPTED/MOOT**` marker -- always go through the scripts above, so
the checksum manifest and the freeze/decision/finding gates stay correct.
Free-text edits (the actual plan content, new `###` entries,
`~~strikethrough~~` corrections, and the `## State` section -- see below)
are exactly what you're expected to write by hand; only the
status/frontmatter/decision-marker/finding-marker mechanics are scripted.

## Append-only, always (while not frozen) -- except `## State`

Never delete text. To correct something wrong, `~~strike it through~~` and
add a new dated note beneath it. To update status, use the scripts above,
which only ever append or rewrite a single frontmatter line -- never body
prose.

**`## State` is the one exception.** Every plan carries a mandatory
`## State` section, rewritten in place -- old content replaced, not
struck through -- because its job is answering "what's actually true
right now," not preserving history. The history it's summarizing already
lives, append-only, in Progress/Decisions (D)/Gotchas (G)/Findings (F)
below it; State is a synthesis over that record, not a second copy of it.
Keep it current as work progresses -- a cold pick-up should be able to
read State alone and know where things stand without replaying the whole
file. `plan-freeze` (and therefore `plan-move ... done`) refuses if
`## State` is missing or still empty.

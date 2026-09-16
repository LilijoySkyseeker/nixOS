---
slug: rename-the-plan-and-workflow-skills-to-plan-file-and-task-gate-to
created: 2026-09-15
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---
# Rename the plan and workflow skills to plan-file and task-gate to stop shadowing builtins


## State

**2026-09-15, code complete, verified to rung 3 (ran it locally, output
inspected).** Both skills renamed in one change, because
`required-agents`/`verify-ladder`/`plan-gate`/`subagent-stamp` all source
`lib.sh` through a baked relative `../../plan/scripts/` path -- renaming
either skill alone would leave that path straddling an old and a new
name.

Evidence: `scripts/gate-tests` 108 passed / 0 failed (28 failures on the
first run were this change's own -- the fixture copied the skill trees to
their old directory names, so every sabotage probe hit a dead `lib.sh`
source and the gate refused before the sweep could prove anything);
`verify-ladder` all checks passed; the CI pin step's fallback simulated
against the real `origin/master` selects `gate=workflow lib=plan`, so
this PR stays gated rather than degrading to skip.

**Not done here:** the review subagents step 6 names (`/simplify`,
`docs-updater`, `security`, `spec-check`) were not run -- this session is
under a harness instruction not to spawn subagents unprompted. They are
advisory per ADR-0002, and this change adds no runtime surface, but the
pass is owed and unrun.

## Original plan

Claude Code 2.1.228 ships `/plan` as a builtin command
(`description:"Enable plan mode or view the current session plan"`,
`argumentHint:"[open|share|<description>]"`). Its command list is
assembled skill-directory-first and builtins-last, and lookup returns the
first exact name match, so this repo's `plan` skill **shadows** that
builtin inside this checkout: `/plan open` and `/plan share` have no
other entry point and become unreachable. `/plan` is likewise a builtin
in Codex CLI, Cursor CLI and Gemini CLI, and skills are now a cross-tool
format, so the collision travels with the files.

`workflow` does not shadow anything -- builtin `/workflows` is a distinct
exact name -- but it collides semantically with Claude Code's `Workflow`
tool and its `.claude/workflows/` script directory, in a repo that also
has `.github/workflows/` and `docs/procedures/workflow.md`.

So: `plan` -> `plan-file`, `workflow` -> `task-gate`. Both new names are
clear of the builtin command table and of every name in the local plugin
catalogue.

Scope is **live surfaces only**. `docs/plans/{done,rejected}/` is frozen
by `pre-commit`, `verify-ladder` and `plan-gate`, and stays untouched --
its references are a record of what the skills were called at the time.

## Progress

- [x] `git mv` both skill directories
- [x] repoint the `.claude/skills/` symlinks (`scripts/claude-links-check --fix`)
- [x] `name:` frontmatter in both `SKILL.md`s
- [x] the four baked `../../plan/scripts/` source paths
- [x] `.claude/settings.json` hook commands (4)
- [x] `.github/workflows/plan-gate.yml` transition-aware pinning (G1)
- [x] `scripts/gate-tests`, `.githooks/pre-commit`, `.gitignore`
- [x] prose docs and live plan files
- [x] `verify-ladder` + `gate-tests` green

## Decisions (D)

### D1 -- rename `workflow` to `task-gate` rather than keeping the word
Asked the user directly, offered `change-gate` / `task-gate` /
`ship-gate` / `repo-workflow`. `task-gate` chosen: it keeps the "gate"
vocabulary the repo already uses (`AGENTS.md` says "the workflow gate",
CI is `plan-gate.yml`) while reading naturally against the skill's own
triviality bar, and sits further from `plan-gate` than `change-gate`
would.


**ANSWERED 2026-09-15:** user picked task-gate from four offered names

### D2 -- leave `docs/plans/{done,rejected}/` alone
Also the user's call, same exchange. Frozen plans are an append-never
record; a stale skill path inside one is correct history, not a defect.


**ANSWERED 2026-09-15:** user chose live-surfaces-only scope, leaving done/rejected frozen

### D3 -- mechanically repoint dead skill paths in live plans and audits
Not asked; recording it because it stretches D2's boundary. Six
`todo/`/`in-progress/` plans and two `docs/audits/` files carried
`docs/skills/{plan,workflow}/...` paths that the rename turns into dead
pointers, plus one cold-start instruction in `2026-08-26/RESUME.md`
telling a reader to "load the `plan` skill". Those are pointers, not
claims about what was true at the time, so repointing them preserves the
record rather than rewriting it -- and the repo has precedent: the
2026-09-09 contraction of
2026-08-27-known-weak-points-in-the-plan-file-and-workflow-sy.md migrated
citations inside a live plan for exactly this reason. Narrative passages
that *recount* a session naming the old skills were left alone. Frozen
`done/`/`rejected/` plans were not touched at all, per D2.

## Gotchas (G)

### G1 -- renaming the pinned gate script reintroduces the CI bootstrap gap
`.github/workflows/plan-gate.yml` deliberately runs the *base branch's*
copy of `plan-gate`, so a PR cannot neuter its own gate. It resolves that
copy by path, and `2026-08-28-fix-plan-gate-ci-bootstrap-failure-on-its-own-introducing-pr.md#G1`
already records that this pattern has a one-time gap whenever the pinned
path does not exist on the base yet. Renaming the path recreates exactly
that: on this PR `origin/master` has no `docs/skills/task-gate/`, so a
naive rename makes the pin step degrade to "nothing to gate" and this PR
merges ungated.

Worse, the pinned `plan-gate` sources `lib.sh` through a relative path
baked into itself, so the temporary layout CI builds has to match
whichever naming the *base branch* uses, not the PR's.

Fix: the pin step probes the new pair first and falls back to the old
one, and derives the temp layout from whichever it found. The fallback is
inert once master carries the new names and can be deleted then.

### G2 -- a path-rename sweep keyed on a trailing slash misses the directory itself
The first pass repointed `docs/skills/plan/` -> `docs/skills/plan-file/`
with the trailing slash included, which is correct for every *file*
reference but silently skips the four places `scripts/gate-tests` names
the directory as a copy *destination*
(`cp -r "$PLAN_SCRIPTS/.." "$repo/docs/skills/plan"`). The fixture then
built a tree whose scripts sourced `../../plan-file/scripts/lib.sh` from
a directory still called `plan`, and 28 sabotage probes failed with "the
gate already refuses with nothing sabotaged" -- a message that describes
the symptom and gives no hint the cause is a rename miss. When renaming
a directory, sweep for the bare name as well as the name-plus-slash.

## Findings (F)
*(populated by security/docs-updater when invoked)*

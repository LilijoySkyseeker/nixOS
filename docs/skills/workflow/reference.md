# `workflow` skill reference

## Trust hierarchy

When verifying a claim or a fix, evidence is not all equally trustworthy.
Least to most trusted:

**documentation → source code → local build (output actually inspected,
not just "it built") → VM testing → an actual switch on a real host.**

Each rung supersedes the ones below it when they disagree — a doc saying a
service is hardened doesn't outrank actually reading the unit's
`serviceConfig`; a clean build doesn't outrank a VM boot showing the unit
failing to start. Climb the ladder as far as the task actually warrants
(see `docs/procedures/testing-changes.md` for the concrete commands at
each rung) rather than stopping at the cheapest rung that happens to agree
with what you expected to find. The rationale is in `docs/agents.md`.

**Corollary: a fix that is not declarative and reproducible is no fix at
all.** A change made by hand on a live host (an ad hoc `systemctl edit`, a
manually-run command, a value patched in `/run/secrets` or the running
config) is not a fix until it's expressed in this repo's Nix and actually
deployed from it — otherwise the next rebuild silently reverts it, and the
next person has no way to know the fix ever existed.

## Handoff notes

A handoff note exists only while a task spans sessions, or holds a user
decision that hasn't reached a PR yet. One plain markdown file at
`docs/plans/<slug>.md`, four sections, kept short:

```markdown
# <task title>

## Goal
One or two lines, in the user's words.

## Your decisions
- 2026-10-06: <what the user decided>. Only things the user actually said.

## State
Where things stand right now. Rewritten in place, not appended.

## Next
The next concrete step.
```

No ids, no scripts, no status folders. A new session reads it before
anything else. When the work merges, the goal and decisions go into the
PR description and the note is deleted in the same PR. The why behind
individual changes lives in commit messages, where `git log`/`git blame`
find it.

Older plans under `docs/plans/{todo,in-progress,done,rejected}/` and the
`# plan: <date>-<slug>.md#D2` citations in code are an archive from the
previous system. Read them for history; don't edit them or add new
citations. Picking up an old `todo/` or `in-progress/` item means starting
a handoff note that links it.

## Review agents

`docs/skills/workflow/scripts/required-agents` prints which agents the
current diff calls for, decided from the paths changed rather than by
judgment, in run order:

| Agent | Runs when |
|---|---|
| `/simplify` | any code change (`WF_CODE_GLOBS` in `scripts/lib.sh`) |
| `security` | any code change |
| `docs-updater` | any code change **or** any `.md` changed |

"Code" is deliberately wider than Nix: scripts, git hooks, hook wiring,
agent definitions, `.sops.yaml`, `secrets/`, CI workflows, `flake.lock`,
`.gitignore` and `.gitattributes` all change what a machine or a gate
does. `docs-updater` fires on code too because a code change can stale a
doc it never touches.

All of it is advisory: the agents run because they find things. The
first `security` run found real fleet exposure.

A harness default against spawning subagents is not a reason to skip
them here: `AGENTS.md`'s "You may use subagents and every tool you have"
is the user's standing request to run them.

### Order

Run them one after another, in the printed order. `/simplify` edits code,
so it goes first and the reviewers see its result. `docs-updater` goes
last so it documents what actually merges, not a version a review
changed afterwards.

**One pass, not a loop.** LLM reviewers have a floor rate of findings on
any nontrivial surface, so "reviewers found nothing" is not a reachable
exit; a design that used it as one livelocked (ADR-0002). Apply what's
worth applying, list anything knowingly left in the PR description, and
re-run only when the fixes were substantial.

### The agents themselves

- **`security`** — reviews firewall rules, secrets wiring, newly exposed
  services, systemd hardening and authentication. Read-only; reports
  findings with a severity back to the calling session. See
  `docs/agents/security.md`.
- **`docs-updater`** — fixes stale docs and trims comments to
  `docs/style-guide.md`'s shape, reporting any reasoning it removed so it
  can go into the commit message. See `docs/agents/docs-updater.md`.
- **`/simplify`** — reviews for reuse, simplification and efficiency and
  applies its own fixes.

## Trivial vs. not: worked examples

Line count is not the test. A textually tiny change can still be
substantively risky:

- **Trivial**: fixing a typo in a comment; correcting a doc's wording
  where the underlying fact doesn't change; a one-line formatting fix
  `nixfmt` would have made anyway.
- **Not trivial, despite being one line**: `openFirewall = true` added to
  a service block; a single sops secret reference added or removed; a
  one-line change to a systemd hardening flag; a one-character change to
  a firewall port range.

## Hooks

Two Claude Code `PreToolUse` hooks back this up mechanically:

- `footer-guard` hard-blocks AI-attribution footers in commit messages
  and PR bodies (see `docs/GIT_WORKFLOW.md`).
- `fresh-branch-guard` blocks creating a branch while local `master` is
  behind `origin/master`, after a session's work was branched off stale
  `master` and needed a rebase across 57 commits.

The git hooks (`.githooks/`) apply to any tool or human: see
`docs/GIT_WORKFLOW.md`.

## Not covered

VM testing is not run by any script here; see
`docs/procedures/vm-testing.md` for the manual procedure.

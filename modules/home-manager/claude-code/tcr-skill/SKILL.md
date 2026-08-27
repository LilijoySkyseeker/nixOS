---
name: tcr
description: Test->Commit/Revert workflow for implementing a task in small, safe, always-green increments. Only runs when explicitly invoked as /tcr <task> or /tcr --strict <task> -- never trigger this automatically for ordinary coding requests.
disable-model-invocation: true
argument-hint: "[--strict] <task description>"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/tcr-status *) Bash(${CLAUDE_SKILL_DIR}/scripts/tcr-verify *) Bash(${CLAUDE_SKILL_DIR}/scripts/tcr-test *) Bash(${CLAUDE_SKILL_DIR}/scripts/tcr-commit *) Bash(${CLAUDE_SKILL_DIR}/scripts/tcr-revert *)
---

Read `reference.md` in this skill's directory before acting on anything
below that isn't immediately clear -- it has the discovery heuristics,
exact rollback mechanics, failure-log format, and strict-mode details this
file deliberately omits to stay short.

## Parse the invocation

Arguments: `$ARGUMENTS`

If it starts with `--strict ` (or `--strict` is any leading token), strict
mode is on and the rest is the task. Otherwise the whole string is the task.
If the task is empty, ask the user what to implement instead of guessing.

## The invariant

**Every persistent repository state TCR produces must be green.**
`BASELINE_GREEN`, every `COMMITTED` state, and `READY` between steps all
mean: FULL_CHECK passes. `CHANGING` and `TESTING` are the only states where
red is allowed to exist, and only transiently, only in the working tree.

Never get to green by weakening validation instead of fixing the code: no
deleting or skipping a failing test, no loosened assertions, no disabling
lint/typecheck, no editing FULL_CHECK to dodge a failure, no claiming a
check passed without running it via these scripts. If a test is genuinely
obsolete because intended behavior changed, that's a legitimate edit --
make it its own reviewable step and say why in the commit message, don't
fold it silently into an unrelated one.

## Scripts (all in `${CLAUDE_SKILL_DIR}/scripts/`)

| Script | Purpose |
|---|---|
| `tcr-status init/show/end` | Establish/inspect/end a session; discovers FULL_CHECK, isolates pre-existing changes, runs the baseline check. |
| `tcr-verify` | Run FULL_CHECK once, report GREEN/RED. Safe to call any time. |
| `tcr-test --step NAME [--fast]` | Run FULL_CHECK for a named step; only its result gates commit/revert. |
| `tcr-commit --step NAME -m MSG` | Commit, but only if `tcr-test` just passed for that exact step. |
| `tcr-revert --step NAME --reason WHY` | Log the failure, hard-reset to the last green commit, re-verify green. |

Every script prints what to do next; read its output rather than guessing
the next command. Every script exits non-zero on failure -- check exit
status, don't parse for the word "pass".

## Step 1 -- establish the baseline

Run `tcr-status init --task "<task>"` (add `--strict` if strict mode).
Read its output. By default this creates an isolated git worktree from HEAD
under `.claude/worktrees/` and runs FULL_CHECK there before anything is
touched -- your original working tree, including anything the user had
uncommitted, is never read from or written to. If it printed a worktree
path, call `EnterWorktree({path: "<that path>"})` next so the rest of the
session operates inside it (this is explicit instruction to use a worktree,
satisfying EnterWorktree's own precondition for when to use it).

If init reports the baseline is RED, stop. Report the failure to the user
and ask how to proceed -- do not start implementing, and do not pass
`--allow-red-baseline` yourself; only use it if the user explicitly says to
proceed with a known-red baseline.

If a `--full-check` couldn't be auto-discovered, inspect the repo yourself
(README, CI config, package.json/Makefile/pyproject.toml, docs on testing)
and pass one explicitly. Prefer the project's own documented command over
a guess; combine gates the project already treats as required (e.g. tests
+ typecheck + lint) into one `--full-check "a && b && c"` string -- don't
invent gates the project doesn't already have.

## Step 2 -- plan

Turn the task into an ordered list of small behavioral scenarios (not
implementation steps) and show it to the user briefly before starting, e.g.
"1. empty case returns nothing, 2. single insert round-trips, 3. ...".
A step is small because it is *one coherent, testable behavior*, not
because it's under some line count -- a large mechanical rename can be one
step; a five-line change touching three behaviors at once is too big.

## Step 3 -- the loop, per step

1. Make the one change for this increment (code and/or tests).
2. `tcr-test --step "<name>"`.
3. **Pass:** `tcr-commit --step "<name>" -m "<message>"`, then move to the
   next increment. Write the message the way this repo already writes
   commit messages (check for a commit-msg hook, CONTRIBUTING.md, or just
   `git log`) -- `tcr-commit` uses your message verbatim and only appends a
   `TCR-Step:` trailer, so it stays compatible with any convention already
   enforced (e.g. Conventional Commits).
4. **Fail:** do not debug forward from a red state. Run
   `tcr-revert --step "<name>" --reason "<what broke>"`. This discards only
   this attempt's changes -- it cannot touch anything from before the
   session started (see reference.md for why that's safe). Then pick a
   smaller or materially different next step; do not immediately retry the
   same idea.
5. If `tcr-test` prints the stuck-agent banner (same step failed
   `max_attempts` times, default 3): stop retrying variations. Summarize
   what was tried, re-read the relevant code/tests, and either find a
   genuinely different/smaller step or stop and report the blocker with the
   green state preserved. Never bypass the loop just because you're stuck.

Infrastructure-only steps (test helpers, invariant checks, fixtures,
refactoring toward a better seam) go through the exact same loop -- they
just need to independently pass FULL_CHECK like any other step.

## Ending a session

`tcr-status end` deactivates the session and prints how to merge or discard
the worktree/branch (or restore a stashed pre-existing change in
`--in-place` mode) -- it never merges, deletes, or pops anything for you.
If the session used `EnterWorktree`, leave it with
`ExitWorktree({action: "keep"})`, never `"remove"`, so cleanup stays a
separate, deliberate step the user can see.

## Strict mode

Everything above already applies in both modes -- `tcr-commit` itself
refuses an ungated commit regardless of `--strict`. `--strict` additionally
relies on a pre-installed hook that blocks *direct* `git commit`,
`git reset --hard`, `git clean -f*`, force-push, and `git branch -D` while
this session is active, so those bypasses aren't available even if
attempted. See reference.md for exactly what that hook does and does not
catch.

# TCR reference

Deeper detail behind `SKILL.md`. Read this when the summary there isn't
enough to act correctly, or when something goes wrong and you need to
understand why a script behaved the way it did.

## State machine

```
BASELINE_GREEN                 tcr-status init: FULL_CHECK passes on a clean
      |                        checkout of HEAD before anything is touched.
      v
READY                          FULL_CHECK still passes; no step in progress.
      |
      v
CHANGING                       one behavioral increment is being made.
      |
      v
TESTING                        tcr-test is running FULL_CHECK.
   /       \
 PASS       FAIL
  |           |
  v           v
COMMITTED   REVERTED
  |           |
  v           v
READY    VERIFY_BASELINE -> (pass) -> READY
                          -> (fail) -> STOP, corrupted:true, report,
                                       do not continue automatically
```

`BASELINE_GREEN`, `COMMITTED`, and `READY` are the only states meant to
persist. `CHANGING`/`TESTING` exist only in the working tree between one
`tcr-test` call and the next, and are never committed as-is.

## `.tcr/state.json`

Written by every script via `lib.sh`'s `tcr_save_state`; one key per line,
flat (no nested objects/arrays) so it can be read with grep/sed instead of
requiring a JSON library in every consumer.

| field | meaning |
|---|---|
| `active` | `true` while a session exists and hasn't been ended. |
| `mode` | `"normal"` or `"strict"`. |
| `baseline_commit` | SHA of the last accepted green commit. |
| `full_check` / `fast_check` | the commands in force for this session. |
| `worktree_mode`, `worktree_path`, `worktree_branch` | isolation details when using a worktree. |
| `main_repo_root` | the original repo root, untouched in worktree mode. |
| `task`, `current_step`, `attempt`, `max_attempts` | planning/retry state. |
| `last_result` | pass/fail/none for `current_step`'s most recent `tcr-test`. |
| `last_verified_result`/`last_verified_at` | from `tcr-verify` or the post-revert check; independent of step bookkeeping. |
| `preexisting_stash_ref` | set only in `--in-place` mode when there were pre-existing changes to protect. |
| `corrupted` | `true` only if a post-revert verify failed -- see "Corrupted state" below. |
| `failure_log_path` | defaults to `.tcr/failures.md`. |

`tcr-status show` prints this in human form; read the file directly only if
you need a field the summary doesn't show.

Stale state cannot leak into an unrelated future session: `tcr-status end`
sets `active:false`, and every script that finds a state file with
`active:false` refuses to act on it (`tcr_require_root`/the active checks
in each script), so a future `/tcr` invocation must run `init` again rather
than silently resuming.

## Establishing the baseline (`tcr-status init`)

Order of operations:

1. Confirm we're inside a git repo with at least one commit. TCR needs a
   commit to branch from and reset to -- a repo with no commits yet gets a
   clear error instead of being force-initialized.
2. Refuse if a session is already `active` at or above the current
   directory (`tcr-status end` first, or inspect it with `show`).
3. **Isolate pre-existing changes without deciding what to do with them.**
   - Default (worktree mode): `git worktree add -b tcr/<slug>-<ts>
     .claude/worktrees/<slug>-<ts> <HEAD>`. This is a fresh checkout of
     HEAD; the original working tree's uncommitted changes are physically
     in a different directory and are never read, copied, or modified.
     They stay exactly as the user left them.
   - `--in-place`: instead, `git stash push -u` moves pre-existing changes
     (tracked and untracked) out of the working tree into the stash, fully
     restorable with `git stash pop`. The stash ref is recorded in
     `preexisting_stash_ref` and surfaced by `tcr-status show`/`end`.
   - Neither mode ever runs `git reset --hard` or `git clean` against
     content that existed before `init` was called -- that only happens
     later, inside `tcr-revert`, against commits/files TCR itself created.
4. Discover `FULL_CHECK` (see below) unless `--full-check` was given.
5. Run it once, before any TCR change exists, as the literal baseline
   check. Red here means "report and stop, don't pretend a change caused
   it" -- `init` refuses to produce an active session unless
   `--allow-red-baseline` is explicitly passed (which the skill should only
   do on the user's explicit say-so).
6. Write `.tcr/state.json` and best-effort-exclude `.tcr/` (and, in
   worktree mode, `.claude/worktrees/`) via `git ... rev-parse
   --git-path info/exclude`, so neither shows up as untracked noise.

### FULL_CHECK discovery order

`Makefile` (`test:` then `check:` target) -> `package.json` (`scripts.test`,
run via `npm test`) -> `Cargo.toml` (`cargo test`) -> `go.mod`
(`go test ./...`) -> `pyproject.toml`/`pytest.ini`/`setup.cfg` (`pytest`,
falling back to `python3 -m pytest` if `pytest` isn't on PATH) ->
`Gemfile` + `spec/` (`bundle exec rspec`). If none match, `init` refuses and
asks for `--full-check` explicitly rather than guessing -- see
`discover_full_check` in `tcr-status` for the exact checks.

This only finds *a* test command, not every required gate. If the project
also requires typecheck/lint as part of "actually green" (check CI config,
package.json scripts, or ask), pass a compound command:
`--full-check "npm test && npm run typecheck && npm run lint"`. Don't add
gates the project doesn't already enforce.

### Why the isolated worktree makes rollback safe

`tcr-revert` runs `git reset --hard HEAD && git clean -fd -- . ':!.tcr'`.
That's only safe because of an invariant `tcr-status init` establishes and
every subsequent script preserves: **HEAD in the work root is always
either the baseline or the last `tcr-commit`, i.e. always already green.**
Nothing valuable can be sitting there uncommitted except the current
attempt, because:
- worktree mode: the worktree started at HEAD with an empty working tree
  (nothing pre-existing was ever copied in), and every subsequent green
  state is a real commit;
- in-place mode: pre-existing changes were moved into the stash before the
  first `tcr-test` ever ran, so the same "only the current attempt is
  uncommitted" property holds.

This is why `tcr-revert` can use a plain hard reset instead of needing
patch-based restoration: the thing patch-based restoration exists to
protect (pre-existing work) was already moved somewhere safe *before* TCR
made its first change, not extracted after the fact from a mixed diff.

### Corrupted state

If, after a reset+clean, `tcr-verify`'s check still fails, that means a
commit that was previously proven green no longer is -- something changed
out from under TCR (flaky test, non-hermetic state, manual edit to the work
root, environment drift). `tcr-revert` sets `corrupted:true` and exits 9.
Every script refuses to act (`tcr-test`, `tcr-commit`, `tcr-revert`) while
`corrupted:true`. Recovery is manual: inspect the work root, understand why
a known-good commit regressed, fix that, then either edit `state.json`'s
`corrupted` field back to `false` once you've confirmed green with
`tcr-verify`, or `tcr-status end` and start a fresh session.

## Failure log

`.tcr/failures.md`, appended to (never truncated/rewritten) by `tcr-revert`
before the reset runs, so the entry survives the rollback it documents.
Each entry: timestamp, step, attempt number, one-line reason, the
FULL_CHECK command, a `diff --stat` of what was discarded, the last 15
lines of the check's output, the commit SHA rolled back to, and an optional
`--lesson` line. Deliberately not the full test output -- enough to avoid
repeating the same mistake, not a log dump.

## Anti-cheating -- why this is a rule, not a mechanism

Nothing in the scripts can distinguish "legitimately updated a test because
behavior intentionally changed" from "weakened a test to force green" --
both are just a diff that makes FULL_CHECK pass. Encoding that judgment as
a mechanical check would be exactly the kind of unreliable, faked
enforcement `SKILL.md`'s rule against it warns against. Instead:
- every accepted step is a normal, individually reviewable git commit --
  nothing is squashed away, so `git log`/`git diff` on any TCR commit shows
  exactly what changed and why (the message you write);
- `tcr-commit` requires a message every time, which forces the "why" to be
  written down at the moment of the decision, not reconstructed later;
- the rule itself lives in `SKILL.md` as an instruction to follow, not a
  gate to route around.

## Strict mode

Both modes already mechanically gate commits: `tcr-commit` refuses unless
`tcr-test` just passed for that exact step, in normal mode too. What
`--strict` adds is a `PreToolUse` hook (`scripts/tcr-guard-hook`, installed
once in `~/.claude/settings.json`) that blocks *direct* attempts to route
around the scripts while a strict session is active:

- direct `git commit` (must go through `tcr-commit`)
- `git reset --hard` (must go through `tcr-revert`)
- `git clean` with a force flag
- `git push --force`/`-f`
- `git branch -D` / `--delete --force`

The hook is inert (`exit 0` immediately) unless it finds `.tcr/state.json`
with `active:true` and `mode:"strict"` by walking up from the Bash call's
`cwd` -- so it never affects git usage in any other project or outside an
active strict session. It requires `jq`; without it, it fails open (allows
the command) rather than risk a hand-rolled parser mis-splitting a quoted
command string.

**Honest limits:** this is pattern-matching on the literal command string,
not a sandbox. It recognizes `git commit`/`git reset --hard`/etc. anchored
at the start of the command or right after `; & | (`, which avoids
false-positives on a `tcr-commit -m "..."` message that happens to contain
those words, but it can be evaded by sufficiently indirect commands (piping
through another shell, `eval`, base64, etc.). The real safety net is
structural, not this hook: everything destructive still only ever targets
commits/files TCR itself created (see "why the isolated worktree makes
rollback safe" above), and git's reflog keeps discarded commits recoverable
for its normal gc grace period regardless.

`--strict` does not attempt to block further `Edit`/`Write` calls after a
known-red `tcr-test`. Distinguishing "fixing forward instead of reverting"
from any other edit needs semantic judgment a `PreToolUse` hook can't make
reliably -- that's enforced as an instruction in `SKILL.md`, not a gate.

## Usage notes for the user

- **Configuring FULL_CHECK**: pass `--full-check "<cmd>"` to `tcr-status
  init` (via the skill) to override auto-discovery, e.g. when the project
  needs a compound gate discovery won't infer on its own.
- **Working outside a worktree**: pass `--in-place` if an isolated worktree
  isn't wanted (e.g. tooling that only works from the original path); any
  pre-existing changes are stashed first, restorably.
- **Retry budget**: `--max-attempts N` on `init` (default 3).
- **Disabling/exiting mid-session**: `tcr-status end` at any time. It never
  merges, deletes, or pops anything automatically -- it prints the exact
  commands to do so, so cleanup stays a deliberate, visible action.
- **Where failures are logged**: `.tcr/failures.md` in the active work root
  (the worktree in worktree mode).
- **Stale sessions**: safe to ignore -- `active:false` after `end` (or a
  session that was simply abandoned and never `init`'d again) is inert; no
  script will act on it, and no hook fires for it.

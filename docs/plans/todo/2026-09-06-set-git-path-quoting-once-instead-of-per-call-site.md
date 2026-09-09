---
slug: set-git-path-quoting-once-instead-of-per-call-site
created: 2026-09-06
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# set git path quoting once instead of per call site

## State

Not started. Filed 2026-09-06 from a `/simplify` altitude finding. The
per-call-site fix is already in place and correct at all seven sites, so
this is a robustness improvement against the *next* call site, not a
live defect.

## Original plan

Git C-quotes non-ASCII paths by default: `modules/café.nix` is reported
as `"modules/caf\303\251.nix"`, quotes included. Any consumer that
matches that string against a glob, an anchor or a filesystem test gets
the wrong answer — verified in
`2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F34`,
where such a file obliged **no** review agent while the fingerprint,
which uses `-z`, hashed it. The two halves of the same gate disagreed
about the same file.

That was fixed by adding `-c core.quotePath=false` to each affected call:

- `lib.sh`, `plan_worktree_files` — three legs
- `docs/skills/workflow/scripts/required-agents` — the range diff
- `.githooks/pre-commit` — twice, one of them the staged-file list
  feeding the private-key/API-token scan, where the quoted name failed
  `[[ -f ]]` and the scan silently skipped the file
- `.githooks/pre-push` — the host-detection list, where a leading `"`
  defeats the `^(hosts/…)` anchor and no build runs

Seven call sites, each of which had to be found and each of which the
next author has to remember.

### The change

Set it once, at the top of `docs/skills/plan/scripts/lib.sh`:

```sh
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
```

That covers every git invocation in every script that sources `lib.sh` —
`plan-gate`, `required-agents`, `verify-ladder` (including
`changed_lines`' `git diff -U0`), `plan-citations`, `subagent-stamp`, and
all the `plan-*` scripts — and cannot be forgotten at a new call site.
Zero extra processes.

A `plan_git()` wrapper was considered and is worse for this purpose: it
reintroduces exactly the per-call-site remembering the change is meant to
eliminate.

### What it does not cover

- **The git hooks.** `.githooks/pre-commit` and `.githooks/pre-push` do
  not source `lib.sh`, so they keep their own `-c` flags or gain a
  source. Do not quietly drop their flags on the assumption the env var
  reaches them.
- **Literal newlines in paths.** `quotePath=false` addresses non-ASCII
  bytes, not newlines. For `plan_worktree_files` it arguably makes the
  newline case *worse*: the raw newline splits one path across two
  lines, and one of the halves can spuriously match a glob, where the
  C-quoted form matched nothing. The real fix for that is `-z`
  throughout with NUL-safe readers, which `plan_code_fingerprint` and
  `plan-citations` already do and the line-based helpers do not.

Whether to take the `-z` refactor at the same time is the main decision
here; doing the env var alone is cheap and safe, doing both is a larger
change to every consumer of `plan_worktree_files`.

### Verification

Create `modules/café-scratch.nix`, confirm `required-agents` names
`/simplify`/`security`/`docs-updater` for it, confirm `verify-ladder`
lints it rather than skipping it, and confirm the fingerprint moves.
Repeat with a path containing a literal newline to establish which of the
two problems the chosen change actually solves.

## Progress

- [ ] decide whether to take the `-z` refactor with it, as a `### D1`
- [ ] set the env var in `lib.sh`, keeping the hooks' own flags
- [ ] verify with a non-ASCII filename end to end
- [ ] establish and document what the newline case does either way

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

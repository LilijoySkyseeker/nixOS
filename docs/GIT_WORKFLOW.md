# Git workflow

Solo repo, worked on from multiple machines concurrently (thinkpad, torrent,
homelab, vps). PR-based: branch, open a PR, merge via PR (a real merge
commit — `gh pr merge` without `--squash`/`--rebase`, matching the existing
`Merge pull request #N ...` history) — reserve a direct commit to `master`
for something genuinely small (a typo, a one-line doc correction) where
opening a PR would be pure ceremony.

## Setup (per machine)

Handled automatically — the flake's dev shell (`devshell.nix`) sets
`core.hooksPath` and `pull.rebase` via `shellHook`, so entering the repo with
direnv (or running `nix develop`) is enough. Hooks live in `.githooks/`
(tracked) rather than `.git/hooks/` (not tracked) so this works from any
clone with no manual step. If you ever need to set it by hand (e.g. outside
the dev shell):

```bash
git config core.hooksPath .githooks
git config pull.rebase true
```

`pull.rebase true` matters here specifically because the same repo is edited
from several machines: a merge commit from a routine `git pull` on top of
local commits creates noise and makes `flake.lock` conflicts harder to read.
Rebase keeps history linear instead.

## Commit messages — Conventional Commits

```
<type>(<scope>)?: <subject>
```

Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `security`, `perf`,
`ci`, `build`, `revert`. Scope is optional, typically a host or module name,
e.g. `fix(homelab): correct impermanence persist path`.

Enforced by the `commit-msg` hook.

No `Co-Authored-By: Claude ...` or `Claude-Session:` trailer in commit
messages — the git author/committer identity already records who/what made
the commit, so both are redundant noise in history. Hard-blocked, not just
documented: `docs/skills/workflow/scripts/footer-guard` (a `PreToolUse`
hook) denies any `git commit`/`gh pr create`/`gh pr edit` whose text
contains one.

Same for PR descriptions: no "🤖 Generated with Claude Code" footer or
`claude.ai/code/session_...` link. Let the body end at its last real
content line (e.g. the test plan).

A commit for work tracked in a plan file (`docs/skills/plan/SKILL.md`) may
add a `Plan: <slug>-<date>.md` trailer for traceability — but never inline
the plan's decisions/findings into the commit body; the body stays short
and human, the reasoning stays in the plan.

## Hooks

- **pre-commit** — blocks commits containing an unencrypted `secrets.yaml`
  (must have a `sops:` metadata block), private key blocks, age secret keys,
  or common API token patterns. Bypass with `git commit --no-verify` for
  false positives.
- **commit-msg** — enforces the Conventional Commits format above.
- **pre-push** — for every host under `hosts/` whose config changed in the
  commits being pushed (directly, or via `modules/` — which covers
  `modules/nixos/`, `modules/home-manager/`, `modules/profiles/`,
  `modules/services/`, and `modules/flake/` alike — or
  `flake.nix`/`flake.lock`), runs `nixos-rebuild build --flake .#<host>`
  before allowing the push. This never switches a running system — it only
  builds. Bypass with `git push --no-verify` if you know what you're doing
  (e.g. you already built it manually on that host).

## Day to day

- Pull before starting work on any machine: `git pull` (rebases, per config
  above).
- Branch, then open a PR — this is the default for anything more than a
  trivial change, not just "something risky." Rebase the branch onto
  `master` first if it's fallen behind, then merge the PR (a real merge
  commit, not squash/rebase) once it builds clean.
- Commit directly to `master` only for something genuinely small (a typo, a
  one-line doc correction) — if you're unsure whether a change qualifies,
  open a PR.
- Test with `nixos-rebuild build`/`dry-build` before committing anything that
  changes a host's config; only `switch` when you intend to deploy.
- Once a branch's content has landed on `master`, prune it if safe: delete
  the local branch (`git branch -d <branch>`, not `-D`, so it refuses if
  unmerged) and the remote one (`git push origin --delete <branch>`) or via
  `gh pr merge --delete-branch`. Skip pruning if the branch is still needed
  for reference (e.g. an open PR under discussion) or if another
  machine/worktree might still be using it.
- If two machines diverge (forgot to pull before committing elsewhere), rebase
  on pull is already the default — resolve any `flake.lock` conflict by
  regenerating it (`nix flake lock`) rather than hand-editing.

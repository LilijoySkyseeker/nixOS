# Git workflow

Solo repo, worked on from multiple machines concurrently (thinkpad, torrent,
homelab, vps). Trunk-based: work directly on `master`, use a short-lived
branch only for something risky enough to want to test in isolation before
merging.

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
- Commit directly to `master` for normal changes.
- Test with `nixos-rebuild build`/`dry-build` before committing anything that
  changes a host's config; only `switch` when you intend to deploy.
- For something you want to iterate on across multiple commits before it's
  trustworthy (e.g. a new service, a risky refactor of `modules/profiles/`), branch,
  then merge (fast-forward preferred — rebase the branch onto `master` first)
  once it builds clean.
- Once a branch's content has landed on `master`, prune it if safe: delete
  the local branch (`git branch -d <branch>`, not `-D`, so it refuses if
  unmerged) and the remote one (`git push origin --delete <branch>`) or via
  `gh pr merge --delete-branch` if a PR was opened. Skip pruning if the
  branch is still needed for reference (e.g. an open PR under discussion) or
  if another machine/worktree might still be using it.
- If two machines diverge (forgot to pull before committing elsewhere), rebase
  on pull is already the default — resolve any `flake.lock` conflict by
  regenerating it (`nix flake lock`) rather than hand-editing.

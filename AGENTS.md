# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) and other AI
agents when working with code in this repository. It's a fast-load
summary — for the deeper *why* behind these rules, and for anything not
covered here, see `docs/`:

- `docs/architecture.md` — how hosts/profiles/modules/services compose.
- `docs/style-guide.md` — Nix conventions actually in use.
- `docs/agents.md` — the reasoning behind the rules in this file.
- `docs/procedures/` — runbooks (new host, new service, secret
  rotation, disaster recovery).
- `docs/GIT_WORKFLOW.md` — git hooks/conventions.

## What this is

A flake-based NixOS/home-manager dotfiles configuration managing multiple
hosts (`thinkpad`, `torrent`, `homelab`, `vps`, `isoimage` — see
`nixosConfigurations` in `flake.nix`). Secrets are encrypted with sops-nix
(see `.sops.yaml`, `secrets/secrets.yaml`) — never commit plaintext secrets.

## Commands

Enter the dev shell first (`nix develop`, or `direnv allow` — `.envrc` is
already `use flake`); it also wires up git hooks (`core.hooksPath
.githooks`) and `pull.rebase true` via its `shellHook`.

- Build (never switch) a host to check it evaluates/compiles:
  `nixos-rebuild build --flake .#<host>` (e.g. `.#homelab`, `.#vps`,
  `.#thinkpad`, `.#torrent`). Use `dry-build` to skip realizing the
  closure. This is the closest thing this repo has to a test suite —
  there's no separate unit test runner.
- Whole-flake check: `nix flake check --no-build`.
- Lint: `statix check .` and `deadnix .`. Format: `nixfmt <file>`.
- Shell scripts (`.githooks/*`): `shellcheck` / `shfmt`.
- Readable diff between the current system and a built closure before
  ever switching: `nvd diff /run/current-system <new-closure-path>`.
- Remote installs: `nixos-anywhere --flake .#<host> root@<ip>` (see
  "Before making changes" below for build-locality caveats).

Never run `nixos-rebuild switch` or push a build to a live remote host
unprompted.

## Repo layout

Quick pointers — see `docs/architecture.md` for the full import chain,
per-host composition table, and the `modules/` vs `services/` vs
`profiles/` boundary explained in detail.

- `flake.nix` — entry point. Defines inputs and the `nixosConfigurations`
  output, one entry per host. Each host is pinned to either
  `nixpkgs-stable` or `nixpkgs-unstable` — check which before assuming an
  option exists (a module option present in unstable may not exist in the
  pinned stable release yet).
- `hosts/<name>/` — per-host `configuration.nix`, `hardware-configuration.nix`,
  and sometimes `disko.nix` (declarative partitioning) or a host-specific
  README (known-issues log, not general docs).
- `profiles/` — shared config layered onto multiple hosts (`default.nix`
  applies to everything, `PC.nix`/`server.nix` are role-specific).
- `modules/nixos/` and `modules/home-manager/` — reusable option modules.
  A module only takes effect if some host or profile actually imports it —
  check reachability before assuming a module is live.
- `services/` — NixOS service configs for things run on the homelab
  (jellyfin, copyparty, factorio, etc.), imported by whichever host needs
  them.
- `files/` — static assets (keyboard layouts, EQ profiles, images). Many
  of these are consumed by external tools (VIA/Vial, Picard, monitor ICC
  profile loaders) rather than by Nix — don't assume "not referenced from
  a `.nix` file" means "unused."

## Before making changes

- Before creating a new branch or worktree, `git fetch origin master &&
  git pull origin master` (or fast-forward the local `master`) so the
  new branch/worktree is cut from up-to-date `master`, not a stale
  local copy.
- Check which `nixpkgs` channel (stable vs unstable) a host uses in
  `flake.nix` before adding a module option — options can exist in one
  and not the other.
- Before deleting a file, `grep -rn` the whole repo for its path/name to
  confirm it's genuinely unreferenced. A file only being unimported from
  `flake.nix`'s reachable graph counts as dead; being unreferenced *by
  Nix* does not automatically mean dead for things in `files/`.
- Validate changes with `nix flake check --no-build` when feasible. Note
  known pre-existing failures before attributing a new one to your
  change (e.g. compare against `git stash` / previous commit).
- Don't build or switch a live host's configuration remotely — that's
  the user's call, not something to run unprompted.
- When installing with `nixos-anywhere`, build on the local machine
  rather than the remote target whenever possible (leave
  `--build-on-remote` unset). Remote targets, especially small/cheap
  VPS instances, can be memory- or disk-constrained enough that
  building the closure there risks hanging or OOMing mid-install.
- Same for `nixos-rebuild --target-host <host>`: prefer building
  locally and pushing the closure (leave `--build-host` unset/local)
  rather than `--build-host <host>`, for the same reason.
- On a fresh `nixos-anywhere` install, pass
  `--generate-hardware-config nixos-generate-config <path>` (e.g.
  `hosts/<host>/hardware-configuration.nix`) so the real target's
  hardware config is captured instead of relying on a
  stale/scaffolded one. Point `<path>` at the checkout/worktree
  currently being worked on — not necessarily the main checkout — so
  the generated file lands where it'll actually get committed from.
- If the host's SSH access depends on a secret (e.g. Tailscale) that
  sops-nix decrypts at boot, pre-generate that host's SSH host key
  locally before install and pass it via `--extra-files` so its age
  key can be enrolled and secrets re-encrypted *before* first boot —
  otherwise sops can't decrypt anything (including the secret needed
  to reach the box at all) on a fresh install. See `hosts/vps/README.md`
  step 1. Never generate or stage that key material inside a tracked
  repo checkout, even gitignored — keep it entirely outside the repo.
- Full new-host runbook: `docs/procedures/new-host.md`. New service:
  `docs/procedures/new-service.md`. Secret rotation:
  `docs/procedures/secret-rotation.md`.

## Commit conventions

- Use [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, etc.) for the subject
  line.
- Write commit messages for **human readability**: explain *why* a change
  was made, not just what changed — the diff already shows what changed.
  Prefer short prose/bullets over restating file names.
- Only commit when the user explicitly asks for it.
- **After every commit, print the full commit message back to the user**
  (e.g. via `git show -s --format=%B HEAD` or by echoing what was just
  written) so they can review it without having to run git themselves.
- Once a branch's content has landed on `master`, prune it if safe (see
  `docs/GIT_WORKFLOW.md`'s "Day to day" section) — don't leave merged
  branches lying around.

# AGENTS.md

Guide for AI agents (and humans) working in this repository.

## What this is

A flake-based NixOS/home-manager dotfiles configuration managing multiple
hosts. Secrets are encrypted with sops-nix (see `.sops.yaml`,
`secrets/secrets.yaml`) — never commit plaintext secrets.

## Repo layout

- `flake.nix` — entry point. Defines inputs and the `nixosConfigurations`
  output, one entry per host. Each host is pinned to either
  `nixpkgs-stable` or `nixpkgs-unstable` — check which before assuming an
  option exists (a module option present in unstable may not exist in the
  pinned stable release yet).
- `hosts/<name>/` — per-host `configuration.nix`, `hardware-configuration.nix`,
  and sometimes `disko.nix` (declarative partitioning) or a host-specific
  README.
- `profiles/` — shared config layered onto multiple hosts (`default.nix`
  applies to everything, `PC.nix`/`server.nix` are role-specific).
- `modules/nixos/` and `modules/home-manager/` — reusable option modules.
  A module only takes effect if some host or profile actually imports it —
  check reachability before assuming a module is live.
- `services/` — NixOS service configs for things run on the homelab
  (jellyfin, copyparty, factorio, etc.), imported by whichever host needs
  them.
- `custom-packages/` — packages/overlays not in nixpkgs. Must be wired
  into `flake.nix` or a host to actually be used.
- `files/` — static assets (keyboard layouts, EQ profiles, images). Many
  of these are consumed by external tools (VIA/Vial, Picard, monitor ICC
  profile loaders) rather than by Nix — don't assume "not referenced from
  a `.nix` file" means "unused."

## Before making changes

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

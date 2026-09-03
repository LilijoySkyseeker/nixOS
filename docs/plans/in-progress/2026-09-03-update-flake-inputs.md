---
slug: update-flake-inputs
created: 2026-09-03
status: in-progress
frozen: false
---

# update flake inputs

## Original plan

Routine `nix flake update` requested by the user, bundled with their
already-in-progress uncommitted `.vil` keyboard layout edits
(`files/doio.vil`, `files/ffkb.vil`, `files/sval_main.vil`) at their
request, into a single commit.

## State

`flake.lock` updated (11 inputs bumped, see G1). All 5 hosts
(`isoimage`, `thinkpad`, `torrent`, `vps`, `homelab`) build clean via
`nixos-rebuild build`. `.vil` files carried over unchanged. Ready to
commit.

## Progress
- [x] `nix flake update`
- [x] verify-ladder run (see G2 for the one known-unrelated failure)
- [x] carry over `.vil` edits from the main checkout

## Decisions (D)


## Gotchas (G)

### G1 -- inputs bumped
`copyparty`, `flake-parts` (+ `nixpkgs-lib`), `home-manager`,
`home-manager-stable`, `import-tree`, `nix-index-database`,
`nixpkgs-stable`, `nixpkgs-unstable`, `nvf`, `sops-nix`, `stylix`. All
5 hosts still build after the bump.

### G2 -- verify-ladder's `nix flake check --no-build` step fails, pre-existing
Fails on `checks.x86_64-linux.zrepl-replication` with `path '...' is
not valid`. This is the exact, already-root-caused issue tracked in
[2026-08-28-nix-flake-check-fails-on-zrepl-replication-test-pk.md](2026-08-28-nix-flake-check-fails-on-zrepl-replication-test-pk.md)
-- confirmed there to reproduce identically on `master` with no other
changes present (via `git stash`), unrelated to any change including
this one. Not re-investigated here; proceeding to commit despite the
ladder's hard-fail on this step since the actual host builds (the part
that would catch a bad input bump) all pass clean.

## Findings (F)
*(populated by security/docs-updater when invoked)*

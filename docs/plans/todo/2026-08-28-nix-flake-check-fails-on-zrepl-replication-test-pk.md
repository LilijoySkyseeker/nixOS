---
slug: nix-flake-check-fails-on-zrepl-replication-test-pk
created: 2026-08-28
status: todo
frozen: false
---

# nix flake check fails on zrepl-replication test (pkgs.path context)

## Original plan

Discovered as a side-finding while working
`2026-08-28-homelab-zdata-pool-usb-uas-checksum-errors.md`: `nix flake
check --no-build` fails unconditionally on this repo (reproduces
identically on `master` with no other changes present, confirmed via
`git stash`), unrelated to whatever else is being worked on. Fix or
otherwise resolve so `verify-ladder` can pass cleanly again.

## Progress
- [x] Root-caused the failure (see G1)
- [x] Ruled out several candidate causes (see G1)
- [ ] Decide on a fix approach (D1)
- [ ] Apply fix
- [ ] Confirm `nix flake check --no-build` passes clean

## Decisions (D)
### D1 -- how to fix: patch the test's ssh-keys.nix import, or something else?
Not yet discussed. Candidate options once picked up:
- Rewrite `tests/zrepl-replication.nix:48`'s
  `import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs` to avoid the
  string-interpolation path-context pattern (e.g. via
  `pkgs.path.nixosTests` helpers if available in this nixpkgs pin, or
  vendoring the two snakeoil keys directly into this repo's test file
  instead of importing them from nixpkgs).
- Investigate whether a different Nix version (this repo currently has
  Nix 2.34.8 in the dev environment) resolves it cleanly, if the
  incompatibility is version-specific.

## Gotchas (G)
### G1 -- root cause: `import "${pkgs.path}/..."` string-interpolation breaks under this Nix version
Full command: `nix flake check --no-build` (also fails with `--refresh`,
and with `--option lazy-trees false` -- that setting doesn't even exist on
this Nix, ruling it out as the mechanism). `--show-trace` pinpoints:

```
… while calling the 'import' builtin
  at tests/zrepl-replication.nix:48:12:
     48 |   inherit (import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs)
… while realising the context of path
  '/nix/store/09g0q2nr523x5inkal66127xmq2z8gw0-yybhs1ybhvk6w56gjywq2x9ipdpx6dd9-source/nixos/tests/ssh-keys.nix'
error: path '09g0q2nr523x5inkal66127xmq2z8gw0-yybhs1ybhvk6w56gjywq2x9ipdpx6dd9-source' is not valid
```

`tests/zrepl-replication.nix` imports nixpkgs' own throwaway ssh test keys
via `"${pkgs.path}/nixos/tests/ssh-keys.nix"` -- an old-style
string-interpolation reference into a flake input's path. Evaluating that
requires Nix to "realise the context" of the referenced store path, which
fails outright ("is not valid") instead of fetching/copying it in, on
Nix 2.34.8.

Ruled out as the cause:
- General store writes/builds: the same Nix, same session, `nixos-rebuild
  build --flake .#homelab` succeeded and built/copied dozens of paths
  fine, so the store/daemon itself works.
- Network: `curl -I` to releases.nixos.org succeeds; `--refresh` doesn't
  change the outcome.
- `lazy-trees`: `--option lazy-trees false` → `warning: unknown setting
  'lazy-trees'` -- not a real setting on this Nix version, so not the
  mechanism (this was the leading theory before testing it).
- No matching upstream `NixOS/nix` issue found for this exact error
  signature (`realising the context of path` + `pkgs.path` +
  `nixos/tests/` + this Nix version) via web search.

Net: a real, narrow compatibility gap between Nix 2.34.8's store/path-
context handling and `tests/zrepl-replication.nix`'s old-style `import
"${pkgs.path}/..."` pattern. Not caused by, or related to, whatever other
work was in progress when this was found.

## Findings (F)
*(populated by security/docs-updater when invoked)*

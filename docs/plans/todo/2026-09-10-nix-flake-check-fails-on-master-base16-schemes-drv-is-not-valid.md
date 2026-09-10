---
slug: nix-flake-check-fails-on-master-base16-schemes-drv-is-not-valid
created: 2026-09-10
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# nix flake check fails on master: base16-schemes drv is not valid, reproducible on torrent and homelab

## State

**2026-09-10.** Observed, not yet root-caused. Blocks verify-ladder's
`nix flake check` rung for every branch until fixed.

## Original plan

`nix flake check --no-build` fails during eval with `error: path
'ihrfigy8ydyr9ggk2fdyi1xmyll9rmxz-base16-schemes-0-unstable-2026-01-15.drv'
is not valid`, surfacing from home-manager's firefox profiles via
stylix (`modules/firefox/each-config.nix` in the trace, under an
evaluation of `nixos-26.11pre1066106` unstable channel nixexprs).

Evidence gathered 2026-09-10 (from the restore-suite session, where it
first bit):

- **Pre-existing on master**: `nix flake check --no-build
  github:LilijoySkyseeker/nixOS/master` fails identically -- not caused
  by any in-flight branch.
- **Reproducible on two independent daemons**: torrent (local) and
  homelab (`ssh root@homelab nix flake check ...`) produce the same
  error for the same drv hash, so it is not one machine's store/db
  corruption.
- **Time-correlated, not code-correlated**: the identical tree passed
  verify-ladder repeatedly on 2026-09-09 (last green ~2026-09-10 06:00
  UTC) and failed by ~2026-09-10 21:30 UTC with only docs/plan-file
  changes in between. Something fetched or substituted during eval
  drifted overnight.
- Local remediation attempted on torrent, no effect: `nix store delete`
  of the drv (succeeded; error persists and the path stays "not
  valid"), `nix store gc`, `--option eval-cache false`. The .drv is
  absent from disk yet eval does not re-instantiate it -- suggests the
  failure happens while *registering* the deterministically re-created
  drv (or one of its references), not while looking up a stale one.
- `flake.lock` pins narHash for all inputs including the indirect
  `nixpkgs/nixos-unstable`, so eval content should be reproducible;
  the moving part is likely a substituter/fetcher interaction (IFD in
  stylix's base16 template reading the base16-schemes package), not
  the pinned source.

Next steps: reproduce with `--show-trace` to find the exact IFD site;
try `nix build <flake>#...base16-schemes` derivation directly on a
clean machine; check whether a `nix flake update` of the
stylix/base16-schemes inputs clears it; consider whether auto-GC on
either host raced an IFD build (both failures could share cache.nixos.org
as the common dependency).


## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

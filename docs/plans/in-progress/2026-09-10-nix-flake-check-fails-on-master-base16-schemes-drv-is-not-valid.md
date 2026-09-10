---
slug: nix-flake-check-fails-on-master-base16-schemes-drv-is-not-valid
created: 2026-09-10
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# nix flake check fails on master: base16-schemes drv is not valid, reproducible on torrent and homelab

## State

**2026-09-10.** Root-caused and fixed on branch
`worktree-flake-check-base16-ifd`. The failure was an
import-from-derivation interacting with a known open Nix bug (G1):
stylix read its scheme yaml out of `pkgs-stable.base16-schemes`, and
once auto-GC removed that package's locally-registered `.drv` files,
eval could substitute the *output* from cache.nixos.org but still
tripped over the missing `.drv` — identically on any machine whose
store had GC'd them, which is why it hit torrent and homelab the same
night with no code change. Fix: `stylix.base16Scheme` now points at
stylix's own pinned `tinted-schemes` source input (byte-identical
yaml, D1), so no derivation has to exist at eval time at all.
`nix flake check` is green locally, but torrent's store was healed as
a diagnosis side effect (G2), so the clean-machine proof is the check
passing on homelab against this branch — pending below.

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

- [x] Reproduce on current master (torrent, 2026-09-10): identical
  error, same drv hash `ihrfigy8…-base16-schemes-…drv`.
- [x] Root-cause (G1): IFD via `pkgs-stable.base16-schemes` +
  GC'd local `.drv` + substitutable output = NixOS/nix#15448.
- [x] Implement fix: `modules/profiles/PC.nix` `base16Scheme` now
  reads from `inputs.stylix.inputs.tinted-schemes` (D1).
- [x] `nix flake check --no-build` green on torrent (weak evidence —
  see G2).
- [ ] Clean-machine proof: check passes on homelab against this
  branch without any store surgery there (its store still had the
  broken state, so this is the real before/after).
- [ ] verify-ladder + review agents + merge.

## Decisions (D)

### D1 — point base16Scheme at stylix's tinted-schemes input, not a package

Three candidate fixes, all removing the demonstrated failure:

1. **`"${inputs.stylix.inputs.tinted-schemes}/base16/gruvbox-dark-soft.yaml"`
   (chosen).** The scheme source stylix itself is built around, already
   pinned in flake.lock (rev `9bd28ed…`), auto-updates in lockstep with
   stylix, zero lock churn, and the yaml is byte-for-byte identical to
   stable's `base16-schemes` package copy (verified with `diff`). A
   plain source path needs no derivation at eval time.
2. Add a top-level `tinted-schemes` input +
   `stylix.inputs.tinted-schemes.follows`. More explicit, but adds an
   input and a relock for no behavioural difference.
3. Inline the 16 colors as an attrset — the only fully IFD-free option
   (kills even stylix's internal yaml→json conversion, see G3), at the
   cost of hardcoding a palette copy. Held in reserve if G3's residual
   ever bites.

Downside of 1 accepted: it reaches into another flake's `inputs`, so a
stylix rename of that input would break eval — loudly, at check time.

## Gotchas (G)

### G1 — IFD + substituted output + GC'd .drv = "path …drv is not valid"

The mechanism, established experimentally on torrent:

- Stylix's yaml import forces the `base16-schemes` *package* to be
  realized during eval (IFD). Nix 2.34 substitutes the package's
  **output** from cache.nixos.org without registering its **.drv**
  locally, and eval then fails demanding the `.drv` be valid — the
  open upstream bug
  [NixOS/nix#15448](https://github.com/NixOS/nix/issues/15448)
  (`nix flake check --no-build` fails on GC'd `.drv`s; related
  [#9285](https://github.com/NixOS/nix/issues/9285), missing `.drv`s
  not repairable).
- **Why it was time-correlated, not code-correlated**: the drvs had
  been registered by ordinary earlier builds; overnight auto-GC
  removed them on both torrent and homelab. Nothing in the tree
  changed and nothing on cache.nixos.org needed to.
- **Proof**: a substituter-disabled eval
  (`--option substituters ''`) forced local instantiation, which
  wrote the `.drv`s back into torrent's store — and the previously
  failing eval immediately succeeded, substituting the same output it
  had refused before. Homelab, untouched, kept failing on the same
  drv hash.

### G2 — diagnosing it on a machine heals that machine's store

Any eval that locally instantiates the drv chain (a substituter-off
eval, a direct `nix build` of the package) re-registers the `.drv`s
and makes `nix flake check` pass **on that machine** with the bug
still present in the tree. Torrent is in that state from 2026-09-10's
diagnosis. A green local check is therefore not evidence the fix
works; homelab (still failing) is the honest test environment for
this branch.

### G3 — a smaller IFD remains inside stylix itself

Stylix converts the yaml to JSON at eval time via a `runCommand`
(base16.nix's importYAML) — still IFD after this fix. Its derivation
is a custom one no binary cache ever has, so the substituted-
output-without-drv trap can't arise the same way, but the drv chain
of its *builder inputs* (unstable pkgs) is in principle exposed to
the same upstream bug. If a "…drv is not valid" ever resurfaces from
the stylix trace, escalate to D1's option 3 (inline colors, zero
IFD).


## Findings (F)
*(populated by security/docs-updater when invoked)*

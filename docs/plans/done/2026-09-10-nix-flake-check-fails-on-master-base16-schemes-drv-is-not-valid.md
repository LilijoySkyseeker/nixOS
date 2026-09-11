---
slug: nix-flake-check-fails-on-master-base16-schemes-drv-is-not-valid
created: 2026-09-10
status: done
frozen: true
kind: task
priority: normal
blocked_by:
---

# nix flake check fails on master: base16-schemes drv is not valid, reproducible on torrent and homelab

## State

**2026-09-10.** Root-caused, fixed, and verified on branch
`worktree-flake-check-base16-ifd`. The failure was an
import-from-derivation interacting with a known open Nix bug (G1):
stylix read its scheme yaml out of `pkgs-stable.base16-schemes`, and
once auto-GC removed that package's locally-registered `.drv` files,
eval could substitute the *output* from cache.nixos.org but still
tripped over the missing `.drv` — identically on any machine whose
store had GC'd them, which is why it hit torrent and homelab the same
night with no code change. Fix: `stylix.base16Scheme` now points at
stylix's own pinned `tinted-schemes` source input (byte-identical
yaml, D1), so the scheme needs no derivation at eval time.

Verified to rung 3 (ran it locally, output inspected): verify-ladder
fully green on torrent (flake check plus all five host builds), and —
since torrent's store was healed as a diagnosis side effect (G2) —
the decisive clean-machine proof ran on homelab, whose store still
carried the broken state: `nix flake check --no-build` against this
branch printed `all checks passed!` there with no store surgery,
while master still failed on the same machine minutes earlier. No
runtime behaviour changes (the yaml is byte-identical), so no VM or
switch rung applies. Reviews: /simplify (2 findings, both applied),
docs-updater (F1, left open — user wording call), security (F2 INFO,
fixed; supply-chain swap independently confirmed a no-op at current
pins). F1 is the only open item and is non-blocking.

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
- [x] Clean-machine proof: check passes on homelab against this
  branch without any store surgery there (its store still had the
  broken state, so this is the real before/after). Verified
  2026-09-10: `all checks passed!` on homelab for this branch while
  master still failed there minutes earlier.
- [x] verify-ladder green; review agents run in order (/simplify →
  docs-updater → security). Merge happens via PR right after this
  plan's close, same branch.

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

### F1 — "temp copy from stable" banner in PC.nix lost its referent

`modules/profiles/PC.nix:76` still carries the `# temp copy from
stable` banner over feishin/prismlauncher/vesktop/… inside the
`pkgs-unstable` list. History (commit `bdd645c`, 2026-04-24, "update
and change torrent and thinkpad to unstable"): these packages were
moved out of the then-populated `with pkgs-stable; [ ... ]` list into
the unstable list and labeled as a temporary copy. This branch removed
the (long-empty) `pkgs-stable` list and the `pkgs-stable` module arg
entirely, so the banner now names a list that no longer exists in the
file. The 2026-08-26 audit had already flagged the comment as
ambiguous (F-P1-15 in `docs/audits/2026-08-26/findings-tail.md`).
Whether "temp" still encodes an intent to move these packages back to
a stable source someday — or the banner should be deleted/reworded as
a plain section label — is a user decision; not silently rewritten
during this docs pass.

_docs-updater finished 2026-09-10T16:53:26Z (code 72f94449f539f4be) -- see Findings above._

### F2 — PC.nix comment "no eval-time IFD" overclaims what this fix removes

- **File:** `modules/profiles/PC.nix:233`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** n/a — documentation-accuracy issue, no adversary; the
  risk is a future maintainer, not an attacker.
- **Rule:** n/a
- **Finding:** The new comment reads "source path, not a package: no
  eval-time IFD". True for this line's own read, but the plan's own G3
  establishes that stylix still performs eval-time IFD internally
  (importYAML's `runCommand` yaml→json conversion), with a residual
  in-principle exposure of its builder-input drv chain to the same
  upstream bug (NixOS/nix#15448). Someone later triaging a recurring
  "…drv is not valid" could read this comment, conclude stylix IFD was
  fully eliminated here, and rule out the actual site. The comment does
  link the plan file, which mitigates; a two-word qualifier ("no
  eval-time IFD *for the scheme read*" or "see G3 for stylix's residual
  IFD") would close the gap.
- **Fix risk:** None — comment-only change; nothing to test beyond
  re-running eval.

---

**Security review, 2026-09-10 (cold read of `worktree-flake-check-base16-ifd`,
commit 5f1446d vs master) — checked and clean apart from F2 (INFO) above.**

Reviewed: `modules/profiles/PC.nix` full current content (not just the
diff), the plan-file bookkeeping under `docs/plans/in-progress/`, and the
supply-chain posture of the `base16Scheme` source swap. Verified, not
assumed:

- **Supply-chain delta is nil at current pins.** The pinned nixpkgs-stable
  (`a3116115…`, `pkgs/by-name/ba/base16-schemes/package.nix`) shows the old
  package was itself just `fetchFromGitHub tinted-theming/schemes` (rev
  `43dd14f6…`) with the yamls copied to `share/themes/` — same upstream
  repo as the new source input, one layer of repackaging removed. Fetched
  the pinned tinted-schemes rev `9bd28ed3…`: narHash matches flake.lock
  (`sha256-fNdfCTeC…`), `base16/gruvbox-dark-soft.yaml` exists, and its
  sha256 (`0df568e0…`) is byte-identical to the stable package's copy —
  independently re-confirming D1's diff claim. Content is 16 hex colors +
  metadata, nothing else. At `nix flake update` time trust floats to
  tinted-theming repo HEAD via stylix's lock instead of a nixpkgs channel
  bump, but the identical update-time trust is already extended to stylix
  itself and its dozen other theme-repo inputs, which are a strictly larger
  eval-time surface — no new adversary capability, so recorded here rather
  than as a finding.
- **Both consumers evaluate.** `nix build --dry-run` of torrent's and
  thinkpad's `system.build.toplevel` on this branch: exit 0, no eval
  errors. (Per the plan's own G2, this machine's store is healed, so this
  confirms expression validity only — the clean-machine proof on homelab
  remains the plan's pending item, correctly tracked there.)
- **No dangling references.** `pkgs-stable` removal from PC.nix's arg set
  is safe: the specialArg is still supplied by `modules/flake/hosts.nix`
  and still consumed by `modules/nixos/{tooling,kde}.nix`,
  `modules/profiles/default.nix`, and the home-manager tooling modules.
  Repo-wide grep shows no other `base16`/`base16-schemes` reference
  anywhere in Nix config — the old package path has no orphaned users.
- **Hardening axis untouched.** No firewall, systemd unit, secret wiring,
  user/group, or service exposure changed; the package-list edit is
  formatting-only (same packages, `pkgs-stable` empty-list stub deleted).
  The orphaned "temp copy from stable" banner is already F1.

No CRITICAL/HIGH/MEDIUM/LOW findings. Nothing here blocks merge.

_security agent finished 2026-09-10 (cold review, session cut from master context)._

_security finished 2026-09-10T16:58:16Z (code 72f94449f539f4be) -- see Findings above._

**FIXED 2026-09-10:** comment reworded: claims only that the scheme itself needs no eval-time build; stylix's internal importYAML IFD stays documented in G3

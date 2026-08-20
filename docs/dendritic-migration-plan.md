# Dendritic Flake Migration Plan

Planning document produced by a Nelson mission (2026-08-20). No code changes
were made in this mission — this is the plan for a future execution mission.

## Goal

Convert this flake from a centrally-orchestrated, hand-chained `imports = [...]`
graph to a **dendritic** organization: every `.nix` file self-registers into
`flake.modules.<class>.<name>` via `flake-parts` + `import-tree`, so files can
be added, moved, or removed without editing a parent's import list. Purely
structural — behavior of all 5 hosts (thinkpad, torrent, homelab, vps,
isoimage) must be unchanged.

## Reconnaissance summary

- ~30 files in scope (~2,500–3,000 lines): `modules/nixos/*` (9),
  `modules/home-manager/*` (4), `profiles/*` (3), `services/*` (6),
  `hosts/*/configuration.nix` (5), `hosts/thinkpad/nvidia.nix`, plus
  `flake.nix`/`devshell.nix` as the conversion point.
- Out of scope: `hardware-configuration.nix`, `disko.nix` (host-specific,
  stay as-is), `secrets/`.
- Import chains are shallow today (≤2 levels), all custom `options.my*`
  blocks are self-contained to their own file — low mechanical risk.
- Real risk is in a handful of implicit cross-file couplings (below), not in
  the sheer number of files.

## Known gotchas to design around

1. **sops relative path** — `profiles/default.nix` sets
   `sops.defaultSopsFile = ../secrets/secrets.yaml`, resolved relative to the
   importing file's location. Must be pinned to a stable (e.g. `self`- or
   repo-root-relative) path before files move.
2. **Per-host specialArgs divergence** — homelab swaps in
   `home-manager-stable`; isoimage omits `pkgs-stable`. Whatever composes
   `nixosConfigurations` under flake-parts must still support per-host
   overrides, not just one shared specialArgs set.
3. **`options` special arg** — consumed directly for stable/unstable compat
   guards in `profiles/default.nix` and `modules/home-manager/tooling.nix`;
   must remain available via `_module.args`.
4. **copyparty overlay scope** — `services/copyparty-iso.nix` applies
   `nixpkgs.overlays = [ inputs.copyparty.overlays.default ]` at module
   level, scoped only to isoimage. Must not leak into the shared
   `pkgs-unstable` used by other hosts.
5. **Duplicated numeric IDs** — gid 999 ("multimedia") is duplicated
   identically in `services/jellyfin.nix` and
   `modules/nixos/nfs-homelab-mounts.nix`; gid 998 ("flatpak") in
   `profiles/PC.nix` deliberately avoids collision. Currently coordinated
   only by code comments.
6. **Duplicated impermanence path** — `environment.persistence."/nix/state"`
   is appended to by `profiles/default.nix`, `services/jellyfin.nix`, and
   `services/factorio.nix` on homelab. Must remain merge-consistent.
7. **devshell.nix** is a plain function, not `perSystem`-shaped.
8. **Vestigial no-op** — `hosts/torrent/configuration.nix` has an empty
   `home-manager.users.lilijoy.imports = [];` override; harmless cleanup
   candidate.

## Phased plan

### Phase 0 — Scaffolding (Risk: Low)
Add `flake-parts` and `import-tree` as flake inputs. Rewrite `flake.nix`
outputs to use `flake-parts.lib.mkFlake` with `import-tree` as the
entrypoint, preserving `vars`, `pkgs-unstable`/`pkgs-stable` construction,
and all current input `follows`. Convert one trivial leaf file
(`modules/nixos/wooting.nix`) as a smoke test.
**Acceptance:** `nix flake check` passes; import-tree discovers and
registers the smoke-test module; no `imports = [...]` chain remains for
that one file.

### Phase 1 — Leaf module conversion (Risk: Low)
Convert files with no custom options and no cross-file coupling:
`modules/nixos/{kde,virtual-machines,tooling}.nix`,
`modules/home-manager/{tmux,virt-manager,kitty,tooling}.nix`,
`services/{nfs,minecraft,octodns}.nix`. Each declares
`flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>`.
**Acceptance:** `nix flake check` passes after each file; no file still
manually imported by a parent.

### Phase 2 — Custom-option module conversion (Risk: Medium)
Convert `modules/nixos/{auto-update,health-alerts,iso-autobuild,
pull-deploy,push-deploy}.nix`. Preserve every `options.my*` block verbatim.
**Acceptance:** `nix flake check` passes; option names/types unchanged
(diff against pre-migration module).

### Phase 3 — Coupling cleanup (Risk: Medium)
Fold in gotchas 5 and 6: centralize gid 999/998 and the `/nix/state` path
into a single named definition (e.g. extend the `vars` attrset or a small
shared `lib`), referenced — not re-typed — from `services/jellyfin.nix`,
`modules/nixos/nfs-homelab-mounts.nix`, `profiles/PC.nix`,
`profiles/default.nix`, `services/factorio.nix`. Convert
`services/copyparty-iso.nix`, keeping its overlay scoped to isoimage only.
**Acceptance:** values appear once, consumed everywhere; per-host builds
still pass; no overlay leakage into other hosts' `pkgs-unstable`.

### Phase 4 — profiles/ conversion and home-manager de-inlining (Risk: High)
Convert `profiles/default.nix` (resolve the sops relative-path gotcha here
explicitly) and `profiles/server.nix`. Split `profiles/PC.nix`: extract the
inline `home-manager.users.lilijoy` config into its own
`flake.modules.homeManager.*` file(s); extract `home-manager.users.root`
from `server.nix` similarly. Drop the vestigial torrent no-op import.
**Acceptance:** `nix flake check` passes; home-manager activation
derivation diffs against pre-migration show no unintended changes.

### Phase 5 — Host reconstruction (Risk: High)
Rebuild all 5 `nixosConfigurations` in `flake.nix` by composing the now-
dendritic `flake.modules.nixos.*` set per host, explicitly preserving
homelab's `home-manager-stable` swap and isoimage's narrower specialArgs.
Convert `hosts/thinkpad/nvidia.nix`.
**Acceptance:** `nix flake show` lists all 5 hosts under the same
attribute names; `nixos-rebuild build --flake .#<host>` succeeds for all 5
(build only, never switch — see verification gate below).

### Phase 6 — devshell (Risk: Low, independent — any time after Phase 0)
Adapt `devshell.nix` into a `perSystem = { pkgs, ... }: { devShells.default
= ...; }` module.
**Acceptance:** `nix develop` produces an equivalent shell.

### Phase 7 — Full-fleet verification (Risk: gate, not itself risky)
Build (not switch) all 5 hosts post-migration. Diff derivation outputs
against pre-migration builds where feasible; explain or flag any drift.
Keep the pre-migration `flake.nix` reachable on a branch for instant
rollback.
**Acceptance:** all 5 hosts build clean. Only after this passes does a real
`nixos-rebuild switch` on any host become appropriate, and even then only
when explicitly requested — never as part of the migration mission itself.
Homelab specifically needs its persistence list rechecked before any real
deploy, given its impermanence setup.

## Sequencing notes

- Phase 0 is a hard prerequisite for everything else.
- Phases 1–3 can interleave, ordered easiest-first.
- Phase 4 depends on Phases 1–3 being far enough along that `profiles/*`
  only reference already-converted files.
- Phase 5 depends on Phase 4 (home-manager modules must exist before hosts
  can compose them).
- Phase 6 is fully independent, can land any time after Phase 0.
- Phase 7 is the final gate before any real deployment.

## Explicitly out of scope for the execution mission

- Any `nixos-rebuild switch` / real deployment.
- Changes to `hardware-configuration.nix`, `disko.nix`, `secrets/`.
- Behavioral changes to any host — this is a structural migration only.

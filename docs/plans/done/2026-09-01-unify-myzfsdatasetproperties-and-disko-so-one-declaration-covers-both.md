---
slug: unify-myzfsdatasetproperties-and-disko-so-one-declaration-covers-both
created: 2026-09-01
status: done
frozen: true
---

# unify myZfsDatasetProperties and disko so one declaration covers both install and live-switch

## Original plan

Follows directly from
`2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`#D1
(`snapdir=disabled` via the new `modules/nixos/zfs-dataset-properties.nix`
module) and `2026-09-01-...disko...` — the disko `rootFsOptions`/root-SSD
consolidation commit `718c396`.

**The gap this closes.** `disko.nix`'s `datasets.<name>.options.<prop>`
and `myZfsDatasetProperties."<pool>/<dataset>".<prop>` are two
independent declarations of the same fact today. Disko's `options` is
install-time only — `disko-install`/`nixos-anywhere` turn it into
`zfs create -o prop=value` once, and it plays no role in an ordinary
`nixos-rebuild switch` (not re-read, not re-applied). The
`zfs-dataset-properties` oneshot is the opposite: live, idempotent,
reapplied every boot/switch, no install-time role. Nothing keeps them in
sync — the same property has to be hand-written in two places today,
exactly the drift class this session's disko consolidation was about
closing everywhere else.

**The design, already talked through, not yet built.** Both `disko.nix`
and the `zfs-dataset-properties` module evaluate inside the same NixOS
`config`, so `disko.nix` can read `config.myZfsDatasetProperties."<pool>/<dataset>"`
directly when building that dataset's `options` block instead of
hand-writing a separate literal. One declaration, two consumers:

- **Disko** reads it to seed the property at creation time on a fresh
  install — meaning a newly-installed host gets e.g. `snapdir=disabled`
  from the dataset's very first mount, with **no** "already-cached
  automount" window at all (see the parent plan's G1/D1 for why that
  window exists on an already-installed host).
- **The systemd oneshot** keeps reading the identical value to
  self-heal an already-installed host (homelab's actual situation
  today) without needing a reinstall.

**What this does not remove:** both mechanisms still need to exist.
Disko's contribution is one-time, at creation; the live oneshot is what
makes an already-installed host self-healing rather than a one-time
guarantee that quietly erodes if something ever flips the property back.

## State

**2026-09-01, implemented and build-verified on all three ZFS hosts, not
deployed anywhere.** homelab (G1, G2), then torrent and thinkpad (G3) all
now read every disko `rootFsOptions`/dataset `options` that has a real
zfs-property counterpart from `config.myZfsDatasetProperties`, via one
shared `vars.zfsProps` helper, instead of a second hand-written literal
— one declaration per host feeds both disko (install-time,
`disko-install`/`nixos-anywhere`) and the live self-heal oneshot
(`zfs-dataset-properties.service`, every boot/switch). vps has no ZFS and
was never touched. All five `nixosConfigurations` build; every rendered
disko script and live-oneshot script was read directly out of the build
(not assumed from a passing build) and cross-checked property-by-property
against `vars.zfsRootFsOptions` — see G3 for the full verification list.
Nothing switched on any real host. Only remaining step is committing and,
per this audit's own rule, leaving the deploy to the user. No further
Progress items open in this plan.

## Progress

- [x] D1 — implementation approach (see Decisions below), confirm no
      surprises before writing code
- [x] wire `disko.nix`'s dataset `options` to read from
      `config.myZfsDatasetProperties` for datasets that have an entry
- [x] decide how disko-specific dataset keys (`mountpoint`,
      `postCreateHook`, etc.) that are NOT zfs properties compose with
      the shared value — they must stay disko-only, not leak into the
      live-reapply oneshot's `zfs set` loop — see G1
- [x] build-verify all three ZFS hosts, confirm no unintended closure
      changes (same "byte-identical store path" check used for the
      disko consolidation, where applicable — this change does alter
      disko.nix's *evaluated* `options`, so an identical-hash check
      isn't the right verification here; verify by reading the rendered
      `options` attrset instead)
- [x] update `2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`
      and `RESUME.md` once implemented
- [x] extend the same mechanism to `vars.zfsRootFsOptions` (each pool's
      own root dataset) for homelab, since those are real, safely
      re-appliable zfs properties too — see G2
- [x] extend to torrent and thinkpad (their `zroot` pools), and lift the
      per-host `zfsProps` helper into `vars.zfsProps` so it's one
      definition instead of three copies — see G3

## Decisions (D)

### D1 — should these two mechanisms share one declaration?

**ANSWERED 2026-09-01:** yes — the user agreed to the design in
conversation and asked for this to be queued as the next item. Not yet
implemented; the how (exact composition of disko-only keys vs shared zfs
properties) is Progress work, not a separate decision, unless something
unexpected turns up while implementing.

## Gotchas (G)

### G1 — disko-only keys never needed separate handling

Implemented 2026-09-01 in `hosts/homelab/disko.nix`: each dataset's
`options` attrset is now `{ <disko-only literals> } // (config.myZfsDatasetProperties."<pool>/<dataset>" or { })`,
merging the shared attrset over a small set of hand-written disko-only
raw properties (`mountpoint = "none"/"legacy"`,
`"com.sun:auto-snapshot" = "false"`). Real disko-only *dataset* concerns
— `mountpoint` (the top-level shorthand disko uses to generate a NixOS
`fileSystems` entry) and `postCreateHook` — are separate top-level
attributes in disko's schema, not inside `options` at all, so they were
never at risk of flowing into `myZfsDatasetProperties`'s `zfs set` loop.
The composition question anticipated in the original plan turned out to
be moot in practice: `myZfsDatasetProperties` only ever holds real `zfs
get`/`zfs set`-style properties by its own contract (see its option
description), so the two key sets are disjoint by construction, not by
any merge-order trick.

### G2 — extended to `vars.zfsRootFsOptions` (pool root datasets), homelab only

Implemented 2026-09-01, same session, on explicit ask after discussing
what's actually safe to unify: ZFS *properties* (dataset- or pool-level,
`zfs`/`zpool` `get`/`set`) are always idempotent and non-destructive to
reapply; *structure* (partitioning, `zpool create`/vdev topology,
`ashift` — fixed permanently at vdev creation, not a runtime-settable
property despite living in `options.ashift`) is one-shot and must stay
disko-only.

`vars.zfsRootFsOptions` (`acltype`, `xattr`, `atime`, `mountpoint`,
`canmount`, `compression`, `devices`, `sync`, `com.sun:auto-snapshot`) is
entirely real properties, applied today by every zpool's `rootFsOptions`
across all three ZFS hosts (`718c396`'s consolidation). Extended for
**homelab only**: `hosts/homelab/configuration.nix` sets
`myZfsDatasetProperties."zroot"/"zdata"/"zbackup" = vars.zfsRootFsOptions;`
(one direction of flow — `vars.zfsRootFsOptions` stays the single literal
source, homelab additionally routes it through the live-reapply option
rather than duplicating the values), and `hosts/homelab/disko.nix`'s
three `rootFsOptions` lines now read `config.myZfsDatasetProperties."<pool>"`
instead of `vars.zfsRootFsOptions` directly — so homelab's disko.nix
reads *everything* zfs-property-shaped through one option, consistent
with the per-dataset wiring above.

torrent/thinkpad's `disko.nix` **unchanged** — they don't import
`zfs-dataset-properties` (PC exclusion is about `snapdir`/backup
browsing specifically, see the parent plan's D1; nothing here revisits
that), so they keep reading `vars.zfsRootFsOptions` directly, same as
before. No new duplication: the literal property values live in exactly
one place (`vars.zfsRootFsOptions`) whichever path a given host takes to
reach them.

Verified, not just built: `nix build .#nixosConfigurations.homelab.config.system.build.diskoScript`
rendered to the **identical store path** as before this change
(`/nix/store/485nnpipg4pi4pvy9i7ai57wdv7zfcyq-disko`), proving install-time
behavior for `zroot`/`zdata`/`zbackup` creation is byte-for-byte
unchanged. The rendered live-oneshot script
(`…/bin/zfs-dataset-properties-start` out of `nixos-rebuild build`'s
closure) now has 27 new `zfs set` lines — all nine properties × three
pools — ahead of the pre-existing `snapdir=disabled` line for
`zroot/local/state`. All five `nixosConfigurations` build to the same
store paths as before this extension for torrent/thinkpad/vps/isoimage
(only homelab's derivation changed), confirming zero effect elsewhere.

### G3 — extended to torrent/thinkpad, `zfsProps` generalized to `vars.zfsProps`

Implemented 2026-09-01, same session, on explicit ask. Two changes:

1. **`vars.zfsProps` (`modules/flake/vars.nix`)** replaces the
   `zfsProps`-per-`disko.nix` local definition from G1. Signature
   `config: pool: dataset: config.myZfsDatasetProperties."${pool}/${dataset}" or { }`
   — takes the calling host's own `config` explicitly, since `vars.nix`
   has no NixOS config of its own. Each host's `disko.nix` binds
   `zfsProps = vars.zfsProps config;` once in its own `let` and calls
   `zfsProps "<pool>" "<dataset>"` exactly as before — G1's call sites in
   `hosts/homelab/disko.nix` are unchanged, only the one-line definition
   moved.
2. **torrent and thinkpad now get the same treatment as homelab**:
   `nixosModules."zfs-dataset-properties"` added to both in
   `modules/flake/hosts.nix`; each sets
   `myZfsDatasetProperties."zroot" = vars.zfsRootFsOptions;` in its own
   `configuration.nix` (same pattern as G2, one pool each instead of
   homelab's three); each `disko.nix` reads
   `rootFsOptions = config.myZfsDatasetProperties."zroot";` and every
   dataset's `options` merges in `zfsProps "zroot" "<dataset>"`. Nothing
   sets a per-dataset property value for either host today (in
   particular, `snapdir` on thinkpad's own `local/state` stays
   untouched, matching the PC exclusion in the `.zfs`-traversal plan's
   D1) — importing the module is inert until something is actually set,
   since its `config` is `lib.mkIf (cfg != { })`.

**Verified, not just built**, per this audit's standing rule:
- `nix build .#nixosConfigurations.homelab.config.system.build.diskoScript`
  still renders to the same store path as G2's check
  (`485nnpipg4pi4pvy9i7ai57wdv7zfcyq`) — moving `zfsProps`'s definition
  into `vars.nix` changed nothing about homelab's evaluated output.
- torrent's and thinkpad's rendered disko scripts were read directly
  (`nix build .#nixosConfigurations.<host>.config.system.build.diskoScript`):
  both `zpool create` commands carry the identical nine `-O` flags
  (`acltype=posixacl atime=off canmount=off com.sun:auto-snapshot=false
  compression=lz4 devices=off mountpoint=none sync=disabled xattr=sa`) —
  the same `vars.zfsRootFsOptions` values disko always applied, now via
  one extra layer of indirection rather than a changed value. Every
  other dataset (`local`, `local/nix`, `local/root`, `local/home`, and
  thinkpad's `local/state`) rendered with only its pre-existing literal
  `options` (`mountpoint`, `com.sun:auto-snapshot` where present) — no
  dataset picked up an unintended property.
- Both hosts' rendered live-oneshot scripts
  (`…/bin/zfs-dataset-properties-start`, read out of each host's built
  closure via a distinct `--out-link`, not `./result` — building both at
  once would otherwise clobber the same default link) are **byte-identical
  to each other** and contain exactly the same nine `zfs set … zroot`
  lines as the `zpool create` flags above, and nothing else — confirming
  the new self-heal capability applies precisely what disko already
  applies at creation, no more.
- All five `nixosConfigurations` build. homelab's and vps's/isoimage's
  toplevel store paths are unchanged from before this G3 work (vps has
  no ZFS and was never touched; isoimage likewise); torrent's and
  thinkpad's changed, as expected, since each gained a genuinely new unit
  (`zfs-dataset-properties.service`, confirmed present and
  `WantedBy=zfs-mount.service` in both rendered unit files).
- `nixfmt --check` clean on every changed file; `statix`/`deadnix`
  warnings present on the touched files are all pre-existing (unrelated
  lines, confirmed by diff) — none introduced by this work.

## Findings (F)
*(populated by security/docs-updater when invoked)*

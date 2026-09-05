---
status: accepted
date: 2026-09-05
---

# ZFS policy tiers and the `myDatasets` registry

Every service gets its own ZFS dataset, so rollback, replication and
offsite backup can be decided per service instead of per filesystem. Which
protection a dataset gets is named by its **tier**, the tier is encoded in
the dataset path, and a single Nix registry (`myDatasets`) is the source of
truth that generates every consumer of that decision — disko layout, ZFS
properties, zrepl's filesystem map, restic's dataset list, and
`environment.persistence` entries.

Decided while planning the fleet log-monitoring stack
(`2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md`),
which needed a persistent-but-never-backed-up dataset and had no existing
convention to follow. Execution lives in
`2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md`.

## The problem this solves

ZFS snapshots whole datasets. There is no exclude list, so **the only way
to exclude a path from a snapshot, a replication stream or an offsite
backup is to make it its own dataset** and leave that dataset out of the
selection. That constraint is already documented in
`2026-08-28-restructure-zfs-so-ordinary-temp-and-cache-data-is.md`; this
ADR generalises its consequence into a fleet-wide convention.

Both backup layers select by dataset:

- **zrepl** matches dataset names exactly; recursion is opt-in via a
  trailing `<`.
- **restic** mounts the latest snapshot of each dataset in a list, and
  `mount -t zfs` mounts one dataset only — never its children.

That second behaviour is the trap. Today `/nix/state` is one dataset, so
the semantics are *"everything under it is backed up unless carved out."*
The moment services get their own datasets, that inverts to *"nothing is
backed up unless explicitly listed"* — and splitting a service out for
better rollback granularity would silently stop backing it up offsite,
with no error, no failed unit, and no staleness alert. The parent dataset
still backs up fine; it is just empty. Discovery would happen at restore
time.

Any per-service-dataset scheme has to make that failure impossible rather
than merely unlikely. That requirement, not aesthetics, is what shapes
everything below.

## Tiers

Named for what the data survives, so the guarantee is legible from the
path rather than needing a lookup:

| Tier | Survives | Snapshots | zrepl → `zbackup` | restic → B2 |
|---|---|---|---|---|
| `offsite` | site loss | yes | yes | yes |
| `onsite` | disk/host loss | yes | yes | no |
| `persist` | reboot | no | no | no |
| `volatile` | nothing — rolled back | `@blank` only | no | no |

`offsite`/`onsite` are a pair where the first is strictly stronger;
`persist`/`volatile` likewise. `mirror` and `replica` were deliberately
rejected as tier names — both already mean something else in this fleet
(ZFS vdev topology, zrepl replication targets).

Four tiers rather than three: `onsite` earns its place because
`zdata/storage/storage-bulk` is real, and collapsing it would force bulk
media either offsite (expensive) or unreplicated (a real loss).

## Dataset tree

The tier is the second path segment, replacing the ambiguous `local`:

```
zroot/
  volatile/root          → /                     (@blank rollback)
  persist/nix            → /nix
  persist/<service>      → /nix/state/<service>
  onsite/<service>       → /nix/state/<service>
  offsite/<service>      → /nix/state/<service>

zdata/
  offsite/<name>
  onsite/<name>

zbackup/<host>/…         replication target — a destination, not a tier
```

**The dataset tree encodes policy; mountpoints stay in one coherent
`/nix/state` tree.** So `zroot/offsite/immich` mounts at
`/nix/state/immich`. Service modules never learn about tiers,
`vars.persistRoot` is unchanged, and re-tiering a service is a
`zfs rename` plus a property change rather than a path change rippling
through every module that references it. Making the filesystem mirror the
policy instead (`/state/offsite/immich`) would break every existing
persistence path and buy nothing.

`/nix` sits in `persist`: it is fully reconstructible from this repo, so
replicating it or shipping it offsite would be paying to back up a cache.
The same reasoning reclassifies `/var/lib/docker` and Jellyfin's
`cacheDir`, both of which go offsite weekly today.

## The registry

`myDatasets` is a normal `my<Name>` options module
(`docs/style-guide.md`), keyed by full dataset name:

```nix
myDatasets."zroot/persist/loki" = {
  tier = "persist";
  mountpoint = "/nix/state/loki";
  owner = "loki";
};
```

Nix generates from it: the disko entry, the ZFS properties (including
`com.sun:auto-snapshot`, which follows from the tier), restic's dataset
list, zrepl's `filesystems` map, and the `environment.persistence` entry.

`tier` has **no default**. A dataset declared without one is an evaluation
error, not a silent policy choice — which is the guard the inversion
hazard above demands. It also removes the standing drift risk between
restic's dataset list and reality, since both now come from one place.

## Safe by default, twice over

The registry gives explicitness. Placement gives a second, independent
layer: restic's `backupPrepareCommand` moves from a hardcoded list to
**recursive enumeration under the `offsite` roots**, mounting in depth
order.

Net effect: a dataset created by hand in the right place is protected
automatically, and a dataset created in the wrong place is caught by the
registry. Both layers have to fail before data goes silently unbacked.

## Considered alternatives

- **Naming convention only, no registry.** Rejected: relies on memory at
  exactly the moment it is most costly to forget, and leaves restic's
  hardcoded list free to drift.
- **Registry only, tier not in the path.** Rejected: `zfs list` stops
  being self-documenting, and a hand-created dataset has no defensible
  default. Path encoding is what makes recursive selectors safe.
- **ZFS user properties as the source of truth** (`local:backup=…`).
  Rejected: properties are set on live datasets out-of-band, so they can
  disagree with the config that is supposed to declare them. The repo
  already treats Nix as authoritative and reapplies properties live via
  `myZfsDatasetProperties`.

## Consequences

- **Adding a dataset to a live host stays a manual step.** disko only
  creates datasets when it formats a disk; a `nixos-rebuild switch` will
  not add a missing one. The registry declares intent and the disko entry
  gives reinstall parity, but `zfs create` still has to be run by hand.
  This is an accepted deviation from the repo's declarative-first
  preference, forced by disko, not chosen.
- **`persist` datasets get no snapshots, so they have no rollback.** That
  is the point, but it means a `persist` dataset must never get a
  `myHealthAlerts.backupStaleness` key, or it will alert forever about a
  backup that intentionally never runs.
- **The legacy and tiered trees coexist** until the migration plan
  (`2026-09-05-migrate-existing-services-onto-per-service-zfs-datasets.md`)
  completes, so restic must cover the union of both. The legacy list is
  marked as a migration remnant in the code so it reads as removable
  rather than as design.
- **D3 in `2026-08-28-restructure-zfs-so-ordinary-temp-and-cache-data-is.md`
  becomes expressible**: `~/.cache` and Trash are `persist`, and
  `~/Downloads` turns into a tier choice rather than an open-ended
  argument.

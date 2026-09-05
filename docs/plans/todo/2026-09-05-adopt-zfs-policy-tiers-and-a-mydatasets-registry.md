---
slug: adopt-zfs-policy-tiers-and-a-mydatasets-registry
created: 2026-09-05
status: todo
frozen: false
---

# adopt ZFS policy tiers and a myDatasets registry

## Original plan

Give every service its own ZFS dataset so rollback, replication and
offsite backup are decided per service rather than per filesystem, and
make that decision declarative through a `myDatasets` registry.

The decision itself — tiers, tree, registry, and the alternatives that
were rejected — is recorded in
[`docs/adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md`](../../adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md).
This plan is the execution of that ADR and does not restate it.

Raised 2026-09-05 while planning the fleet log-monitoring stack, which
needed a persistent-but-never-backed-up dataset for Loki and found no
existing convention for one.

**Ordering.** This plan lands **first**, before
`2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md`,
which depends on `zroot/persist/loki` existing and on the registry
generating its persistence entry. Two plans follow this one and neither
blocks it:
`2026-09-05-migrate-existing-services-onto-per-service-zfs-datasets.md`
(existing services onto per-service datasets) and
`2026-09-05-migrate-existing-architectural-decisions-into-docs-adr.md`
(the wider ADR backfill).

## State

**2026-09-05, not started.** Design fully settled through a grilling
session; every decision below is answered and no code has been written.
ADR-0001 is written and is the reference for the model. Next step is the
`myDatasets` options module — nothing else here can be built before it,
since the registry is what generates the disko entries, ZFS properties,
zrepl map, restic list and persistence entries.

Scope is deliberately narrow (D5): the registry plus new datasets only,
with two existing reclassifications that are pure wins. No existing
service state is migrated here.

## Progress

- [ ] `myDatasets` options module (`modules/nixos/datasets.nix`), with
      `tier` mandatory and no default — see D3
- [ ] generate ZFS properties from the registry, extending the existing
      `myZfsDatasetProperties`/`vars.zfsProps` path
- [ ] generate `environment.persistence` entries from the registry — see
      D4
- [ ] generate zrepl `filesystems` from the registry — see G4
- [ ] restic: replace the hardcoded dataset list with recursive
      enumeration under the `offsite` roots, mounting in depth order —
      see G1
- [ ] restic: keep the legacy list alongside it for the transition,
      marked as a migration remnant — see D6
- [ ] create `zroot/persist/loki` on homelab (manual `zfs create`, see
      G2) and add the disko entry for reinstall parity
- [ ] reclassify Jellyfin `cacheDir` and `/var/lib/docker` out of the
      offsite set — see D5
- [ ] document the manual `zfs create` step in `docs/procedures/`
- [ ] update `docs/architecture.md`'s Backups section to point at
      ADR-0001
- [ ] note in `2026-08-28-restructure-zfs-so-ordinary-temp-and-cache-data-is.md`
      that its D3 is now expressible as tier choices

## Decisions (D)

### D1 — how many tiers?

Four (`offsite`, `onsite`, `persist`, `volatile`) rather than collapsing
`onsite` into `offsite`. `zdata/storage/storage-bulk` is the live proof
that `onsite` is a real category: collapsing it would force bulk media
either offsite (expensive) or unreplicated (a real loss).


**ANSWERED 2026-09-05:** four tiers; onsite justified by storage-bulk

### D2 — tier vocabulary

Named for what the data survives rather than by metaphor. `mirror` and
`replica` were explicitly rejected: both already mean something else in
this fleet (ZFS vdev topology, zrepl targets). `persist` was chosen partly
because it already matches `persistRoot`/`environment.persistence`
vocabulary in the repo.


**ANSWERED 2026-09-05:** offsite/onsite/persist/volatile; mirror and replica rejected as colliding terms

### D3 — path-encoded tiers, or registry only?

Both, deliberately. The path makes `zfs list` self-documenting and lets
restic's recursive enumeration be safe; the registry makes the choice
explicit and generates every consumer. Either alone leaves a gap — see
G1.


**ANSWERED 2026-09-05:** both path-encoded and registry, layers are independent guards

### D4 — mountpoints

The dataset tree encodes policy; mountpoints stay in one coherent
`/nix/state` tree. Service modules never learn about tiers and
`vars.persistRoot` is unchanged. Rejected: mirroring the policy into the
filesystem (`/state/offsite/immich`), which would break every existing
persistence path for no benefit.


**ANSWERED 2026-09-05:** policy in dataset tree, mountpoints stay under /nix/state

### D5 — migration scope

New services only, plus the two reclassifications that are pure wins
(Jellyfin `cacheDir`, `/var/lib/docker` — both regenerable, both going
offsite weekly today). Full migration of existing service state is
deferred to
`2026-09-05-migrate-existing-services-onto-per-service-zfs-datasets.md`,
because that is exactly where G1's hazard bites and it deserves restore
verification rather than a ride-along.


**ANSWERED 2026-09-05:** new services only plus jellyfin cacheDir and /var/lib/docker reclassification

### D6 — transition period

restic covers the union of the legacy hardcoded list and the new
recursive `offsite` roots until the migration plan completes. The legacy
list is marked in the code as a migration remnant so it reads as
removable rather than as design; the migration plan's completion is what
deletes it.


**ANSWERED 2026-09-05:** restic covers union of legacy list and recursive offsite roots

### D7 — which tier does `/nix` belong to?

`persist`. It is fully reconstructible from this repo, so replicating it
or shipping it offsite is paying to back up a cache. Same reasoning
reclassifies `/var/lib/docker` and Jellyfin's `cacheDir`.


**ANSWERED 2026-09-05:** /nix is persist, reconstructible from the repo

### D8 — where does the convention live?

A new `docs/adr/` practice, starting with ADR-0001. Considered and
rejected: a section in `docs/architecture.md` (correct for mechanics, but
does not record *why* alternatives were rejected) and the plan file alone
(plans move to `done/` and freeze, so a live convention would rot in an
unreadable file). Backfilling the rest of the repo's architectural
decisions is its own plan.


**ANSWERED 2026-09-05:** start docs/adr practice with ADR-0001

## Gotchas (G)

### G1 — splitting a dataset out silently stops backing it up

`mount -t zfs <snapshot>` mounts **one dataset only, never its children**,
and restic's `backupPrepareCommand` mounts the latest snapshot of each
dataset in a hardcoded list. So today's semantics are "everything under
`/nix/state` is backed up unless carved out"; per-service datasets invert
that to "nothing is backed up unless listed."

Carving a service out for better rollback granularity therefore **stops
its offsite backup with no error, no failed unit and no staleness alert**
— the parent dataset still backs up fine, just empty. Discovery would
happen at restore time.

This is the reason for both the mandatory `tier` and the recursive
enumeration; the two layers are independent on purpose, so both must fail
before data goes silently unbacked.

### G2 — disko will not create a dataset on a live host

disko only creates datasets when it formats a disk; `nixos-rebuild
switch` will not add a missing one. Every new dataset needs a manual
`zfs create` on the live host **and** a disko entry for reinstall parity.
Already documented in `docs/backups.md`; repeated here because the
registry makes it look more declarative than it is.

### G3 — a `persist` dataset must never get a `backupStaleness` key

`persist` datasets are deliberately never snapshotted or replicated, so a
`myHealthAlerts.backupStaleness` key for one would alert forever about a
backup that intentionally never runs.

### G4 — zrepl's filter is exact-match, recursion is opt-in

`mkFilesystems` builds literal patterns; a trailing `<` means "and
children." homelab's current `local.datasets` have no `<`, which is why a
child dataset is invisible to zrepl by default. Convenient for `persist`,
dangerous for `offsite` — the generated map must add `<` deliberately
rather than inheriting whatever the legacy list does.

## Findings (F)
*(populated by security/docs-updater when invoked)*

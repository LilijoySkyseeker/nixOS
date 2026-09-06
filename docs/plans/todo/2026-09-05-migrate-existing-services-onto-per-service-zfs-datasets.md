---
slug: migrate-existing-services-onto-per-service-zfs-datasets
created: 2026-09-05
status: todo
frozen: false
---

# migrate existing services onto per-service ZFS datasets

## Original plan

Move existing service state off the shared `zroot/local/state` dataset and
onto per-service datasets under the tier scheme, so rollback,
replication and offsite backup become per-service decisions.

The convention is already decided in
[`docs/adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md`](../../adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md);
this plan is only the data migration. Deferred out of
`2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md#D5`
(2026-09-05), which deliberately scoped itself to new datasets because
this is exactly where that plan's `#G1` hazard bites.

**Ordering.** Blocked on
`2026-09-05-adopt-zfs-policy-tiers-and-a-mydatasets-registry.md` (needs
the registry and the recursive restic enumeration in place first). Its
completion is also what allows the legacy hardcoded restic dataset list
to be deleted — see that plan's `#D6`. Not urgent: nothing is broken
today, the current shared dataset simply gives coarser control.

## State

**2026-09-05, not started.** Deferred at creation. No services migrated;
`zroot/local/state` still holds everything except the two
reclassifications handled in the tier plan (Jellyfin `cacheDir`,
`/var/lib/docker`).

## Progress

- [ ] inventory every service persisting to `/nix/state`, with its tier
- [ ] decide per-service tiers — see D1
- [ ] migration procedure with a verified restore, per service — see D2
- [ ] delete the legacy restic dataset list once nothing depends on it
- [ ] confirm no `persist`-tier dataset carries a
      `myHealthAlerts.backupStaleness` key

## Decisions (D)

### D1 — which tier does each existing service get?

Needs a per-service pass. Immich and Jellyfin *config/metadata* are
clearly `offsite`; their caches and transcodes are `persist`. Most other
service state is probably `offsite` but should not be assumed — the point
of the exercise is that the answer differs per service.

### D2 — how is each migration verified?

The failure mode being guarded against is silent: a service split out of
the shared dataset stops being backed up offsite with no error and no
alert, discovered only at restore time. A migration that is not
restore-verified does not count as done. Open question is whether that
means a full restore drill per service or a cheaper positive check that
the data appears in the restic snapshot.

## Gotchas (G)

### G1 — this is a live data migration, not a config change

Each service means: stop it, `zfs create` the new dataset, move the data,
remount, restart, verify. Unlike the tier plan, there is no way to do
this without touching live service state, so it wants a per-service
runbook rather than one big sweep.

## Findings (F)
*(populated by security/docs-updater when invoked)*

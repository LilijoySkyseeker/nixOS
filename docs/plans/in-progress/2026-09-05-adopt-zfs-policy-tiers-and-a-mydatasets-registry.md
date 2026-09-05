---
slug: adopt-zfs-policy-tiers-and-a-mydatasets-registry
created: 2026-09-05
status: in-progress
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

**2026-09-05, code complete, one manual step outstanding.** The
`myDatasets` registry (`modules/nixos/datasets.nix`) is built and wired
into homelab: three registrations (`zroot/persist/loki`,
`zroot/persist/jellyfin-cache`, `zroot/persist/docker`), the restic
recursive-offsite walk, and the zrepl onsite/offsite auto-include.
`nixos-rebuild build` passes for every host (homelab, torrent, thinkpad,
vps, isoimage) and the generated `zfs-dataset-properties` unit script was
inspected directly to confirm `com.sun:auto-snapshot=false` lands on all
three new datasets. `/simplify` ran; of its findings, the redundant
`zfs list` existence check in the restic script and the dead `owner`/
`group` fields on entries with `managePersistence = false` were applied
as-is, and a `myDatasetsReplicated` option was added addressing its
altitude finding about the zrepl dataset-list generation. Its disko
`lib.mkMerge` suggestion was applied, then found to cause a genuine
infinite recursion (`nixos-rebuild build` failing outright) and reverted
back to the original `foldl'`/`recursiveUpdate` form — see F1. Every
host build re-verified green after the revert.

Outstanding: none of the three new datasets exist on the live homelab
host yet (G2) — each needs a manual `zfs create` before the next deploy,
or its mountpoint stays an ordinary directory inside its parent dataset.
This is a live-host, one-way (cache/docker-layer loss on the two
reclassified paths) action and was deliberately left for the operator
rather than run from this session — see
`docs/procedures/new-service.md`'s updated step 5 for the exact command
per entry. Plan stays in `in-progress/` until that step is confirmed
done.

Scope is deliberately narrow (D5): the registry plus new datasets only,
with two existing reclassifications that are pure wins. No existing
service state is migrated here.

## Progress

- [x] `myDatasets` options module (`modules/nixos/datasets.nix`), with
      `tier` mandatory and no default — see D3
- [x] generate ZFS properties from the registry, extending the existing
      `myZfsDatasetProperties`/`vars.zfsProps` path
- [x] generate `environment.persistence` entries from the registry — see
      D4
- [x] generate zrepl `filesystems` from the registry — see G4
- [x] restic: replace the hardcoded dataset list with recursive
      enumeration under the `offsite` roots, mounting in depth order —
      see G1
- [x] restic: keep the legacy list alongside it for the transition,
      marked as a migration remnant — see D6
- [ ] create `zroot/persist/loki` on homelab (manual `zfs create`, see
      G2) and add the disko entry for reinstall parity — disko entry
      done (`hosts/homelab/configuration.nix`'s `myDatasets`); the
      manual `zfs create` on the live host is still outstanding, see
      State
- [x] reclassify Jellyfin `cacheDir` and `/var/lib/docker` out of the
      offsite set — see D5
- [x] document the manual `zfs create` step in `docs/procedures/`
- [x] update `docs/architecture.md`'s Backups section to point at
      ADR-0001
- [x] note in `2026-08-28-restructure-zfs-so-ordinary-temp-and-cache-data-is.md`
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

### D9 — who owns the persistence entry for a reclassified path?

Arose implementing the Jellyfin `cacheDir`/`docker` reclassification (D5).
The registry's `mountpoint` field is the absolute path the app actually
reads/writes; if that path already sits under `persistRoot`
(`/nix/state/<service>`, the flat convention new services use, e.g.
Loki) the dataset mounts there directly and no `environment.persistence`
entry is needed at all. Anything else gets the dataset mounted at
`persistRoot+mountpoint` and impermanence bind-mounts it to the real
path, same as every other persisted directory.

That covers a genuinely new path, but not a reclassified one: Jellyfin's
`cacheDir` already has a persistence entry, declared in
`modules/services/jellyfin.nix` alongside `configDir`/`dataDir`/`logDir`
as one generic list shared across whatever host imports it. Having the
registry generate a second entry for the same path would duplicate that
bind mount, and editing jellyfin.nix to skip `cacheDir` would make a
service module tier-aware, contradicting D4 outright.

**ANSWERED 2026-09-05:** added `managePersistence` (default `true`) to
the `myDatasets` submodule. Off for `jellyfin-cache` and `docker`, whose
persistence entries already exist elsewhere and must stay untouched;
on (the default) for anything the registry is the only owner of, e.g.
Loki. Service modules stay tier-unaware either way — this only decides
who writes the persistence declaration, never whether one exists.

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

### F1 — `lib.mkMerge` over a `cfg`-derived list caused real infinite recursion, reverted

`/simplify` suggested replacing `modules/nixos/datasets.nix`'s hand-folded
`lib.foldl'`/`lib.recursiveUpdate` disko-entry accumulator with
`lib.mkMerge` over a list built by `lib.mapAttrsToList (...) cfg`, since
the module system already merges multiple modules' contributions to the
same `attrsOf`-typed option. That's true, but the refactor doesn't just
change a *value* — it makes the module's own `config` attribute's
top-level *shape* (how many keys the returned attrset has) depend on
`cfg` (`= config.myDatasets`), a length-`attrNames cfg`-dependent list.
The module system evaluates a config attribute's shape eagerly while
gathering definitions across all modules, before any individual option's
*value* is needed — so this is a genuine circular dependency, not merely
a style tradeoff. `nixos-rebuild build --flake .#homelab` failed
immediately with "infinite recursion encountered", not a subtle runtime
bug. Reverted back to the original `foldl'`/`recursiveUpdate` form, which
keeps the config attribute's top-level shape static (`myZfsDatasetProperties`/
`disko`/`environment`, always exactly these three keys) and defers only
the *values* to `cfg`, lazily. See the "NB" comment on `datasets.nix`'s
`config` block for the same explanation in place.

### F2 — `myDatasetsReplicated` is exposed, not auto-wired into `myZrepl`

`modules/nixos/datasets.nix`'s `myDatasetsReplicated` option computes the
`<`-suffixed onsite/offsite dataset list but stops short of adding it to
`myZrepl` itself. Which role covers "this host's own datasets" (`local` vs
`serve`) is host topology, not something this module can know — so each
host feeds the option into whichever role applies itself, e.g.
`myZrepl.local.datasets = [ ... ] ++ config.myDatasetsReplicated;`.

_docs-updater finished 2026-09-05T22:09:25Z -- see Findings above._

### F3 — restic's recursive `offsite` walk word-splits enumerated dataset names, which can silently re-open G1

- **File:** `hosts/homelab/configuration.nix` (`backupPrepareCommand`, the
  `for root in zroot/offsite zdata/offsite; do ... datasets="$datasets $names"; done`
  block and the following `for dataset in $datasets; do ... done` loop,
  both unquoted)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening / needed-used
- **Reachability:** No external adversary — the actor is whoever runs the
  manual `zfs create` step this same plan documents in
  `docs/procedures/new-service.md` (step 5) or
  `docs/adr/0001-...md`'s example, i.e. this repo's own operator, since
  disko never creates these datasets on a live host (G2) and nothing else
  provisions a dataset name. If that dataset name (any component, not
  just the leaf) contains a literal space — or another IFS character —
  the enumeration's output gets word-split on `for dataset in $datasets`
  same as the pre-existing hardcoded list already was, but now the list
  is populated from live `zfs list` output instead of hand-typed
  literals. A split name causes `zfs list -t snapshot -r <fragment>` to
  fail (no matching dataset), the script has no `set -e`, and the `if
  [[ -n "$snapshot" ]]` guard silently skips the mount — the exact "no
  error, no failed unit, no staleness alert" failure mode G1 names as the
  reason this whole feature exists, reopened by the safeguard meant to
  close it.
- **Rule:** n/a (not a `docs/hardening.md` line item) — violates this
  plan's own G1 invariant ("both layers have to fail before data goes
  silently unbacked"); here the second layer (recursive enumeration) can
  fail silently by itself, in a way the mandatory-`tier` layer does
  nothing to catch, since the dataset *is* correctly tiered and placed —
  it just doesn't survive the shell's own word-splitting.
- **Finding:** ZFS dataset names are **not** restricted to
  shell-word-safe characters. Verified against the pinned `zfs` package
  actually used by `hosts/homelab/configuration.nix`
  (`boot.zfs.package`, resolved via `nixosConfigurations.homelab`, zfs
  2.4.4): its own `zfs(8)` man page states the naming grammar as
  `[A-Za-z_.:/ -]` — the character class explicitly includes a literal
  space. `zpool-create(8)` says the same for pool names ("alphanumeric
  characters as well as the underscore, dash, colon, space, and
  period"). So a dataset named e.g. `zroot/offsite/immich backup` is
  valid ZFS and will round-trip through `zfs list -H -o name` as one
  line containing a space; the consuming loop then treats it as two
  words. This isn't hypothetical-only: the task that introduces this
  exact enumeration is also the one adding the fleet's first
  hand-written `docs/procedures/new-service.md` instructions for typing
  a brand-new dataset name by hand, which is precisely where a
  descriptive multi-word name would come from.
- **Fix risk:** Quoting fixes (`for dataset in "${datasets[@]}"` with an
  actual bash array instead of a space-joined string, or `zfs list -H -o
  name` filtered through `readarray`/`mapfile` with `-d ''`/NUL
  separation) change `datasets` from a string to an array, which touches
  every consumer of that variable in both `backupPrepareCommand` and
  needs the equivalent care in `backupCleanupCommand` if it's ever
  extended the same way. Needs a real `nixos-rebuild build` and ideally a
  VM test that creates a deliberately space-named dataset under
  `zroot/offsite` to confirm the fix actually mounts it, since the
  failure mode this finding describes produces no test failure signal by
  itself.

### F4 — `myDatasets`' `owner`/`group` fields are dead-on-arrival for the registry's own canonical dataset shape, and the documented manual-creation step never mentions ownership

- **File:** `modules/nixos/datasets.nix:38-52` (`diskoMountpoint`,
  `needsPersistenceEntry`), `docs/adr/0001-zfs-policy-tiers-and-the-mydatasets-registry.md:110-116`
  (the registry's own canonical example), `docs/procedures/new-service.md`
  (new step 5)
- **Severity:** LOW
- **Confidence:** CONFIRMED for the dead-code claim; PLAUSIBLE for the
  downstream consequence (depends on a service module not yet written)
- **Axis:** needed-used
- **Reachability:** No adversary — this is a design/documentation gap
  that surfaces as a functional trap for whoever wires the next
  `myDatasets` entry (starting with
  `2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md`'s
  Loki module, which this plan is explicitly ordered ahead of).
- **Rule:** n/a — not a `docs/hardening.md` violation, but adjacent to
  the class of mistake `docs/hardening.md` exists to prevent (a directory
  ending up with different ownership than the app that reads/writes it
  expects, previously seen as the `/nix/state/.zfs` 0777 incident this
  same repo was burned by).
- **Finding:** `needsPersistenceEntry = ds.managePersistence &&
  diskoMountpoint ds != ds.mountpoint` only generates an
  `environment.persistence` directory entry (and therefore only applies
  `owner`/`group`) when the dataset's mountpoint sits **outside**
  `persistRoot`. But the ADR's own dataset tree
  (`docs/adr/0001-...md`, "Dataset tree") places every `persist`/
  `onsite`/`offsite` service dataset **at** `/nix/state/<service>` —
  always under `persistRoot` — so for any dataset built the way the ADR
  itself recommends, `diskoMountpoint ds == ds.mountpoint` and no
  persistence entry, hence no ownership enforcement, is ever generated.
  The two datasets in this diff that *do* sit outside `persistRoot`
  (`jellyfin-cache`, `docker`) both set `managePersistence = false`
  because their ownership is already handled elsewhere — so no
  registration exercised by this diff, or implied by the ADR's own
  worked example, ever takes the `owner`/`group` code path. (Jellyfin's
  own case happens to be fine regardless: its NixOS module's
  `systemd.tmpfiles.settings` line for `cacheDir` is a `d`-type rule with
  no `:` prefix, and per the pinned `systemd-tmpfiles(8)`/`tmpfiles.d(5)`
  docs, `d` lines apply their configured owner/group **unconditionally,
  regardless of whether the path already existed** — so jellyfin's cache
  dir gets re-chowned to `jellyfin:multimedia` every boot independent of
  what ownership the fresh ZFS mountpoint started with. This is
  happenstance, not something the registry arranged.) The current code's
  own comment on the `loki` entry (`# ownership is the log-monitoring
  plan's problem once it exists`) already acknowledges this, but
  `docs/procedures/new-service.md`'s new step 5 — the generic, repo-wide
  instructions for adding *any* future `myDatasets` entry — never
  mentions chowning the freshly-created mountpoint, and doesn't warn that
  `owner`/`group` do nothing for the common case. A future service that
  lands via this exact procedure and does **not** happen to carry its
  own unconditional-chown tmpfiles rule (unlike jellyfin) will get a
  dataset mounted root:root, and its non-root dedicated service user
  (`docs/hardening.md`'s own "dedicated service users" convention) will
  fail to write to it — a bug most likely "fixed" by loosening
  permissions on the live host rather than by realizing the registry
  never covered this case, which is exactly the shape of the
  `/nix/state/.zfs` 0777 mistake this repo has already paid for once.
- **Fix risk:** Making `owner`/`group` actually apply to a
  directly-mounted persistRoot dataset means either (a) adding an
  activation-script/tmpfiles step to `datasets.nix` itself that chowns
  `diskoMountpoint ds` whenever `ds.owner != "root"`, regardless of the
  persistence-entry branch, or (b) documenting in `new-service.md` that
  the service module is responsible for its own idempotent,
  unconditional (not merely create-if-missing) ownership enforcement —
  and auditing that every tier-migrated service actually has one before
  relying on it. Either fix needs a live or VM-tested boot to confirm the
  target directory's ownership survives a reboot with the bind
  mount/dataset already present, not just a first-activation check.

**RESOLVED 2026-09-05 (F3):** `backupPrepareCommand` rewritten to be
newline-delimited throughout (`$'\n'`-joined, `printf '%s\n' "$datasets"
| while IFS= read -r dataset`) instead of space-joined/word-split. A
dataset name containing a space now survives the pipeline as one token.
Verified by reading the rendered `backupPrepareCommand` derivation output
directly (not just `nixos-rebuild build` succeeding) to confirm no stray
indentation leaked into the joined string — the initial fix attempt used
a literal embedded newline inside a quoted Nix `''` string, which is
indentation-fragile; `$'\n'` avoids that class of bug entirely. Chose
newline-safe string handling — not one of the array-based options the
"Fix risk" note actually enumerated — over converting to a real bash
array, since the latter would have touched `backupCleanupCommand` too for
no behavioral gain here.

**RESOLVED 2026-09-05 (F4), partially — option (b):** `new-service.md`
step 5 now states explicitly that `owner`/`group` only take effect on a
generated persistence entry, that a flat `/nix/state/<service>` dataset
(the recommended convention) gets none, and that the service module must
arrange its own ownership (tmpfiles rule, or self-managed on start).
Option (a) from the finding (an activation-time chown inside
`datasets.nix` itself, covering the flat case too) is deliberately not
implemented here — it's real behavior-changing scope beyond this plan's
narrow D5 boundary, and no current registration needs it (Loki's entry
leaves `owner`/`group` unset, with the reasoning already in the comment
next to it). Revisit when a concrete service actually needs
registry-enforced ownership on a flat dataset.

## Checked and clean (security review, 2026-09-05)

Reviewed against `docs/hardening.md`, `docs/procedures/secrets.md`, and
`docs/agents/security/reference.md`'s rubric. In scope: `modules/nixos/datasets.nix`
in full, `hosts/homelab/configuration.nix`'s full diff (restic
`backupPrepareCommand`/`backupCleanupCommand`, `myZrepl.local.datasets`,
the new `myDatasets` block), `hosts/homelab/disko.nix` (for key-collision
and parent-dataset-creation checks), `modules/services/jellyfin.nix`'s
existing persistence entry, `modules/flake/hosts.nix`'s one-line addition,
and `docs/architecture.md`/`docs/backups.md`/`docs/procedures/new-service.md`'s
prose changes. No secrets touched or referenced by this change; none
decrypted or read, per policy.

No issue found with: the disko `foldl'`/`recursiveUpdate` merge producing
a key collision with `hosts/homelab/disko.nix`'s existing `zroot` dataset
keys (`local`, `local/state`, `local/nix`, `local/root` vs the new
`persist/loki`, `persist/jellyfin-cache`, `persist/docker` — disjoint);
the missing explicit `zroot/persist` parent dataset (disko's `zfs_fs`
type creates with `zfs create -up`, confirmed in the pinned disko source
at `lib/types/zfs_fs.nix`, so `-p` auto-vivifies the missing parent with
inherited, unexploitable defaults); `myDatasets` being wired into every
host via `modules/flake/hosts.nix` rather than homelab-only (guarded by
`lib.mkIf (cfg != { })`, a no-op everywhere `myDatasets` stays empty);
`com.sun:auto-snapshot` tier mapping matching ADR-0001's table exactly;
ZFS property inheritance (`acltype`/`devices`/`sync`/etc.) for the new
datasets, which inherit correctly from `zroot`'s existing
`myZfsDatasetProperties` since nothing in this registry overrides them;
the restic script's dataset-name interpolation for injection beyond the
word-splitting issue in F3 (no `eval`, no shell metacharacter
interpretation — ZFS names reach `zfs`'s own argv, never a shell, so `;`/
backticks/`$()` in a name cannot execute anything, only word-splitting on
IFS characters is live); and the zrepl `myDatasetsReplicated` filter
correctly including both `onsite` and `offsite` (matching ADR-0001's "zrepl
→ zbackup: yes" for both) while excluding `persist`/`volatile`.

Two findings recorded above (F3 medium, F4 low); no CRITICAL/HIGH found.

_security finished 2026-09-05T22:13:35Z -- see Findings above._

_docs-updater finished 2026-09-05T22:22:54Z -- see Findings above._

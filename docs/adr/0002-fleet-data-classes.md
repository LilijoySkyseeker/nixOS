---
status: accepted
date: 2026-10-26
supersedes: 0001-zfs-policy-tiers-and-the-mydatasets-registry.md
---

# Fleet data: two classes, one list, one pool

Design against the goal spec in `docs/plans/fleet-data.md`. Written after
torrent's pool filled on 2026-10-25: local snapshots kept ~9 days of
deletions pinned, nothing warned, and homelab's `zbackup` was 78% full with
2.67 TB of it torrent's history.

## The spec it meets

Never lose what can't be replaced, never let protecting it get in the way,
and keep everything where it's needed.

1. What rebuilds itself isn't protected. What can be replaced is protected
   at home. Everything else is protected everywhere. If in doubt, it can't be
   replaced.
2. What can't be replaced survives a mistake noticed within a month, the
   loss of any machine, and the loss of the whole house or anything with
   root on it. Each loss costs as little recent work as possible.
3. Protecting data never gets in the way of using a machine.
4. The fleet is one pool: data lives where it's needed, space is used where
   it's free, and every machine is treated the same.
5. Getting data back is easy, and the owner hears when any of this stops
   being true.

## Classes

Every dataset on every host is in exactly one class. ZFS can only exclude
a path from snapshots and replication by making it its own dataset, so
the class is per dataset.

| Class | Survives | Snapshots | Copy on homelab | Offsite | Examples |
|---|---|---|---|---|---|
| `irreplaceable` | everything in spec line 2 | every 5 min | yes, 1 month of history | yes | home directories (the catch-all), service state, photos, music |
| `replaceable` | mistakes, losing a machine | every 5 min | yes, 1 month of history | no | installed games, launcher data, persistent VMs, system roots |
| `disposable` | reboots | none | no | no | caches, shader caches, thumbnails, search indexes, build output, scratch, `/nix` |
| `volatile` | nothing | `@blank` only | no | no | system root on impermanent hosts |

On the PCs, local snapshots of both protected classes are released once
homelab has them. The only difference between `irreplaceable` and
`replaceable` is the offsite copy, the one layer that costs money every
month.

What a snapshot costs is what changes or gets deleted while history is
kept, not what the dataset holds. On homelab, `storage` holds 1.22 TB with
0.27 GB in snapshots; homelab's copy of torrent's home holds 2.13 TB with
2.67 TB of history. So `disposable` is for data that churns and rebuilds
itself, where history buys nothing.

How data is classed:
- `disposable` by rule: what machines generate and rebuild on their own
  (caches, indexes, shader caches, thumbnails, build output, scratch).
- `replaceable`: what can be got again, but at a cost in time or effort. By
  rule for installed software and games; otherwise the owner's review.
- `irreplaceable`: everything else. Acquired media isn't replaceable by
  rule, because it changes or disappears at the source. Each host's home
  dataset stays `irreplaceable` as the catch-all, and the other classes are
  carved out of it as child datasets.

## The list

`myDatasets` stays the one place a dataset is declared, keyed by full name,
with a required `class` (no default, as in ADR-0001). It generates:

- the disko entry, for reinstall parity;
- ZFS properties;
- the zrepl snapshot and replication sets (`irreplaceable` only);
- the offsite job's dataset list (`irreplaceable` only);
- the read-only restore export on the receiving host;
- an `environment.persistence` entry on impermanent hosts.

Changes from ADR-0001:

- **Mountpoints anywhere.** Hosts without impermanence mount a dataset
  at its real path (`/home/<user>/.local/share/Steam/steamapps`), not under
  `/nix/state`. Datasets may nest across classes: a `replaceable` Steam
  library can hold an `irreplaceable` Proton-prefix dataset at
  `steamapps/compatdata`, where most non-cloud saves live. Some games save
  inside their own install folder; those get an entry of their own, or the
  save is redirected, as the owner finds them.
- **Names don't carry the class.** The list is the source of truth, and
  renaming a replicated dataset restarts its replication with a full send.
- **Live-data limits.** An entry can carry a `refquota` (live data only, not
  snapshots), used for the agents' dataset. A `quota` would count pinned
  snapshots too, and could fill up while the pool itself was fine.
- **Every declared dataset must be mounted**, and an alert says so if one
  isn't. A missing child mount is silent otherwise: an app writes into the
  parent's directory (a game saving into the unprotected Steam library) and
  the data is unprotected.

## How each spec line is met

### 1–2. Protection

| Loss | Path | Recent work lost |
|---|---|---|
| Mistake, last hour | 5-minute snapshots, on homelab within ~10 min | none to minutes |
| Mistake, noticed later | the backup pool keeps hourly for 2 days, daily for a month, then monthly for a year (`irreplaceable`) | — |
| One machine | the copy on the backup pool; for homelab's irreplaceable data, Backblaze until the backup pool has its own box | ~10 min; for homelab, the offsite job's interval |
| Several machines, or root deleting | Backblaze, where nothing homelab holds can remove or hide a backup | the small job's interval, about an hour, if uploads keep up |

- **Snapshots and replication.** zrepl as today, pull not push. homelab
  pulls every 5 minutes (today 15). History lives on the backup pool:
  - `irreplaceable`: `1x1h(keep=all) | 48x1h | 30x1d | 12x30d`, about a
    year;
  - `replaceable`: `1x1h(keep=all) | 48x1h | 30x1d`, about a month.

  Grids count from the newest snapshot, not the wall clock. zrepl prunes
  per job, so each source serves its two classes as two jobs, and the
  backup host pulls each with its own retention (proved in
  `tests/proofs/zrepl-classes.nix`). Two jobs claiming one client identity
  fail silently: `zrepl configcheck` accepts it, and at runtime one job
  either can't serve or pulls the other's datasets. So a Nix assertion
  keeps identities unique, each identity has its own key, and receiving
  roots don't nest.
- **On every source, homelab included,** a snapshot is released once the
  backup pool has it (`not_replicated` only, no grid), apart from the
  newest one it has. homelab is no different from the PCs here (decision
  1); its backup pool just happens to be in the same box for now.
- **Offsite.** Every `irreplaceable` dataset fleet-wide, sent from homelab
  (from the PCs' replicas on `zbackup` and homelab's own datasets).
  Spec line 2 includes root deleting data, so nothing homelab holds can
  remove or hide a backup (proved in `tests/proofs/offsite-lock.nix`):
  - **kopia to B2 over its S3 API**, one locked bucket per job. Every
    object kopia writes is locked for 30 days, and daily full maintenance
    renews the locks on everything the latest backups still use
    (`--extend-object-locks`). restic works with the same key but never
    renews locks, so old chunks that new backups depend on lapse.
  - **homelab's key can only add:** `listBuckets`, `listFiles`,
    `readFiles`, `writeFiles`, `readFileRetentions`, `writeFileRetentions`,
    `readBucketRetentions`. No `deleteFiles`, `bypassGovernance`,
    `writeBuckets`, `writeBucketRetentions`, `deleteBuckets` or key
    capabilities. Today's job sets the bucket's lifecycle itself, which
    proves its key has `writeBuckets`; it's replaced, not hardened.
  - **A key that can write can also hide.** Hiding everything makes the
    repository look empty, but the locked versions stay. Recovery is
    kopia's read-only point-in-time view with homelab's own key, or
    removing the hide markers with the admin key; both restored
    byte-identical data in the proof.
  - **The admin key lives only outside the fleet** (decision 4). It creates
    the buckets with Object Lock and sets the lifecycle rule that removes
    hidden chunks once their locks lapse, so storage stays bounded while
    nothing in use can go.
  - The 30-day lock is the window to notice a compromise before old data
    could go, separate from the month of history. The vps watch and the
    offsite staleness alert are what notice it. **Small data never waits
  behind a large transfer:** two jobs with separate repositories, a small
  one (home directories, service state, photos) hourly, and a large one
  (music, books) daily, so a multi-hour music upload never holds up a new
  secret in a repo.
- **The way back in** (the offsite repository password, the account login,
  the key that can prune, the sops recovery keys) is held outside the fleet,
  in at least two independent places that don't burn together. A restore
  after losing the house needs nothing from the fleet, and that's
  rehearsed on a clean machine (decision 4: the password manager and two
  YubiKeys kept apart).

### 3. Never in the way

- **Local snapshots pin minutes, not days**, because they're released
  once copied.
- **Away from homelab** (thinkpad travelling, homelab down): snapshots
  pile up locally. A small guard on each PC destroys the oldest local
  snapshots once its pool passes 90%, until it's under 85%. It never
  touches `@blank` or held snapshots. In normal running it never fires,
  because everything older than a few minutes is already gone. When it
  does fire, it's deleting history that exists nowhere else; that's the
  trade the owner accepted for spec line 3, and it always sends an alert
  saying what went. A held snapshot from a stalled transfer can still pin
  space the guard can't free; the pool alert covers that.
- **Replaceable data has no snapshots**, so deleting it frees space
  immediately.
- **The agents' home is its own dataset with a `refquota`.** Their
  scratch, VM images and the USB stick mirror are `replaceable` children
  inside it.

### 4. One pool

- Where data lives is the owner's review, using two questions: would it
  still exist if the fleet vanished, and does something on this machine need
  it fast or offline?
- homelab's `zdata` (9.1 TB free) is where the library and the archive go.
  torrent keeps its working set and software. It already mounts homelab's
  `storage` and `storage-bulk` over the tailnet (`nfs-homelab-mounts`).
- Agents may use space elsewhere in the pool only where it's practical and
  something needs it. Their bulk data needs it now (decision 8): a 1 TB
  `replaceable` dataset on homelab's `zdata`, exported over NFS to torrent
  only, with every access from torrent mapped to the agents' user on
  homelab. torrent automounts it at `~/work/nas`, the owner's `~/Agent/nas`;
  the kernel mounts it, so the agents' egress rules don't change, and it
  can't reach `storage` or `storage-bulk`. When homelab is down it's
  unavailable, which is fine for data that isn't needed fast. First tenant:
  the USB stick mirror (158 GB).

### 5. Restoring and hearing

- **Restore, last hour to a month, without root, for the owner and the
  agents** (proved in `tests/proofs/restore-export.nix`). homelab mounts
  each received dataset read-only (`mount -t zfs -o ro,zfsutil`, as a
  `fileSystems` entry; setting `mountpoint` on it doesn't stick, because
  zrepl resets it on every receive) and exports it with
  `ro,root_squash,crossmnt` to that host's own tailnet IPv4 and IPv6
  addresses only. Snapshots are read by explicit path,
  `.zfs/snapshot/<snap>/...`.
- **Browsing pins snapshots.** Every snapshot read over NFS stays "busy"
  on homelab, so zrepl can't prune it, until the NFS server drops its
  cache: a timer runs `exportfs -f` every 5 minutes. A snapshot actually
  held open stays until it's closed. On torrent they appear under `/backup`, with
  every snapshot browsable. File permissions are preserved, so an agent
  can read only its own files. (NFS trusts the client's numeric uids; root on
  torrent could read all of torrent's replicas, which it can read on torrent
  anyway.) The mount is the kernel's, so the agents' egress rules don't
  change. A `restore <path> [--at <time>]` helper lists
  the versions of a path across snapshots and copies the chosen one back.
- **Disaster.** `scripts/restore-drill` stays the tool for whole datasets
  and drills. It has to clean up its scratch clone even when a run fails: a
  real file restore left `zbackup/restore-drill-249027` behind, pinning a
  two-month-old snapshot. The USB toolbox stick carries the runbook for
  restoring a fresh install from homelab or Backblaze.
- **Hearing.**
  - Pool alerts at 80% and 90% for every pool on every host.
  - Staleness per replicated dataset, and for offsite, the age of the newest
    source snapshot actually secured there, not whether the job ran.
  - Unmounted declared datasets, and every snapshot the guard deletes.
  - History that outlives its retention by more than a day: one check for
    everything that blocks pruning (a leftover clone, a snapshot pinned
    over NFS, a stuck hold).
  - vps notices homelab going silent, and homelab notices vps (decision 5).
  - Before relying on any of these, the alert path itself gets fixed:
    `notify()` must not drop alerts silently (no `--fail`, cooldown written
    before posting), and torrent's and thinkpad's staleness alerts must stop
    sharing a key.

## Hosts

- **torrent.**
  - Home catch-all `irreplaceable`.
  - `replaceable`: the Steam library (Proton prefixes nested back in as
    `irreplaceable`), launcher data, persistent VMs, the system root.
  - `disposable`: caches, Steam's shader cache, the search index, the
    agents' scratch and scratch VMs, `/nix`.
  - The agents' dataset with a 400 GB `refquota`; their bulk data, starting
    with the USB stick mirror, lives on their share on homelab.
  - Impermanence isn't needed for the spec, and stays out of this rework.
- **thinkpad.** The same layout. It's lent out now and holds almost
  nothing irreplaceable. Config-only changes (retention, the guard) arrive
  with its weekly deploy; dataset changes wait until it's back.
- **homelab.**
  - `storage` and the service state are `irreplaceable`.
  - `storage-bulk` is `replaceable`.
  - Its copy is on `zbackup`, in the same box for now (decision 1).
  - Watches vps, and is watched by it (decision 5).
- **vps.** Everything `disposable`, rebuilt from config. Install-time
  secrets are provisioned, never copied.

## Space, before and after (estimates)

| Pool | Now | After |
|---|---|---|
| torrent `zroot` (3.6 TB) | ~2.3 TB live, up to 1.25 TB pinned | ~1.45 TB live once music has left, minutes pinned |
| homelab `zbackup` (10.9 TB) | 8.61 TB (78%) | about 3.3 TB plus churn (~30–35%): the PCs ~1.5 TB, `storage` 1.23 TB, `storage-bulk` 0.45 TB, state 0.06 TB |
| homelab `zdata` (10.8 TB) | 1.66 TB | grows as the library moves in |
| Backblaze | homelab `storage` and `state` | about 2 TB, roughly $13–15 a month: adds torrent's irreplaceable home (~0.65 TB, shrinking as the owner reviews it) |

## Deleted

| Part | Why | What would bring it back |
|---|---|---|
| `zfs-emergency-prune` | Destroys snapshots homelab hasn't received; replaced by release-on-copy and the guard | A pool full of copied snapshots, which release-on-copy prevents |
| `retention.source` / `ceiling` / `archive` | Replaced by one history preset and release-on-copy | — |
| zrepl push, sink, tcp, tls roles | Unused | A host a puller can't reach |

## Decisions (2026-10-26)

1. **homelab's copy stays on `zbackup` for now.** The owner wants a
   separate backup machine later, when it's affordable. Until then
   homelab's data has its copy in the same box: it survives a failed disk
   pair, not the laptop or enclosure dying, and not root on homelab.
   Irreplaceable data still survives that through Backblaze; `storage-bulk`
   doesn't. The backup pool is a role (a receiving host with its pool), not
   something tied to homelab, so moving it to its own box later changes
   config, not the design.
2. **`storage-bulk` is `replaceable`.**
3. **The owner's persistent VMs are `replaceable`;** the agents' scratch
   VMs are `disposable`.
4. **The way back in:** the password manager plus two YubiKeys kept in
   different places, one away from the house. Its account recovery mustn't
   depend on anything in the house. A restore onto a clean machine is
   rehearsed once.
5. **vps and homelab watch each other.** vps is offsite and on the
   tailnet: it checks homelab every few minutes and alerts through the
   existing Discord webhook, and homelab watches vps the same way. That
   still alerts when the house loses power or internet.
6. **The agents get 400 GB of live data on torrent** (`refquota`).
7. **History:** `irreplaceable` keeps a year (monthly after the first
   month) on the backup pool; `replaceable` keeps a month; offsite keeps a
   month. Long history on irreplaceable data is cheap once the churn is
   split out (`storage`, 1.2 TB, has 1.78 GB of history). Claude Code's
   transcript retention was already raised at the source.
8. **The agents get a 1 TB share on homelab** for bulk data that isn't
   needed fast locally, `replaceable`, mounted at `~/work/nas`. It adds an
   NFS export, so its PR gets a security review and another model family's
   review, and the top-level layout in the shared agent instructions gains
   `nas/` in the same PR.

9. **Offsite lock mode** (open). Compliance: nobody, not even the admin
   key, can delete locked data before its date. Governance: the admin key
   (`bypassGovernance`) can, to clean up a mistake. Only compliance was
   tested.

## To prove before building

- **Proved:** NFS export of a received dataset's snapshots, with the
  changes above (`tests/proofs/restore-export.nix`). Mounting each snapshot
  separately was rejected: a mounted snapshot is never pruned. Not covered:
  whether pins clear without `exportfs -f`, and real tailnet addresses.
- **Proved against a local S3 server** (versitygw, with real versioning
  and Object Lock): the offsite setup above (`tests/proofs/offsite-lock.nix`).
  Still to check once with a real B2 key: that B2's S3 API treats a plain
  delete as a hide and refuses a versioned one, which the B2 docs don't
  state.
- **Proved:** zrepl with two jobs per class (`tests/proofs/zrepl-classes.nix`).
  The source never held more than one snapshot per dataset; a deleted
  500 MiB file freed its space within seconds while the copy kept it; each
  class's copy followed its own grid; after an outage the local cap held the
  pile at its limit, and catch-up was incremental from the cursor bookmark
  even after the cap destroyed the cursor's snapshot; an interrupted
  transfer resumed from its token and released its holds. A stalled
  transfer's holds pin space nothing local can free; the pool alerts cover
  that. zrepl logs routine probe errors in steady state, so alerts watch
  replica age, not zrepl's log.

## Order of changes

Each step is its own PR, branched from `master` after the previous one
merges. Local snapshots only shrink once restoring from the backup pool
works.

1. **Relief and alerts**, once the transcript-mining session is done.
   - First, by hand on homelab: destroy the leftover restore clones under
     `zbackup/restore-drill-249027`. They pin torrent's home as of
     2025-08-25 and would block the prune.
   - History on the backup pool cut to a month for everything. This frees
     most of `zbackup` on the first prune: `storage-bulk`'s copy alone holds
     1.84 TB of history against 451 GB live. `irreplaceable` gets its year
     only in step 3, once the churn is split out of it; before that, a year
     would keep Steam's and the VMs' churn.
   - The PCs' local snapshots cut from ~9 days to one day for now.
   - 5-minute pulls; pool alerts with `notify()` fixed; vps and homelab
     watching each other; `zfs-emergency-prune` removed.
2. **Restore.** The read-only export, `/backup`, the `restore` helper, and
   the USB toolbox runbook. Then every source switches to release-on-copy,
   with the guard on the PCs.
3. **The list** (`myDatasets`, three classes), torrent's carve-outs, the
   agents' dataset and their share on homelab (the stick mirror moves
   there, with the USB toolbox pointed at it), with a migration script the
   owner runs with `run0`. Existing replicas on `zbackup` are renamed into
   the per-class receiving roots before the new jobs start; otherwise the
   first pull finds no common snapshot and starts over.
   Then `irreplaceable` gets its year of history.
4. **Offsite**: the new setup, then the PCs' data, then the clean-machine
   restore.
5. Later, when affordable: the backup pool moves to its own machine.

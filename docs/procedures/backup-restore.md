# Restoring from backup

Getting data back out of `zbackup` (zrepl) or Backblaze (restic). For how
the backups are produced, see [`docs/backups.md`](../backups.md).

**`scripts/restore-drill` is the restore tooling, and this document is
its runbook.** The same script is both the periodic fire drill and the
real recovery procedure — drill mode is just the real commands pointed at
scratch destinations with verification and cleanup added, so exercising
the drill exercises the real thing and the two can't drift apart
(plan: 2026-08-25-build-and-test-a-full-restore-suite-scripts-proced.md).
It runs from an operator machine and does everything over
`ssh root@homelab` (`RESTORE_DRILL_HOST=root@<addr>` overrides the
target — useful when the sink is rebuilt or only reachable by IP), where
`zbackup` and the restic wrapper live.

Every restore path below was first exercised against real backup data on
2026-09-09. Run the whole drill periodically (and after any change to
the backup stack) with:

```
scripts/restore-drill drill        # all paths, scratch targets, PASS/FAIL summary
scripts/restore-drill cleanup      # remove scratch after an interrupted run
```

An all-PASS `drill` touches `/var/lib/restore-drill/last-drill-success`
on homelab, and `myHealthAlerts.staleMarkerFiles` alerts once that
marker is 90 days old — so an overdue drill pages like any other backup
staleness instead of relying on anyone remembering this paragraph.

A destination argument (`--dest`/`--to`) selects a real restore and
requires that subcommand's full argument set — a recovery never
silently inherits a drill default. Without one the subcommand drills;
`--src`/`--snap`/`--id` alone just point the drill at other data.

Scratch lives under `zbackup/restore-drill` (tagged with a
`org.dotfiles:restore-drill` ZFS property that cleanup verifies before
destroying anything) and `/mnt/restore-drill` on homelab; it is torn
down at exit unless `--keep` holds it for inspection. Real backups
are only ever read.

## First: work out where the data is

Everything zrepl received lives under `zbackup/backup/<host>/<full source
dataset path>`. That last part trips people up — the tree is deeper than
the old syncoid names:

```
zbackup/backup/torrent/zroot/local/home      # NOT .../torrent/home
zbackup/backup/thinkpad/zroot/local/root
zbackup/backup/homelab/zdata/storage/storage
```

List what's actually there before planning anything:

```
zfs list -r -t filesystem zbackup/backup
zfs list -r -t snapshot zbackup/backup/torrent/zroot/local/home | tail
```

Snapshots are named `zrepl_<timestamp>`. Anything named `autosnap_*` is
leftover sanoid history; `@blank` is an impermanence rollback point, not a
backup.

## Recovering a few files

```
scripts/restore-drill file --src zbackup/backup/torrent/zroot/local/home \
  --glob '*/lilijoy/some/path/*' --dest /where/to/put/them
```

A real recovery needs `--src`, `--glob` and `--dest` together; bare
`file` drills instead (a few sample files to scratch). Either way the
newest `zrepl_*` snapshot is used unless `--snap <name>` picks one, and
every copied file is `cmp`-verified against the snapshot before the
script reports success.

What it runs, and why not to improvise it by hand: backup datasets are
deliberately never mounted, and everything under `zbackup` is
`mountpoint=none` — so a bare `zfs clone` gives you a clone you can't
read. The working form needs explicit properties:

```
zfs clone -o readonly=on -o mountpoint=<scratch> <snap> zbackup/restore-drill/file-clone
# ... copy out ...
zfs destroy zbackup/restore-drill/file-clone
```

A clone is cheap — it shares blocks with the snapshot and costs only what
you change. Destroy it when done, or it pins the snapshot it came from.
(`.zfs/snapshot/` also works, but only on datasets that are actually
mounted, which `zbackup`'s never are — it's the right tool on a *source*
host's own datasets, e.g. recovering from torrent's local snapshots.)

## Rolling a host's dataset back in place

Destroys everything written since the snapshot. Deliberately not wrapped
in the script
(2026-08-25-build-and-test-a-full-restore-suite-scripts-proced.md#D1) —
make sure this is what you want, then on the affected host:

```
zfs rollback -r zroot/local/home@zrepl_...
```

`-r` destroys any newer snapshots in the way. If the snapshot you want is
only on `zbackup` and no longer on the host, you need a full restore
instead. The drill's `rollback` mode proves the snapshot → mutate →
rollback mechanics on a scratch dataset each run.

## Restoring a whole dataset

**Onto homelab** (including anywhere on `zbackup`/`zdata`):

```
scripts/restore-drill dataset --src zbackup/backup/torrent/zroot/local/home \
  --to zdata/home-restored
```

Runs `zfs send -c | zfs recv -u -o mountpoint=none -o readonly=on` into a
**new** dataset (it refuses to touch an existing one; `-c` sends blocks
as stored on disk — measured ~2:1 stream shrink on lz4 datasets), then proves
integrity by comparing the source and received snapshots' GUIDs — ZFS
preserves the GUID through send/recv, so equality is an end-to-end
identity check. Inspect the data, then `zfs set` mountpoint/readonly and
`zfs rename` into place once satisfied. Drill mode also clones both
sides and readback-verifies them with an `rsync --checksum` dry-run —
content plus permissions, owners, xattrs, ACLs, hardlinks and special
files, the metadata a byte-diff can't see.

**Onto another host** (torrent/thinkpad): those hosts only accept root
SSH for zrepl's forced command — homelab *cannot* push a stream into
them. Pull instead, from the target host (root via `run0`):

```
scripts/restore-drill stream --src zbackup/backup/torrent/zroot/local/home \
  | run0 zfs recv -u -o mountpoint=none -o readonly=on -o canmount=off \
      zroot/local/home-restored
```

`stream` is a raw `zfs send` on stdout over SSH from homelab. The `-o`
overrides matter: a send stream's bytes come entirely from the sink, so
never let one choose where or how the received dataset mounts
(2026-08-25-build-and-test-a-full-restore-suite-scripts-proced.md#F3) —
inspect first, then deliberately `zfs set canmount=on readonly=off` and
a real `mountpoint`. Restoring alongside the original (`-restored`)
rather than over it is the safe
default — compare, then swap mountpoints or `zfs rename` once satisfied.
Only `zfs recv -F` directly onto the live dataset if you have accepted
losing whatever is currently there, and **stop zrepl on the target host
first** (`systemctl stop zrepl`) so its jobs don't race you; restart it
when done. Expect the next replication run to reconcile — if the restored
dataset has diverged from what `zbackup` holds, zrepl reports a conflict
and waits for a decision rather than clobbering, which is intended
behaviour, not a fault.

Timing, measured: 5.0G restored in ~2.5min (drill default); a
multi-terabyte send has previously taken ~40 hours (see
`2026-08-21-torrent-s-initial-full-backup-send-to-homelab-is-t.md`) —
run big ones under `tmux`.

## Restoring from the offsite restic backup

Only `zroot/local/state` and `zdata/storage/storage` go offsite —
`storage-bulk` does not, and neither does anything from `torrent` or
`thinkpad`. Backblaze is the last resort, for when `zbackup` itself is
gone.

```
scripts/restore-drill restic --include '/run/restic-backups-backblazeWeekly/zroot/...' \
  --dest /restore
```

A real restore needs `--include` and `--dest` together (`--id
<short-id>` picks a snapshot, newest otherwise); bare `restic` drills —
restores one small real file to scratch and verifies its size. Under
the hood it uses the preconfigured
`restic-backblazeWeekly` wrapper on homelab (`createWrapper = true`
wires the repository and credentials), which is also what to use by hand
for browsing:

```
restic-backblazeWeekly snapshots
restic-backblazeWeekly ls <snapshot-id> /run/restic-backups-backblazeWeekly
restic-backblazeWeekly restore <snapshot-id> --target /restore --include <path>
```

Paths inside the repo reflect the temporary snapshot-mount layout used at
backup time — `/run/restic-backups-backblazeWeekly/<dataset
path>@<zrepl-snapshot>/...` (top level: `includes`, `zdata`, `zroot`) —
not the live filesystem layout, and the `@<snapshot>` component changes
every run, so browse with `ls` before restoring to target the right
subtree.

Retention there is `--keep-daily 2`, meaning two weekly runs — roughly two
weeks of offsite history, not two days.

## After any restore

- Check `myHealthAlerts` stops reporting staleness on the affected dataset
  within a couple of cycles (it runs every 15 minutes).
- If you rolled back or replaced a dataset that zrepl replicates, confirm
  the next pull succeeds rather than reporting a conflict:
  `journalctl -u zrepl -n 50` on homelab.
- Record what happened in the affected host's `hosts/<name>/README.md` if
  it revealed anything worth knowing next time, per
  `docs/procedures/updating-documentation.md`.

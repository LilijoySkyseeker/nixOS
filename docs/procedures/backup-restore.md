# Restoring from backup

Getting data back out of `zbackup` (zrepl) or Backblaze (restic). For how
the backups are produced, see [`docs/backups.md`](../backups.md).

> **Written from the mechanics, not yet exercised.** The zrepl layout it
> describes is not deployed at time of writing (see `TODO.md`). The `zfs`
> commands are standard, but nobody has done a real restore against this
> layout yet — verify each step's output rather than pasting the whole
> sequence, and correct this doc once a restore has actually been done.

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

Cheapest option, no rollback, no send/recv. Every ZFS filesystem exposes
its snapshots read-only under `.zfs/snapshot/`:

```
ls /zbackup/backup/torrent/zroot/local/home/.zfs/snapshot/
cp -a /zbackup/backup/torrent/zroot/local/home/.zfs/snapshot/zrepl_.../path/to/file  /somewhere
```

If the dataset isn't mounted (backup datasets normally aren't), either
mount it read-only or clone the snapshot:

```
zfs clone zbackup/backup/torrent/zroot/local/home@zrepl_... zbackup/restore-scratch
# ... copy what you need out of /zbackup/restore-scratch ...
zfs destroy zbackup/restore-scratch
```

A clone is cheap — it shares blocks with the snapshot and costs only what
you change. Destroy it when done, or it pins the snapshot it came from.

## Rolling a host's dataset back in place

Destroys everything written since the snapshot. Make sure that's what you
want.

```
zfs rollback -r zroot/local/home@zrepl_...
```

`-r` destroys any newer snapshots in the way. If the snapshot you want is
only on `zbackup` and no longer on the host, you need a full restore
instead.

## Restoring a whole dataset back to a host

This sends from `zbackup` back to the source host — the reverse of normal
replication. **Stop zrepl on the target host first**, or its jobs will race
you:

```
systemctl stop zrepl
```

Then send. Run this on homelab, where `zbackup` lives:

```
zfs send zbackup/backup/torrent/zroot/local/home@zrepl_... \
  | ssh root@torrent zfs recv -F zroot/local/home-restored
```

Restoring alongside the original (`-restored`) rather than over it is the
safe default — you can compare, then swap mountpoints or `zfs rename` once
satisfied. Only `zfs recv -F` directly onto the live dataset if you have
accepted losing whatever is currently there.

For a large dataset add `-v` for progress, and consider running it under
`tmux` — a multi-terabyte send over this hardware has previously taken
~40 hours (see `TODO.md`).

Restart zrepl when done:

```
systemctl start zrepl
```

Expect the next replication run to reconcile. If the restored dataset has
diverged from what `zbackup` holds, zrepl will refuse rather than clobber —
it reports a conflict and needs a decision, which is the intended
behaviour, not a fault.

## Restoring from the offsite restic backup

Only `zroot/local/state` and `zdata/storage/storage` go offsite —
`storage-bulk` does not, and neither does anything from `torrent` or
`thinkpad`. Backblaze is the last resort, for when `zbackup` itself is gone.

`createWrapper = true` in the restic config means a preconfigured
`restic-backblazeWeekly` wrapper exists on homelab with the repository and
credentials already wired:

```
restic-backblazeWeekly snapshots
restic-backblazeWeekly restore <snapshot-id> --target /restore
```

Paths inside the repo reflect the temporary mount layout used at backup
time (`/tmp/restic/<dataset>@<snapshot>/...`), not the live filesystem
layout — browse with `restic-backblazeWeekly ls <snapshot-id>` before
restoring so you target the right subtree.

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

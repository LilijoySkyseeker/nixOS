# homelab

Old laptop with usb HDD enclose used as main server.

## Hardware

MSI GL62M 7RD laptop:

- **CPU**: Intel Core i5-7300HQ (4 cores/4 threads, 2.50GHz)
- **RAM**: 16GB
- **GPU**: Intel HD Graphics 630 (iGPU) + NVIDIA GeForce GTX 1050 Mobile
- **Boot disk**: 256GB Samsung SATA SSD (`zroot`, single-disk ZFS pool)
- **Storage**: 4x 12TB HGST enterprise drives (HUH721212ALE601, USB attached),
  in two 2-disk ZFS mirrors (`zdata`, `zbackup`)

## Backups

This host is the backup target and the active side of all replication —
see [`docs/backups.md`](../../docs/backups.md) for the full picture and
[`docs/procedures/backup-restore.md`](../../docs/procedures/backup-restore.md)
for getting data back out.

It **pulls** from `torrent` and `thinkpad` rather than being pushed to, so
it holds an SSH key for them (`homelab_zrepl_key`) and they hold none for
it. It also replicates its own datasets into `zbackup` over zrepl's
in-process `local` transport.

`zbackup` lives on USB-attached drives sharing one hub, which is a known
throughput and I/O-contention constraint (see `TODO.md`) — it is why
replication runs on a 15m interval separate from the 5m snapshot cadence,
and why the archive retention grid is tiered rather than a flat year of
dailies.


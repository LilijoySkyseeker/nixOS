# homelab

Old laptop with usb HDD enclose used as main server.

## Hardware

MSI GL62M 7RD laptop:

- **CPU**: Intel Core i5-7300HQ (4 cores/4 threads, 2.50GHz)
- **RAM**: 16GB
- **GPU**: Intel HD Graphics 630 (iGPU) + NVIDIA GeForce GTX 1050 Mobile
- **Boot disk**: 256GB Samsung SATA SSD (`zroot`, single-disk ZFS pool)
- **Storage**: 4x 12TB HGST enterprise drives (HUH721212ALE601) in a
  TerraMaster TDAS enclosure, USB attached behind an ASMedia ASM107x hub,
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

`zbackup` lives on USB-attached drives sharing one hub. This used to be a
severe throughput and I/O-contention constraint: all four drives ran at USB
2.0 High-Speed (480 Mbps) on a single upstream link, a hard ~40-60MB/s
ceiling *across all four combined*, with recurring `uas_eh_abort_handler` /
`stat urb: status -71` faults on the same link.

**Resolved in hardware on 2026-08-23 by replacing the enclosure's USB
cable.** All four drives now enumerate at 5000 Mbps (USB 3.0 SuperSpeed) on
bus 2, and the fault class is gone — zero `uas_eh_*`/urb errors across the
23h following the change, all pools healthy. Verify with:

```
for d in /sys/bus/usb/devices/*/; do [ -f "$d/speed" ] &&   echo "$(basename $d) $(cat $d/speed) $(cat $d/product 2>/dev/null)"; done
```

The four `TerraMaster TDAS` entries should read `5000`; `480` means the link
has renegotiated down (a marginal cable/port) and the old ceiling is back.

The conservative replication settings chosen under the old ceiling are still
in place — replication runs on a 15m interval separate from the 5m snapshot
cadence, and the archive retention grid is tiered rather than a flat year of
dailies. Those are no longer forced by the hardware and could be revisited,
but they have not been re-tuned; see
`2026-08-23-replace-sanoid-syncoid-with-zrepl-repo-wide.md`.


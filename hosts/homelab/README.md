# homelab

## Hardware

MSI GL62M 7RD laptop:

- **CPU**: Intel Core i5-7300HQ (4 cores/4 threads, 2.50GHz)
- **RAM**: 16GB
- **GPU**: Intel HD Graphics 630 (iGPU) + NVIDIA GeForce GTX 1050
  Mobile
- **Boot disk**: 256GB Samsung SATA SSD (`zroot`, single-disk ZFS pool)
- **Storage**: 4x 12TB HGST enterprise drives (HUH721212ALE601, USB
  attached), in two 2-disk ZFS mirrors (`zdata`, `zbackup`)

## Known issues

### zdata pool: recurring I/O suspensions (since 2026-08-07)

`dmesg` on homelab shows the `zdata` pool repeatedly hitting
`WARNING: Pool 'zdata' has encountered an uncorrectable I/O failure and
has been suspended.`:

- 2026-08-07: multiple suspensions (18:12, 18:12, 19:06, 20:29 x3)
- 2026-08-08: 02:01
- 2026-08-13: 19:19
- 2026-08-15: 20:20 (during a routine config switch — see below)

On **2026-08-11 16:53:40**, four drives faulted together on the same
command:

```
sd 8:0:0:0: [sdf] Synchronize Cache(10) failed: Result: hostbyte=DID_ERROR driverbyte=DRIVER_OK
sd 9:0:0:0: [sdg] Synchronize Cache(10) failed: Result: hostbyte=DID_ERROR driverbyte=DRIVER_OK
sd 10:0:0:0: [sdh] Synchronize Cache(10) failed: Result: hostbyte=DID_ERROR driverbyte=DRIVER_OK
sd 11:0:0:0: [sdi] Synchronize Cache(10) failed: Result: hostbyte=DID_ERROR driverbyte=DRIVER_OK
```

Four drives failing the same command simultaneously points to a shared
component — HBA/controller, backplane, or power to that drive group —
rather than a single failing disk. A suspended pool blocks all `zfs`/
`zpool` commands (they hang instead of erroring), so anything touching
ZFS (syncoid, restic's snapshot mount/unmount, scrubs) queues up and
stalls until the pool clears or the box is rebooted.

**Root cause identified (2026-08-21): power loss to the external
enclosure, not a hardware fault.** homelab itself is a laptop with a
battery, so it rides through a brief power blip — but the 4-drive USB
enclosure holding all these disks has no battery backup of its own. A
momentary outage drops the enclosure (and every drive in it
simultaneously) while homelab keeps running, which is exactly the
"multiple drives fault on the same command at the same instant"
signature seen both on 2026-08-11 and again on **2026-08-18 08:27-08:28**
(`sdb`/`sdc`/`sde` — 3 of 4 drives — hit `uas_eh_abort_handler`/device
resets within ~90 seconds of each other; see the USB troubleshooting
section below for the log excerpt). This explains the "shared
component" multi-drive pattern without needing to suspect a bad HBA,
backplane, or a real multi-disk hardware failure — it's simply
whatever's powering that enclosure. A UPS or otherwise more stable
power feed for the enclosure specifically (not just the laptop) would
likely prevent this class of incident going forward.

**2026-08-15 incident:** a routine flake update + `nixos-rebuild switch`
restarted the syncoid/restic systemd units as part of normal service
activation. Because the pool was mid-suspend, those units (and every
`zfs` invocation they spawned) hung in uninterruptible (`D`) state
instead of failing cleanly, wedging `switch-to-configuration` for over
an hour. A reboot was used to clear it.

**Not yet done:** physical investigation of the HBA/backplane/power
for the `sdf`–`sdi` drive group, and a `zpool status`/`smartctl` check
on all drives once the pool is next healthy and not suspended, to rule
out a legitimate multi-disk hardware fault.

### USB enclosure: High-Speed (USB 2.0) link, shared across all 4 drives (found 2026-08-21)

Confirmed via `lsblk -o TRAN` (= `usb` for all four HGST drives) and
`/sys/bus/usb/devices/*/speed` (= `480`, i.e. USB 2.0 High-Speed, not
USB 3.x SuperSpeed) that all four drives — both `zdata`'s and
`zbackup`'s — share one hub on a single USB 2.0 upstream link
(`1-6.1` through `1-6.4`). That's a hard ~40-60MB/s ceiling across all
four drives *combined*, not per-drive. Found while investigating why
torrent's first `myBackupPush` full send (3.13TB) was only sustaining
~20-40MB/s despite a direct LAN connection, idle CPU on both ends, and
individual disk write rates well under HDD capability — see `TODO.md`
for the full investigation.

A single-drive reset also landed on `sdd` (part of `zbackup`) at
2026-08-21 14:41:36, ~35 minutes into that same transfer — same
`uas_eh_abort_handler`/`reset high-speed USB device` signature as the
multi-drive power-loss events above, but isolated to one drive this
time rather than several at once, so not obviously the same power-loss
cause. Actively being traced — see `TODO.md`.

**If revisited:** a real USB 3.0 (SuperSpeed) link, or moving this
enclosure to direct SATA/HBA passthrough, would remove the bandwidth
ceiling entirely and likely help with the reset frequency too (USB 2.0
links pushed near their ceiling for hours at a time are more prone to
protocol-level faults than ones with headroom).

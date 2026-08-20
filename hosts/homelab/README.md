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

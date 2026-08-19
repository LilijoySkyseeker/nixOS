# homelab

## Secure Boot setup (lanzaboote, one-time manual steps)

`configuration.nix` declares `boot.lanzaboote.enable = true`, but
lanzaboote can't take effect purely declaratively — it needs manual
steps on this physical machine, in this order (see
nix-community/lanzaboote's own `docs/getting-started/`), done last
after thinkpad and torrent proved the process out — this box runs
always-on services, so it carries the most disruption risk if boot
breaks:

1. `sudo sbctl create-keys` — generates this machine's Secure Boot
   keys into `/var/lib/sbctl` (the `pkiBundle` path this config
   points at), before the first `nixos-rebuild switch` carrying this
   config.
2. `nixos-rebuild switch` — replaces systemd-boot with lanzaboote's
   signed UKI entries. Firmware enforcement isn't on yet, so this
   boots fine either way.
3. Reboot into firmware and put Secure Boot into *Setup Mode* —
   either an explicit "Reset to Setup Mode" option, or erasing the
   existing Platform Key (PK) if there's no explicit toggle; exact
   menu wording depends on this board's firmware. **Do not** wipe the
   Forbidden Signature Database (dbx) while doing this. Save and exit.
4. Boot back into NixOS, then `sudo sbctl enroll-keys --microsoft`.
5. Reboot. Verify with `sudo sbctl verify` and `bootctl status`
   (`Secure Boot: enabled (user)`).

Only after this is confirmed working should the TPM2 auto-unlock work
(Phase 2, not yet implemented — also touches the zdata/zbackup
encryption plan, so hold off until the I/O-suspension issue below is
resolved and ruled out as a hardware fault) be enrolled on this host.
Treat this as beta — same caveats as thinkpad's README.

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

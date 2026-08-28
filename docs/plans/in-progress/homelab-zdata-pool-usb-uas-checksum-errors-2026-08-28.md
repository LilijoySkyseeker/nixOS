---
slug: homelab-zdata-pool-usb-uas-checksum-errors
created: 2026-08-28
status: in-progress
frozen: false
---

# homelab zdata pool USB/UAS checksum errors

## Original plan

Triggered by a health-alert email: `zpool status` on `homelab` reported
`zdata` ONLINE but with CKSUM errors on both mirror members ("One or more
devices has experienced an unrecoverable error... Applications are
unaffected"). Investigate root cause, document findings, and decide
whether/how to fix.

Alert as received:
```
  pool: zdata
 state: ONLINE
status: One or more devices has experienced an unrecoverable error.  An
    attempt was made to correct the error.  Applications are unaffected.
action: Determine if the device needs to be replaced, and clear the errors
    using 'zpool clear' or replace the device with 'zpool replace'.
   see: https://openzfs.github.io/openzfs-docs/msg/ZFS-8000-9P
  scan: scrub repaired 0B in 11 days 16:51:37 with 0 errors on Tue May 12 17:22:23 2026
config:
    NAME                              STATE     READ WRITE CKSUM
    zdata                             ONLINE       0     0     0
      mirror-0                        ONLINE       0     0     0
        wwn-0x5000cca26fd26b20-part1  ONLINE       0     0    22
        wwn-0x5000cca26fe3d464-part1  ONLINE       0     0    27
errors: No known data errors
```

## Progress
- [x] Confirmed pool health via `zpool status -v` on all three pools (zdata/zbackup/zroot)
- [x] Mapped wwn IDs on the errored devices to physical disk serials
- [x] Pulled SMART data on all four zdata+zbackup HDDs
- [x] Checked dmesg/journalctl for ATA/USB link errors
- [x] Identified physical transport (USB, not SATA) as the likely differentiator
- [ ] Decide on remediation (D1)
- [ ] Apply fix if approved, then `zpool clear zdata`
- [ ] Confirm no error recurrence after a full scrub cycle

## Decisions (D)
### D1 -- how to remediate: apply USB UAS quirk, just clear errors, or investigate further first?
**DISCUSSED 2026-08-28:** three options laid out with tradeoffs (quirk+reboot
vs. clear-only vs. more diagnosis first). User chose to investigate further
before deciding -- not yet answered.


**ANSWERED 2026-08-28:** User chose to apply the usb-storage.quirks=174c:55aa:u kernel param (force BOT mode, disable UAS) for the TerraMaster USB enclosure, then zpool clear once deployed and confirmed stable.

## Gotchas (G)
### G1 -- all four zdata/zbackup HDDs are USB-attached, not SATA
`lsblk -S -o NAME,SERIAL,HCTL,TRAN` shows `TRAN=usb` for sdb/sdc/sdd/sde
(only the boot NVMe/SSD, sda, is native `sata`). They live in a TerraMaster
4-bay USB enclosure ("TDAS", USB vendor:product `174c:55aa`, ASMedia
ASM107x bridge) attached via a single USB3 hub, bound to the kernel's `uas`
driver (scsi hosts 4-7). UAS bridge-chip firmware (ASMedia/JMicron in
particular) has a well-known history of silently corrupting in-flight data
under load -- below the SATA link layer, so SMART/UDMA_CRC never see it,
but ZFS's own checksum does. This matches the observed signature exactly.

### G2 -- errors are isolated to one mirror vdev, not one disk
Both errored devices (`8CH9J1UE`/sdb CKSUM=22, `8CJJUE6E`/sde CKSUM=27) are
in the `zdata` mirror. The other two physical disks in the *same*
enclosure/hub, on the separate `zbackup` mirror (`8CK6DXTF`/sdd,
`2AHDD1AY`/sdc), are completely clean -- 0 CKSUM/READ/WRITE. This argues
against "just replace a failing disk" and toward a
transport/bridge/enclosure-level cause.

### G3 -- SMART is clean on all four disks, including UDMA_CRC_Error_Count=0
Reallocated_Sector_Ct, Current_Pending_Sector, Offline_Uncorrectable, and
UDMA_CRC_Error_Count are all 0 on every drive (`8CH9J1UE`, `8CJJUE6E`,
`8CK6DXTF`, `2AHDD1AY`), and SMART overall-health is PASSED on all four.
A failing drive or bad SATA cable almost always shows up as nonzero
UDMA_CRC_Error_Count first -- its absence here is evidence *against* a
simple physical-media or cable explanation, and consistent with
corruption happening in the USB/UAS translation layer instead (which
SMART/ATA-level counters can't see).

### G4 -- serial numbers for all four zdata/zbackup HDDs (model HUH721212ALE601, 12TB)
| disko name | serial      | pool    | device | zpool CKSUM |
|---|---|---|---|---|
| hdd-a | `8CH9J1UE` | zdata   | sdb | 22 |
| hdd-b | `8CJJUE6E` | zdata   | sde | 27 |
| hdd-c | `8CK6DXTF` | zbackup | sdd | 0 |
| hdd-d | `2AHDD1AY` | zbackup | sdc | 0 |

### G5 -- no ATA link resets or USB disconnect/reset events found
`dmesg -T` and `journalctl -k --since -30d` show no `ata*` link-down/reset
events on sdb/sde beyond normal boot enumeration, and no USB
disconnect/reset/over-current events for the enclosure. The corruption
(if UAS-related) isn't accompanied by any visible link-layer symptom,
which is itself typical of this class of UAS bridge bug -- it happens
silently within a "successful" transfer, not as a dropped/retried one.

### G6 -- CKSUM counters (22/27) are a lifetime total since pool creation, never cleared
`zpool history zdata` shows the pool was created 2024-07-29 and contains
no `zpool clear` entry, ever. So 22 and 27 CKSUM errors represent the
*entire ~25-month life of the pool*, not a recent burst -- averaging
roughly 1 per month per disk. That's a slow, low-grade trickle, not an
accelerating failure. Also notable: 21 separate `zpool import -N` boot
events over that lifetime (one per reboot), clustered unusually tightly on
2026-08-24 (4 imports within 50 minutes) and 2026-08-26 (2 imports) --
consistent with recent config/deploy work in this repo around that date
rather than crash-looping, but worth keeping in mind as context.

### G7 -- kernel's live checksum-ereport ring buffer holds nothing (as expected)
`zpool events zdata | grep checksum` returns 0 matches -- the in-kernel
zfs event ring buffer only covers the current boot (system has been up
since 2026-08-26 13:51, ~1 day 21h at time of writing) and the errors
predate it (per G6). Not a sign the events never happened, just that the
live ring buffer rotated past them; the CKSUM counters in `zpool status`
are the durable record.

### G8 -- external research corroborates the UAS/enclosure-power theory
[TerraMaster forum reports](https://forum.terra-master.com/en/viewtopic.php?t=5830)
and multiple kernel-list/distro threads describe the same failure class
for ASMedia-bridge USB enclosures (`174c:55aa` covers several ASMedia
SATA-bridge chips, some with broken UAS and some fixed, auto-detected by
kernel quirk heuristics): under heavy I/O, corruption/resets appear with
no clean disconnect event, because **the bridge chip itself is powered
from the USB port while only the drives get power from the enclosure's
own supply** -- so bus-side power sag under load can glitch the bridge
without ever dropping the disks. This matches G5 (no link resets/
disconnects, "silent" corruption) exactly, and is a documented,
common issue for this device family, not a one-off. Reported fix is the
same `usb-storage.quirks=<vid>:<pid>:u` forced-BOT-mode workaround, at a
reported ~20-30% throughput cost.

### G9 -- verify-ladder's `nix flake check` step is red, but pre-existing and unrelated
Added `boot.kernelParams = [ "usb-storage.quirks=174c:55aa:u" ]` to
`hosts/homelab/configuration.nix` (merged into the existing `boot = { ... }`
block alongside `extraModprobeConfig` to avoid a new statix repeated-key
warning). `nixfmt --check`, statix/deadnix (diff-scoped), and a targeted
`nixos-rebuild build --flake .#homelab` all pass cleanly. `nix flake check
--no-build` fails on `checks.x86_64-linux.zrepl-replication` with `path
'...-yybhs1ybhvk6w56gjywq2x9ipdpx6dd9-source' is not valid` -- confirmed via
`git stash` that this reproduces identically on `master` with this change
completely absent, so it's a pre-existing local-store/network gap for an
unrelated zrepl VM test, not something this change introduced.

### G10 -- root-caused the pre-existing `nix flake check` failure; it's a Nix-version/tooling issue, not a repo bug
Per-user request, dug further into the G9 failure before committing.
`--show-trace` pinpoints the exact site: `tests/zrepl-replication.nix:48`
does `import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs` -- an old-style
string-interpolation reference into a flake input's path. Evaluating that
requires Nix to "realise the context" of the referenced store path
(`09g0q2nr523x5inkal66127xmq2z8gw0-yybhs1ybhvk6w56gjywq2x9ipdpx6dd9-source`),
which fails outright ("is not valid") rather than fetching/copying it in.
Ruled out:
- General store writes/builds are fine -- the same run's `nixos-rebuild
  build --flake .#homelab` succeeded and copied/built dozens of paths.
- Not a network problem -- `curl` to releases.nixos.org succeeds, and
  `--refresh` doesn't change the outcome.
- Not `lazy-trees` (my leading theory): `--option lazy-trees false`
  produced `warning: unknown setting 'lazy-trees'` -- that setting name
  doesn't exist on this Nix (2.34.8), so it's not what's at play.
- No matching upstream Nix issue found on a search for this exact error
  signature combined with `pkgs.path` + nixos test framework + this Nix
  version.
Conclusion: this is a real but narrow compatibility gap between Nix
2.34.8's store/path-context handling and this test's old-style `import
"${pkgs.path}/..."` pattern -- unrelated to anything in this session's
diff, unrelated to the homelab host, and outside this plan's scope to fix
(would mean either patching `tests/zrepl-replication.nix` to source
`nixos/tests/ssh-keys.nix` a different way, or a Nix version change).
Recommend a separate `docs/plans/todo/` entry if this is worth fixing;
not blocking this plan's commit.

## Findings (F)
*(populated by security/docs-updater when invoked)*

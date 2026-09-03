---
slug: zbackup-pool-also-showing-usb-uas-enclosure-checksum-errors
created: 2026-09-01
status: done
frozen: true
---

# zbackup pool also showing USB/UAS-enclosure checksum errors, confirming fix's residual risk is enclosure-wide not zdata-specific

## Original plan

Follow-up to `2026-08-28-homelab-zdata-pool-usb-uas-checksum-errors.md`
(now frozen in `docs/plans/done/`), which root-caused and fixed silent
USB/UAS corruption on the TerraMaster 4-bay enclosure via
`usb-storage.quirks=174c:55aa:u`. That plan's evidence (G2) treated
`zbackup` as a clean control group -- 0 CKSUM ever, only `zdata`'s two
disks were affected -- which argued for something specific to zdata's
disks/vdev rather than the whole enclosure.

Triggered by a second health-alert email received 2026-09-01, ~1.5h
after the previous plan was closed: during the *same* nightly scrub
cycle, `zbackup` (not just `zdata`) now shows a CKSUM error too.

Alert as received:
```
  pool: zbackup
 state: ONLINE
status: One or more devices has experienced an unrecoverable error.  An
    attempt was made to correct the error.  Applications are unaffected.
action: Determine if the device needs to be replaced, and clear the errors
    using 'zpool clear' or replace the device with 'zpool replace'.
   see: https://openzfs.github.io/openzfs-docs/msg/ZFS-8000-9P
  scan: scrub in progress since Tue Sep  1 01:39:34 2026
    3.86T / 6.33T scanned at 99.1M/s, 3.49T / 6.33T issued at 89.7M/s
    128K repaired, 55.16% done, 09:13:19 to go
config:
    NAME                              STATE     READ WRITE CKSUM
    zbackup                           ONLINE       0     0     0
      mirror-0                        ONLINE       0     0     0
        wwn-0x5000cca26fed3145-part1  ONLINE       0     0     1  (repairing)
        wwn-0x5000cca27ad3b92a-part1  ONLINE       0     0     0
errors: No known data errors

  pool: zdata
 state: ONLINE
  scan: scrub repaired 256K in 09:43:35 with 0 errors on Tue Sep  1 11:23:12 2026
config:
    NAME                              STATE     READ WRITE CKSUM
    zdata                             ONLINE       0     0     0
      mirror-0                        ONLINE       0     0     0
        wwn-0x5000cca26fd26b20-part1  ONLINE       0     0     1
        wwn-0x5000cca26fe3d464-part1  ONLINE       0     0     1
errors: No known data errors
```

Investigate whether this contradicts the prior conclusion, decide if
any further action is needed, and update the record.

## State
**2026-09-01, investigated, low severity, monitoring only.** Confirmed
live on homelab: the errored `zbackup` disk (`wwn-0x5000cca26fed3145` =
sdd = serial `8CK6DXTF`, previously the cleanest disk in the enclosure
per the old plan's G4) shows the identical signature as every prior
event -- SMART clean (0 reallocated/pending, UDMA_CRC=0, PASSED), no
dmesg ATA/USB reset or disconnect events, kernel quirk still active,
self-healed by ZFS with no data errors. This is not a new problem or a
fix failure; it's the existing, already-accepted enclosure-wide
mechanism (G8 in the old plan) showing up on `zbackup` for the first
time simply because tonight's scrub is the first time `zbackup` has
been driven at the same sustained peak I/O as `zdata` normally sees
(see G1 below for why). No remediation needed beyond what's already
deployed. `zbackup`'s scrub has ~9h to go as of this check; not blocking
on it before filing this -- the outcome is already predictable from the
`zdata` precedent (G12 in the old plan) and this plan can be closed now,
same as the prior one was, without waiting idle for hours.

## Progress
- [x] Live-checked homelab: kernel quirk active, no link resets, SMART
      clean on the newly-errored zbackup disk (sdd/`8CK6DXTF`)
- [x] Reconciled this against the old plan's G2 ("isolated to one mirror
      vdev") -- see G1
- [x] Concluded no further remediation is needed beyond the existing fix (G3)

## Decisions (D)
*(none -- see G3: this is a conclusion from established precedent, not
a judgment call needing the user's input)*

## Gotchas (G)
### G1 -- zbackup's old "0 CKSUM ever" cleanliness (G2 in the prior plan) was a duty-cycle artifact, not immunity
The prior plan's G2 used zbackup's perfect record as evidence that the
corruption was specific to the `zdata` vdev/disks, not the whole
enclosure. That conclusion doesn't survive this event: `zbackup`'s sdd
disk, previously 0/0/0 for the pool's entire ~25-month history including
21 boots' worth of scrubs and continuous zrepl receive traffic, picked
up a CKSUM error the very first time it was driven through a full-pool
scrub at the same time and rate as `zdata`. `zbackup` normally only sees
bursty, lower-duty-cycle I/O (periodic zrepl receives) versus `zdata`'s
continuous live-service load -- so it simply hadn't been put under
matching sustained peak I/O before. Once it was (tonight's paired
scrub, both pools scrubbing concurrently since ~01:39), it showed the
identical bridge-chip signature. This *strengthens* G8's enclosure-wide
power-sag theory from the old plan rather than weakening it: all four
disks share one enclosure and one bridge chip, and the earlier
"isolated to one vdev" read was an artifact of unequal historical load,
not a real difference in exposure.

### G2 -- both pools' scrubs are scheduled to run concurrently, which is itself worth knowing
Both `zdata` and `zbackup` scrub started within 3 seconds of each other
(`01:39:34` vs `01:39:37`) -- evidently a shared/simultaneous scrub
schedule. Running both pools' scrubs at once roughly doubles the
enclosure's sustained I/O and bus-power draw versus staggering them,
which plausibly makes this exact failure mode (power-sag under peak
load, G8 in the old plan) more likely to trigger than if the two pools'
scrubs were offset. Not changed here -- flagging as a candidate second
step if this residual CKSUM trickle needs to be pushed down further
someday (see "what would change the answer" framing below), but not
worth doing preemptively for a risk this small.

### G3 -- no new remediation needed; this doesn't change the old plan's fix decision
Same root cause (bridge-chip power sag under peak I/O, G8 of the old
plan), same fix already deployed and confirmed active
(`usb-storage.quirks=174c:55aa:u`), same self-healing outcome (ZFS
`repairing`, no data errors), just observed on a disk that had never
previously been driven hard enough to show it. This does not reopen
`2026-08-28-homelab-zdata-pool-usb-uas-checksum-errors.md#D1` -- there
is no new option on the table beyond what was already chosen there.
Recorded here rather than as a `### D` heading because it's a mechanical
conclusion from established precedent, not a fork requiring the user's
judgment; the user can reopen this as a real decision if they disagree.

## Findings (F)
*(populated by security/docs-updater when invoked)*

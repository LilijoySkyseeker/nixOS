---
slug: homelab-zbackup-zdata-cksum-alert-recurrence-2026-09-02-matches-known
created: 2026-09-02
status: done
frozen: true
---

# homelab zbackup+zdata CKSUM alert recurrence 2026-09-02 -- matches known accepted risk, zbackup newly affected

## Original plan

Triggered by a health-alert email 2026-09-02 reporting CKSUM errors on
**both** `zbackup` and `zdata` on `homelab`:

```
  pool: zbackup
 state: ONLINE
status: One or more devices has experienced an unrecoverable error...
  scan: scrub repaired 256K in 19:25:22 with 0 errors on Tue Sep  1 21:04:56 2026
config:
    NAME                              STATE     READ WRITE CKSUM
    zbackup                           ONLINE       0     0     0
      mirror-0                        ONLINE       0     0     0
        wwn-0x5000cca26fed3145-part1  ONLINE       0     0     1
        wwn-0x5000cca27ad3b92a-part1  ONLINE       0     0     1
errors: No known data errors

  pool: zdata
 state: ONLINE
status: One or more devices has experienced an unrecoverable error...
  scan: scrub repaired 256K in 09:43:35 with 0 errors on Tue Sep  1 11:23:12 2026
config:
    NAME                              STATE     READ WRITE CKSUM
    zdata                             ONLINE       0     0     0
      mirror-0                        ONLINE       0     0     0
        wwn-0x5000cca26fd26b20-part1  ONLINE       0     0     1
        wwn-0x5000cca26fe3d464-part1  ONLINE       0     0     1
errors: No known data errors
```

Check whether this is a recurrence of the already-diagnosed/fixed USB-UAS
issue (see `docs/plans/done/2026-08-28-homelab-zdata-pool-usb-uas-checksum-errors.md`)
or something new, and decide whether action is needed.

## State
**2026-09-02, confirmed known accepted residual risk, no action taken.**
The `zdata` half of this alert is *literally the same scrub* already
analyzed and closed out in G12/addendum of the prior plan (identical
scan line: `scrub repaired 256K in 09:43:35 ... Tue Sep 1 11:23:12 2026`,
identical per-disk CKSUM=1/1) -- this alert email was just a second
delivery/delayed trigger for that same event, not a new one. The
`zbackup` half is new: that pool's disks were clean throughout the
entire prior investigation (G2), and now show the same 1/1 CKSUM
pattern from a separate scrub that ran later the same day (21:04:56).
Live-checked homelab: system has been up continuously since the
2026-08-28 11:49 fix-deploy boot (`who -b` confirms, no reboot since),
`usb-storage.quirks=174c:55aa:u` still active on all four enclosure
ports (dmesg), SMART clean on all four disks (Reallocated/Pending/
Offline_Uncorrectable/UDMA_CRC all 0, PASSED), both pools' scrub
summaries report 0 permanent/uncorrectable errors. No data loss, no
new remediation needed -- this is the same accepted-risk mitigation
(G8 of the prior plan) now observed extending to the previously-clean
`zbackup` mirror, consistent with the shared-enclosure/shared-bridge-
power theory since all four disks share one TerraMaster USB enclosure.
Closing this out as confirmed-no-new-issue.

## Progress
- [x] Compared alert against prior closed investigation
      (`docs/plans/done/2026-08-28-homelab-zdata-pool-usb-uas-checksum-errors.md`)
- [x] Confirmed live `zpool status -v` on homelab matches alert email
      exactly for both pools
- [x] Confirmed `usb-storage.quirks` kernel param still active, no
      reboot since the 2026-08-28 fix deploy
- [x] Confirmed SMART clean on all four zdata/zbackup disks
- [x] Confirmed zero permanent/uncorrectable errors in both scrub
      summaries -- no data loss
- [x] Decided no `zpool clear` / no new remediation needed (D1)

## Decisions (D)
### D1 -- take any new remediation action, or treat as continuation of accepted risk?
**ANSWERED (no user input needed, matches prior explicit decision):**
prior plan's D1 already chose the `usb-storage.quirks` mitigation over
disk replacement or a powered-hub/different-enclosure escalation, and
G12 of that plan explicitly accepted a low-rate residual CKSUM trickle
as normal for this mitigation, self-healing via ZFS's own repair with
no `zpool clear` required (counters reset on next reboot on their
own). This alert doesn't exceed that accepted envelope -- 1 error per
disk per pool, both pools' scrub summaries show 0 permanent errors --
so no new action taken. Escalation trigger (per the prior plan)
remains: this recurring *more than rarely* or a scrub summary ever
showing >0 permanent errors.

## Gotchas (G)
### G1 -- `zbackup` (previously clean, see prior plan's G2) is now also showing the residual CKSUM pattern
All four disks in the TerraMaster enclosure share the same USB hub and
bridge-chip power path (prior plan's G1/G8: bridge chip is bus-powered
off the USB port even though the drives get enclosure power, so
bus-power sag under sustained I/O can glitch the bridge without a
link-layer disconnect). Previously only `zdata`'s mirror had ever shown
CKSUM errors, `zbackup` was clean across the pool's entire history. This
alert is the first time `zbackup` shows the same 1-per-disk pattern,
from a scrub that ran later the same day as `zdata`'s. This is
consistent with (not contradicting) the power-sag theory -- it's a
matter of which pool's scrub happened to be running during a sag event,
not evidence the fix stopped working for `zdata` specifically. Worth
tracking if `zbackup` starts accumulating errors faster than `zdata`
did pre-fix, but a single event doesn't establish a trend.

## Findings (F)
*(populated by security/docs-updater when invoked)*

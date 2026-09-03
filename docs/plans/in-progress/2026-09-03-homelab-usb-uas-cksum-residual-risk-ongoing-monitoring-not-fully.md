---
slug: homelab-usb-uas-cksum-residual-risk-ongoing-monitoring-not-fully
created: 2026-09-03
status: in-progress
frozen: false
---

# homelab USB-UAS CKSUM residual risk -- ongoing monitoring, not fully resolved

## Original plan

Continuation of two frozen plans:
`docs/plans/done/2026-08-28-homelab-zdata-pool-usb-uas-checksum-errors.md`
(original diagnosis + `usb-storage.quirks` mitigation) and
`docs/plans/done/2026-09-02-homelab-zbackup-zdata-cksum-alert-recurrence-2026-09-02-matches-known.md`
(confirmed the 2026-09-02 alert was the same accepted residual risk,
now also hitting `zbackup`). Both are frozen (`done/` plans get zero
further edits by design -- `plan_require_not_frozen` in
`docs/skills/plan/scripts/lib.sh`), so new information goes here
instead. Purpose of *this* plan: track the residual USB-UAS CKSUM
trickle as an open, ongoing condition rather than a closed
investigation -- the underlying enclosure/bridge-chip vulnerability is
mitigated, not eliminated, and will keep producing occasional alerts.
Left in `in-progress/` deliberately (not moved to `done/`) since the
issue itself isn't resolved, only managed.

## State
**2026-09-03.** Quantified the mitigation's actual effect and cleared
the counters that were driving repeat alerts. `zpool clear` run on
both `zbackup` and `zdata` on homelab; both now show clean `0 0 0`
READ/WRITE/CKSUM on every device (`errors: No known data errors`); the
only remaining `zpool status` message is an unrelated pre-existing
"zpool upgrade available" feature notice, not an error. This is
expected to recur (the underlying bridge-chip power-sag vulnerability
under sustained I/O, per the frozen plan's G1/G8, is reduced but not
eliminated by the kernel quirk) -- next scrub or heavy-I/O event will
likely tick CKSUM back up by roughly 1 per affected disk, which is
normal and does not by itself indicate data loss. Also ran a general
homelab health check-in same session: no failed systemd units, disk
space healthy on both pools, zrepl's `local-pull`/`torrent` jobs
completing normally; `thinkpad`'s zrepl pull job is failing on
connection timeouts because the laptop itself is offline (tailscale:
"offline, last seen 2d ago") -- expected laptop-off behavior, not a
homelab fault, noted here only as context, not a health problem for
this plan to track.

## Progress
- [x] Quantified pre-fix vs. post-fix CKSUM error rate with hard
      numbers (G1)
- [x] Ran `zpool clear` on `zbackup` and `zdata` on homelab, verified
      both show clean 0/0/0 across all devices
- [x] Ran a general homelab health check-in (failed units, disk space,
      memory/swap, zrepl job status) -- nothing else actionable found
- [ ] Watch for the next scrub/alert cycle and confirm the recurrence
      rate stays in the same low steady-state band (not growing)
- [ ] Revisit escalation (powered USB hub / different enclosure /
      direct SATA) only if the rate measurably increases from here, per
      the frozen plan's original escalation criteria

## Decisions (D)
### D1 -- should `zpool clear` be run routinely to suppress repeat alerts on the known residual trickle?
**ANSWERED 2026-09-03:** yes, user explicitly requested it ("clear the
errors for zfs, so it stops alerting me"). `zpool clear` only resets
the READ/WRITE/CKSUM counters and pool error state; it does not affect
data, and the durable record of actual repair activity/data-loss is
each scrub's own summary line (`scrub repaired ... with 0 errors`),
which `zpool clear` does not touch. Safe to run again whenever a future
alert fires on this same known residual issue.

## Gotchas (G)
### G1 -- quantified the mitigation's effect: ~65-80x reduction in CKSUM rate for `zdata`, not just "looks better"
Pre-fix (frozen plan's G6 correction): `zdata`'s two disks accumulated
22 and 27 CKSUM errors in ~2 days of normal light I/O -- roughly 11-13
errors/disk/day. Post-fix: system stayed on one boot from 2026-08-28
11:49 through at least 2026-09-03 (~5.9 days), including the two
heaviest I/O events this pool sees (a 9h43m `zdata` scrub and a 19h25m
`zbackup` scrub, each reading multiple TB) -- total damage over that
whole window was 1 error per disk on each pool (~0.17 errors/disk/day),
and the count did not move at all in the ~2 days between the Sep 1
scrubs finishing and this check. Conclusion: the fix is a real, large
effect (roughly two orders of magnitude), not a placebo -- it just
doesn't fully eliminate the underlying bridge-chip vulnerability, and
what's left is specifically tied to peak sustained I/O (scrubs), not
steady-state day-to-day traffic which now produces ~zero errors.

## Findings (F)
*(populated by security/docs-updater when invoked)*

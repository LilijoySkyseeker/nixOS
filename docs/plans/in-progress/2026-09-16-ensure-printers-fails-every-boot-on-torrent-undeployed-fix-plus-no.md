---
slug: ensure-printers-fails-every-boot-on-torrent-undeployed-fix-plus-no
created: 2026-09-16
status: in-progress
frozen: false
kind: task
priority: normal
blocked_by:
---

# ensure-printers fails every boot on torrent -- undeployed fix plus no retry

## State

Verified to rung 3 (ran it locally, output inspected): `verify-ladder`
passes, the built unit carries `After=/Wants=network-online.target` plus
`Restart=on-failure` / `RestartSec=30` / `StartLimitBurst=5`, and
`systemd-analyze verify` on that exact generated unit is clean.

Stays in `in-progress/`. The thing that actually broke here was a fix
that was correct in git and never switched in (G1), so closing this on a
local build would repeat that mistake exactly. It closes after a real
`nixos-rebuild switch` on torrent and a reboot that leaves the unit
active -- rung 5, which needs the user.

## Original plan

`ensure-printers.service` on `torrent` is `loaded failed failed`. Find
out why and fix it.

The unit has failed on **every boot** since 2026-09-02 and succeeded on
every activation-time run in between -- see G1 for the timeline that
splits those two populations. Same `lpadmin: Unable to connect to
192.168.1.166:631: Host is down` each time.

Work:

- Redeploy so the existing `network-online.target` ordering actually
  takes effect (G1).
- Give the unit a bounded retry so a printer that is merely asleep or
  powered off at boot no longer leaves a permanently-failed unit and an
  unset default printer (G2, D1).

## Progress

- [x] Reproduce and read the failure live on torrent
- [x] Confirm the printer is reachable now (ping + TCP 631 open)
- [x] Establish that the committed ordering fix was never switched in (G1)
- [x] Confirm `Restart=on-failure` is legal for `Type=oneshot` (G3)
- [x] Add bounded retry to the unit
- [x] `verify-ladder`
- [ ] Deploy: `nixos-rebuild switch --flake .#torrent` (needs the user)
- [ ] Confirm across a real reboot

## Decisions (D)

### D1 -- bounded retry rather than "wait until the printer answers"

Ordering after `network-online.target` only fixes the case where
*torrent* has no network yet. It does nothing for the case where the
printer itself is off or in deep sleep at boot, which for a home laser
printer is the common one. Options considered:

- An `ExecStartPre` that polls TCP 631 until the printer answers --
  blocks `multi-user.target` behind a device that may never come up.
- `Restart=on-failure` with a bounded burst -- the unit retries quietly
  in the background and self-heals once the printer wakes, then gives up
  instead of retrying forever.

Took the second. `StartLimitBurst` counts the initial start too, so
`startLimitBurst = 5` with `RestartSec = 30` is one attempt plus four
retries -- about a two-minute window. Enough to cover a printer waking
from sleep, short of spinning all day against one that is unplugged.
`startLimitIntervalSec = 600` is deliberately longer than that window, so
the burst is actually spent rather than silently reset mid-sequence.

Open for the user: whether giving up after ~2 minutes is the right
tradeoff, or whether the unit should keep trying for longer.

## Gotchas (G)

### G1 -- the 2026-09-03 fix was committed but never deployed

`54f1e0a` ("fix(printer): order ensure-printers.service after
network-online.target", 2026-09-03 13:02) added
`after`/`wants = [ "network-online.target" ]`. `torrent` has been running
generation **130**, built 2026-09-02 18:32 -- *before* that commit. The
live `/etc/systemd/system/ensure-printers.service` still reads only
`After=cups.service`, while a fresh `nixos-rebuild build --flake .#torrent`
emits `After=cups.service network-online.target`. So the fix was real and
correct, it just was not running.

The journal splits cleanly along that line. Every failure is at a boot
(`-- Boot <id> --` immediately above it): 09-02 18:37, 09-04 18:34, 09-05
15:43, 09-05 15:49, 09-05 15:55, 09-12 07:29, 09-13 12:57. Every success
is an activation-time or manual run mid-session: 09-02 18:04, 09-03
12:59, 09-05 15:34. The closing 09-03 12:59 success in the previous plan
was the *manual* `systemctl restart`, not evidence the ordering had taken
effect.

Timing from the last boot makes the race explicit:

```
12:57:35.813814  Starting Network Manager Wait Online...
12:57:35.844327  Starting Ensure NixOS-configured CUPS printers...
12:57:35.860931  lpadmin: Unable to connect to 192.168.1.166:631: Host is down
12:57:41.737760  Reached target Network is Online.
```

`lpadmin` ran 30 ms after NetworkManager started and 5.9 s before the
network was actually up.

Lesson worth carrying: a plan closed on "restarted the unit and it
worked" proves the *command* works, not that the *config* that was
supposed to make it work on the next boot is live. The evidence ladder's
top rung is an observed switch, and this never got one.
Cross-ref: `2026-09-03-ensure-printers-service-boot-race-on-torrent-order-after-network.md#G1`.

### G2 -- a failure leaves the queue half-configured, not just unset

The generated `ensure-printers-start` script is `set -e`, and the
`lpadmin -p ... -v ...` that fails is the *first* of three commands. So on
failure the queue's `device-uri` and `printer-is-accepting-jobs` have
already been written (visible in `cupsd`'s own log for the failed boot),
but the following `lpadmin -d Brother_MFC_L2740DW` never runs -- the
default printer is silently not set -- and neither does the trailing
`systemctl stop cups.service`. That is why the symptom reads as "the
printer is broken" rather than "one oneshot is red".

### G3 -- `Restart=` is legal on `Type=oneshot`, just not `always`

Verified empirically against the systemd actually running on torrent
(261.1) rather than from memory, since the constraint is easy to
misremember as a blanket ban:

```
$ systemd-analyze verify t-oneshot-restart.service   # Restart=on-failure
(no complaint about Restart=)

$ systemd-analyze verify t-oneshot-restart.service   # Restart=always
Service has Restart= set to either always or on-success,
which isn't allowed for Type=oneshot services. Refusing.
```

`on-failure` is fine. Pair it with `StartLimitIntervalSec`/
`StartLimitBurst` in `[Unit]`, not `[Service]`.


## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 -- reviewed by hand, not by the review subagents

This session was started with a standing constraint against spawning
subagents, so `security` / `docs-updater` / `spec-check` / `/simplify`
were not run. Reviewed the diff directly instead; re-run them if this
needs a real gate before merge.

Surface check, for what it is worth: the diff adds only `Restart`,
`RestartSec`, `StartLimitIntervalSec` and `StartLimitBurst` to an
existing unit. No new listener, no firewall change, no secret, no
sandboxing option relaxed, no change to who the unit runs as. The retried
command is the same root `lpadmin` against the local
`/run/cups/cups.sock` it already ran.

One thing worth naming rather than leaving implicit: the generated script
ends with `systemctl stop cups.service`, which `set -e` skips on failure,
so a run that fails leaves `cups.service` up. Retrying does not introduce
that -- it is the behaviour today, at every failed boot since 09-02 -- and
CUPS binds loopback only here (`Remote access is disabled.` in the boot
log, `listenAddresses` untouched at its `localhost:631` default), so it is
not an exposure. Retrying does make it happen up to five times instead of
once. Net effect is unchanged or better: on the runs where the printer
does wake, cups now gets stopped where previously it stayed up.

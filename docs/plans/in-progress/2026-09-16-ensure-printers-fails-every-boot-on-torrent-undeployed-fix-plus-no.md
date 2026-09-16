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
- [x] `security` review run (F2-F8); `TimeoutStartSec` gap it found now fixed (F3)
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

**SUPERSEDED IN PART 2026-09-16** -- left standing above as the record of
what the hand review actually claimed, now that `security` has checked it.
Read F2 and F4 before relying on any of it:

- F2 **qualifies** the "no new exposure" claim. `-m everywhere` is not a
  local-socket-only operation; it makes cupsd connect *outbound* to the
  bare LAN IP and build the queue and PPD from whatever answers, as root.
  Retries fire precisely on the runs where the real printer did not
  answer, which is exactly when an impostor at `.166` is uncontested. The
  loopback half of the claim was verified correct; "no new exposure" was
  too strong.
- F4 **agrees with the conclusion but not the reasoning** on cups being
  left up. It is harmless because `cups.socket` binds `127.0.0.1:631` from
  boot regardless, so stopping the service evicts a process and never a
  listener -- not, as written above, merely because cupsd is loopback-only.

Worth keeping as a datapoint on hand review: it reached the right verdict
on the merge (nothing above LOW) while getting the mechanism wrong twice.

### F2 -- the retry fires *only* while the real printer is absent, which widens the impostor window rather than leaving it unchanged (qualifies F1)

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:59-67` (new `Restart`/`RestartSec`/`startLimit*`), `modules/nixos/brother-mfc-l2740dw.nix:23-24` (`deviceUri`, `model = "everywhere"`)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** any device with L2 access to `192.168.1.0/24` (a compromised IoT device, a guest on Wi-Fi bridged to the LAN, or anything that can take/ARP-spoof `.166` while the real printer is off) -- it answers the root `lpadmin` IPP query and supplies the attributes CUPS turns into a root-written PPD plus the queue's `device-uri`, and thereafter receives every document printed to `Brother_MFC_L2740DW`.
- **Rule:** n/a (the module's own D9 rationale, `modules/nixos/brother-mfc-l2740dw.nix:5-17`)
- **Finding:** F1 says the retried command is "the same root `lpadmin` against the local `/run/cups/cups.sock` it already ran". That is only half of what the command does, and the missing half is the part D9 cares about. `lpadmin(8)` in the pinned cups (`/nix/store/2wvg1npjz93sqr9lx2602bpvn9mqr7vr-cups-2.4.19-man`, under `-m model`) states: the model "everywhere" queries the printer referred to by the specified IPP device-uri. The failure text this whole plan is about -- `lpadmin: Unable to connect to 192.168.1.166:631` -- carries `lpadmin`'s own prefix, so the outbound TCP connection to the LAN IP is made by the root process in this unit, not by an already-trusted local daemon. The queue and its PPD are built from whatever answers at `192.168.1.166:631`: network-supplied identity, resolved by bare IP, no TLS, no device authentication.
- **Finding (cont.):** The delta the retry introduces is not "5 attempts instead of 1" in the abstract. `Restart=on-failure` fires *only* on the runs where the legitimate printer did **not** answer -- precisely the window in which an impostor at `.166` is uncontested and cannot lose the race. Before this commit the system failed closed after one probe into that window; after it, the system keeps probing that address every 30 s for as long as the real device stays silent, and binds to the first thing that replies. That is a real widening of the exact exposure the module header says torrent-only scoping was meant to contain, not the "unchanged or better" F1 concludes. F1 is right about `cups.service` residency (see F4) and right about the loopback binding -- verified: `cups.socket` is `ListenStream=/run/cups/cups.sock` plus `ListenStream=127.0.0.1:631` (`/nix/store/qbfz1dpdxr4ns1sgn8gaz9hhxlvjmq8v-unit-cups.socket`), and `cupsd.conf` is `Listen localhost:631` plus the socket with `Allow localhost` only. It is not right that the change adds no exposure at all.
- **Finding (cont.):** Rated LOW rather than MEDIUM because this widens an already-taken, already-documented decision (D9 and the 2026-08-27 plan's F1/F2) rather than opening a new class, and because the pinned cups is 2.4.19 -- past the 2024 IPP-attributes-into-PPD sanitization work (the CVE-2024-4717x cluster) -- so the worst realistic outcome is a hijacked print destination plus attacker-chosen strings in a root-written PPD, not a known RCE. That "past the fixes" part is the one piece not verified against source (the cups tarball is not unpacked in the store and this environment has no network); treat it as the reason the rating is not higher, not as an independent claim.
- **Fix risk:** Narrowing means either not retrying on the specific device-unreachable failure (which is the whole feature), or gating the retry on something that authenticates the device -- checking the printer's MAC against the router reservation before running `lpadmin`, or pinning `printer-uuid`/`printer-device-id` from the known-good queue and refusing to re-create it if the reply differs. Any such gate must be tested against the real wake-from-sleep case, since one that is too strict reproduces exactly the permanently-failed unit this plan set out to remove. Accepting the risk is also defensible; the point is that the tradeoff belongs next to D1 rather than being described as no-cost.

### F3 -- "about a two-minute window" holds only for fast failures; a slow-failing probe can make the burst self-resetting and the retry unbounded

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:59-66`
- **Severity:** LOW
- **Confidence:** PLAUSIBLE
- **Axis:** needed-used
- **Reachability:** no adversary needed for the availability half. For the security half, the same on-LAN adversary as F2: anything that blackholes traffic to `.166` (silent DROP rather than an ICMP unreachable) converts a bounded 5-probe burst into an indefinite loop of root IPP probes at that address, extending F2's impostor window from ~2 minutes to the entire uptime of the host.
- **Rule:** new-rule candidate -- a start-limit window should be set with headroom over the *worst-case* burst duration, not the observed fast-fail one.
- **Finding:** D1 computes the burst as "one attempt plus four retries -- about a two-minute window" and concludes `startLimitIntervalSec = 600` is "deliberately longer than that window". Both halves assume each attempt fails near-instantly, which is true only for the observed `EHOSTUNREACH` fast-fail (ARP fails, `connect()` returns immediately). It is not true in general.
- **Finding (cont.):** Verified: this unit sets no `TimeoutStartSec`, and torrent's `/etc/systemd/system.conf` sets no `DefaultTimeoutStartSec` and no `DefaultStartLimit*` -- the built `etc` (`/nix/store/2z6dim5xwsfy2w7zalk97n6v2iirsjsf-etc`) contains only `DefaultIOAccounting`, `DefaultIPAccounting` and `ManagerEnvironment` under `[Manager]`. So systemd's built-in 90 s start timeout applies. A probe that hangs rather than fast-failing therefore costs up to 90 s, and the gap between consecutive start attempts becomes up to 90 + `RestartSec` 30 = 120 s. Five starts then span up to 480 s, and the sixth -- the one that is supposed to be refused -- lands at t ~= 600 s.
- **Finding (cont.):** `systemd.unit(5)` in the pinned systemd (`/nix/store/fymqir88fw6va1zvqy8r3s7ik2fxiac2-systemd-261.2-man`) defines the limit as units "started more than *burst* times within an *interval* time span", and systemd implements it as a window that **resets** the counter when a start arrives later than `interval` after the window opened. So in the slow-failure case the margin between "burst is spent" and "window rolls over and the counter resets" is approximately zero, and accumulated dispatch latency across five cycles pushes it to the wrong side. At that point the unit retries forever at ~2-minute intervals, `cups.service` is never stopped (F4), and -- because a unit in auto-restart never enters `failed` -- `health-alerts`' `systemctl --failed` check (`modules/nixos/health-alerts.nix:262-267`) never reports it. That is the shape `docs/hardening.md` rule 11 warns about: a permanently-retrying unit looks identical to a succeeding one from a check that only watches unit state.
- **Finding (cont.):** Marked PLAUSIBLE, not CONFIRMED, because whether `lpadmin -m everywhere` actually takes ~90 s against a blackholed IP depends on the connect timeout inside cups's own `get_printer_ppd()`, which could not be read here (source tarball not unpacked in the store, no network). If that timeout is 30 s, the margin is comfortable and this is a non-issue. The arithmetic and the systemd semantics above are confirmed; only the trigger condition is not.
- **Fix risk:** Setting an explicit `TimeoutStartSec` comfortably below `startLimitIntervalSec / startLimitBurst` (e.g. 45 s) closes the gap and costs nothing structurally, but a value too low would kill a slow-but-succeeding probe against a printer that is awake and merely slow to answer `Get-Printer-Attributes`, turning a working boot into a failed one. Test with the printer awake both before and after.

**FIXED 2026-09-16:** Added `TimeoutStartSec = 45` to `serviceConfig`.
Took the reviewer's suggested value rather than the 30 s first written,
since the fix-risk note above is the binding constraint. Worst case is now
`5x45 + 4x30 = 345 s`, comfortably inside `startLimitIntervalSec = 600`,
so the burst is spent and the unit reaches `failed` where
`health-alerts` can see it.

The fix-risk half was then measured rather than assumed, with the printer
awake, using the same `Get-Printer-Attributes` operation `-m everywhere`
issues:

```
$ ipptool -t ipp://192.168.1.166/ipp/print attrs.test
    attrs                        [PASS]
real    0m0.204s
```

204 ms against roughly 220x that in budget. A 45 s timeout cannot
plausibly kill a succeeding probe on this device, so the "turns a working
boot into a failed one" risk does not materialise. The PLAUSIBLE half of
the finding -- cups's internal connect timeout in `get_printer_ppd()`,
which the reviewer could not read -- is now moot either way: whatever that
timeout is, `TimeoutStartSec` caps the cycle below it.

### F4 -- leaving `cups.service` up is confirmed harmless for listening surface, but for a different reason than F1 gives

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:46-68`; upstream `nixos/modules/hardware/printers.nix:120,418-440` and `nixos/modules/services/printing/cupsd.nix:409-418` (pinned unstable, `/nix/store/sr2lpwrcdjfpkk8gpvr98gp4nrgsijns-source`)
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** local unprivileged users on torrent reach `127.0.0.1:631` either way -- `cups.socket` is `WantedBy=sockets.target` and binds `127.0.0.1:631` from boot regardless of whether `cups.service` is running. "cups left up" grants no principal anything it did not already have.
- **Rule:** n/a
- **Finding:** Checked the socket-activation question specifically. F1's conclusion survives, with a correction to its reasoning. `ultimatelyStopCups = startWhenNeeded && !stateless` (upstream `printers.nix:120`) is true here, which is why the generated `ensure-printers-start` ends in `systemctl stop cups.service`; `set -e` with the probing `lpadmin` first does skip it on failure, as G2 says. But the reason that is not an exposure is not merely that cupsd binds loopback -- it is that the *listener* is `cups.socket`, which is up from boot either way. Stopping `cups.service` only evicts the process, never the socket. So repeatedly failing and leaving cupsd resident costs a resident daemon and nothing else, and once the burst is spent the end state is identical to the pre-commit end state. No consequence found beyond that; the specific worry about socket activation does not materialise.
- **Finding (cont.):** Worth recording anyway: the `startWhenNeeded` design intends cupsd to be transient, and on every boot where the printer does not wake within the burst it is not -- a root daemon that parses IPP stays resident for the rest of the uptime. Pre-existing and unchanged by this commit; it only becomes permanent-by-design under F3's slow-failure case.
- **Fix risk:** Nothing to fix in this commit. If someone later adds an `ExecStopPost` or a shell trap to stop cups on the failure path, note that `ensure-printers` is `After=cups.service` and a synchronous `systemctl stop` from inside the unit is safe only because `Wants=` does not propagate stop; promoting that to `Requires=`/`BindsTo=` would deadlock the job.

### F5 -- the start limit applies to manual starts too, so after the burst the unit refuses `systemctl start` for the rest of the 600 s window

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:59-60`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** the operator, not an adversary -- a human debugging the printer after a failed boot, who wakes the printer and then cannot start the unit.
- **Rule:** n/a
- **Finding:** Answering what hitting the start limit leaves behind. Three checks against the pinned versions, all clean:
- **Finding (cont.):** (1) `multi-user.target` is not affected. Confirmed from the built unit (`/nix/store/31nvn5mjazh63wny6j7qys7lywhgrkyd-unit-ensure-printers.service`): `[Install] WantedBy=multi-user.target` only, with no `Before=`. `WantedBy=` creates a `Wants` dependency and no ordering, and an auto-restart is a fresh job rather than one pending from the boot transaction, so neither the retries nor the start-limit-hit hold up the target. (2) `StartLimitAction=` is unset and defaults to `none` (`systemd.unit(5)`, pinned systemd 261.2 man pages), so hitting the limit triggers no reboot/poweroff/`FailureAction` -- the only effect is that the start is refused. This is the failure mode most worth having checked, and it is clean. (3) `nixos-rebuild switch` is not blocked by the rate-limited state: `switch-to-configuration-ng` calls `systemd.reset_failed()` before starting units (`pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs:2354`, and again at `:1543` for the user manager), and `systemd.unit(5)` states that `systemctl reset-failed` flushes the restart rate counter. A torrent sitting in `start-limit-hit` still takes a switch cleanly.
- **Finding (cont.):** What does bite: the same man page says the limits "apply to all kinds of starts (including manual), not just those triggered by the `Restart=` logic". With `startLimitBurst = 5` spent inside the first ~2 minutes of boot and `startLimitIntervalSec = 600`, there is a roughly eight-minute stretch in which `systemctl start ensure-printers` -- the obvious thing to type after walking over and waking the printer -- is answered with "Start request repeated too quickly" until the operator knows to run `systemctl reset-failed ensure-printers` first. The pre-commit unit inherited `DefaultStartLimitIntervalSec` of 10 s, so this lockout window is new, and it is a side effect of raising the *interval*, not of adding `Restart=`. Worth one line in the module comment or `hosts/torrent/README.md` so the next person does not read it as a second bug.
- **Fix risk:** Lowering `startLimitIntervalSec` toward the actual burst length shrinks the lockout but eats the headroom F3 is already worried about. The two pull in opposite directions and should be chosen together, not separately.

### F6 -- the queue and the default printer persist across reboots on torrent, so what is being retried around may be a red unit rather than a broken printer

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:50-67`; `hosts/torrent/disko.nix:36-42`
- **Severity:** INFO
- **Confidence:** PLAUSIBLE
- **Axis:** needed-used
- **Reachability:** n/a -- no adversary. This is a justification question, but it bears directly on F2: if the retry buys little, the widened impostor window buys even less.
- **Rule:** n/a
- **Finding:** D1 and G2 justify the retry partly on user-visible breakage -- "the default printer is silently not set", the symptom "reads as *the printer is broken*". That framing assumes queue state is rebuilt from scratch each boot. On torrent it is not. `hosts/torrent/disko.nix` puts `/` on the persistent `zroot/local/root` dataset with no boot-time rollback, and torrent carries no `environment.persistence` at all (`grep -rl environment.persistence hosts modules` returns homelab and vps, not torrent). `lpadmin(8)` in the pinned cups states the configuration "is stored in several files including `printers.conf`", which lives under `/var/lib/cups` and therefore survives the reboot. So on a boot where `ensure-printers` fails, the queue and the server default set by the *previous* successful run are still present; what is lost is the idempotent re-assertion, not the configuration.
- **Finding (cont.):** This does not make the commit wrong. A permanently-red unit is a real problem on its own terms -- it holds `health-alerts`' failed-units alert on (`modules/nixos/health-alerts.nix:262-267`), which trains the operator to ignore that alert -- and G1's deployment fix is plainly correct. It does mean D1's cost/benefit is stated one notch too favourably, and the plan should say so before it closes: the retry buys a green unit and a re-asserted config, not a working printer that would otherwise be broken.
- **Finding (cont.):** PLAUSIBLE, not CONFIRMED: `/var/lib/cups/printers.conf` was not inspected on the live host (this review is read-only and off-host), and the interaction between a *partially applied* failed run (G2's "device-uri and printer-is-accepting-jobs have already been written") and the persisted file was not verified. If a partial run can leave `printers.conf` naming a queue with no PPD, the user-visible impact is larger than described here. One `lpstat -t` / `lpstat -d` on torrent at the next failed boot settles it, and is worth doing before rung 5 closes.
- **Fix risk:** n/a -- this is justification/documentation, not config.

### F7 -- the diff opens `serviceConfig` on a root unit that parses network-supplied input and declines to bring the repo's own sandboxing baseline with it

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:61-67`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** the F2 adversary -- a device on `192.168.1.0/24` answering at `.166` feeds a crafted IPP response to `lpadmin` running as uid 0 with full ambient privilege: no `NoNewPrivileges`, no `ProtectHome`, no `PrivateTmp`, no `RestrictNamespaces`, no `ProtectKernel*`. A memory-safety or injection bug in cups's IPP-to-PPD path executes with the whole machine available rather than inside a namespace.
- **Rule:** `docs/hardening.md` "Custom `systemd.services` sandboxing" -- arguably out of scope, since this is an upstream unit rather than one this repo authored, which is why this is LOW and not MEDIUM.
- **Finding:** Confirmed from the built unit that the merged `[Service]` block is exactly `Environment=` x3, `ExecStart`, `RemainAfterExit`, `Restart`, `RestartSec`, `Type` -- nothing from the repo's sandboxing baseline, and no `User=`. This commit is the first time this repo sets `serviceConfig` on `ensure-printers` at all, so it was the natural moment to bring the cheap half of the baseline, and it did not. The unit cannot drop root (`lpadmin` writes under `/var/lib/cups`, and the script calls `systemctl stop cups.service`), and `ProtectSystem = "strict"` would need explicit `ReadWritePaths` for `/var/lib/cups` and `/run/cups`, so the full stack is not free -- but `NoNewPrivileges`, `ProtectHome`, `PrivateTmp`, `ProtectKernelModules`, `ProtectKernelTunables`, `ProtectKernelLogs` and `RestrictNamespaces` all are, on a unit whose entire job is one `lpadmin` invocation. The commit makes that root parse of untrusted input happen up to five times per boot instead of once (F2) without touching the privilege it happens under.
- **Finding (cont.):** The honest counter-argument, since this is a judgement call: the pre-commit unit was equally unsandboxed, this commit relaxes nothing, and NixOS ships `ensure-printers` this way for every user. Nothing here is a regression. It is a missed opportunity that the repo's own standing rule points straight at.
- **Fix risk:** `ProtectSystem`/`ProtectHome` interact with cupsd's `/etc/cups -> /var/lib/cups` symlink handling (upstream `cupsd.nix:442-446`) and with the `systemctl stop` call needing the system D-Bus socket; `PrivateTmp` is likely safe, `ProtectSystem = "strict"` is not without explicit `ReadWritePaths`. Any addition needs a real boot on torrent with the printer awake, since a sandbox that breaks the success path turns a cosmetic failure into a permanent one.

### F8 -- the sane-airscan WSD firewall rule (unchanged by this commit) is live rather than dead, and already narrowed; two residual notes

- **File:** `modules/nixos/brother-mfc-l2740dw.nix:78-80`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** any device on `192.168.1.0/24` able to spoof a source address of `192.168.1.166` -- trivial on a LAN, since `checkReversePath` validates routability, not L2 identity, and `.166` is routable via `enp8s0`. Such a device can send UDP into the host's entire ephemeral port range on that interface, unconditioned by conntrack state.
- **Rule:** `docs/hardening.md` rule 5 ("scope every firewall rule to an interface") -- satisfied.
- **Finding:** Checked for deadness first, since the classic failure for a hand-written `nixos-fw` rule is being appended after the chain's terminal refuse. It is not dead: the pinned `nixos/modules/services/networking/firewall-iptables.nix` emits `${cfg.extraCommands}` at line 235 and `ip46tables -A nixos-fw -j nixos-fw-log-refuse` at line 238, so the accept lands ahead of the refuse and is reachable. `networking.nftables` is not enabled anywhere in this repo, so the iptables backend is the live one and this is not the "renders but does nothing" case hardening rule 9 describes. The earlier plan already narrowed the rule from all-UDP to `32768:60999` (`2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#F3` plus its 2026-09-02 FIXED note), so the obvious over-breadth is gone.
- **Finding (cont.):** Two residual notes, neither new and neither caused by this commit. (1) The hole is permanently open for a transient, user-initiated operation: WSD discovery only runs when a scanning application enumerates devices, but the rule is in force for 100% of uptime. Nothing in the NixOS firewall makes an on-demand hole convenient, so this is a note rather than a demand. (2) Its only authentication is source IP, which is spoofable on-link, and it carries no `--sport` restriction and no state match. Real exposure is bounded by what is actually bound to ephemeral UDP on torrent (resolver and NTP client sockets, browser QUIC), so injection into an in-flight DNS or QUIC exchange is the shape of it, and an on-link spoofer generally has better options. Separately, `--dport 32768:60999` is a hardcoded copy of the kernel's `ip_local_port_range`; nothing in this repo sets that sysctl, so the literal is currently correct -- but the coupling is silent, and it fails open if the range is ever moved upward. A comment naming that coupling would be cheap.
- **Fix risk:** Any tightening (a `--sport` restriction, a state match, gating the rule on a running scan) risks silently reintroducing the original dropped-reply symptom, which is only detectable by running `scanimage -L` with the scanner awake. Do not change it without that test.

## Checked and clean -- security review, 2026-09-16

Reviewed `git diff master...HEAD`: one commit, `35a41f6`, touching
`modules/nixos/brother-mfc-l2740dw.nix` (+22/-2) and adding this plan
file. Working tree and index both clean; nothing else staged. Verified
against the nixpkgs torrent actually builds from (`nixpkgs-unstable`,
`3ed67ec0a4d3c7ab4ae1f04f8ee8df07bfa506a2`,
`/nix/store/sr2lpwrcdjfpkk8gpvr98gp4nrgsijns-source`) and the systemd/cups
in the resulting closure -- by building the real artefacts rather than
reading the module: the merged unit
(`/nix/store/31nvn5mjazh63wny6j7qys7lywhgrkyd-unit-ensure-printers.service`),
the generated `ensure-printers-start` script, `cups.socket`,
`/etc/cups/cupsd.conf` and `/etc/systemd/system.conf` from
`config.system.build.etc`.

Confirmed rather than assumed, and fine:

- The four new settings land where they belong -- `StartLimitBurst` and
  `StartLimitIntervalSec` in `[Unit]`, `Restart` and `RestartSec` in
  `[Service]` -- and the `serviceConfig` override **merges with** rather
  than replaces upstream's `Type=oneshot` and `RemainAfterExit=true`.
  Both survive in the built unit. G3's claim that `on-failure` is legal on
  `Type=oneshot` holds.
- The `network-online.target` ordering from `54f1e0a` is present in the
  built unit (`After=cups.service network-online.target`), consistent with
  G1, and the stale half-sentence in the old comment ("or it fails
  outright with no retry") was correctly removed rather than left to rot.
- No new listener, no new port, no firewall change, no secret referenced
  or dereferenced, no user or group change, no capability grant, no
  sandboxing option relaxed, no `DynamicUser`/`StateDirectory` or
  impermanence interaction. Nothing under `secrets/` was read, decrypted
  or touched; nothing in this diff relates to secrets.
- `cups-browsed` -- the component behind the 2024 CUPS UDP-631 exposure --
  is off: `services.printing.browsed.enable` defaults to
  `config.services.avahi.enable` (pinned `cupsd.nix:301-304`) and avahi is
  disabled fleet-wide per D9.
- `ensure-printer-classes` is not instantiated (no `ensureClasses`), so
  the `systemctl stop cups.service` line belongs to `ensure-printers`
  itself and there is no second unit racing it.
- Hitting the start limit does not reboot, does not hold
  `multi-user.target`, and does not break the next `nixos-rebuild switch`
  (pinned-source citations in F5).
- The left-running `cups.service` adds no listening surface (F4).
- The pre-existing WSD firewall rule is reachable, not dead (F8).

Deliberately not verified: cups's internal connect timeout inside
`lpadmin -m everywhere` (source tarball not unpacked in the store, no
network in this environment) -- the sole load-bearing gap in F3, and why
that finding is PLAUSIBLE. Live on-host state (`/var/lib/cups/printers.conf`,
`lpstat -d`) was also not inspected, which is why F6 is PLAUSIBLE.

Severity counts: 0 CRITICAL, 0 HIGH, 0 MEDIUM, 3 LOW (F2, F3, F7),
4 INFO (F4, F5, F6, F8). Nothing here blocks the merge or the plan's close
under ADR-0002; the CRITICAL/HIGH class is empty. F1's surface check was
re-done and is qualified by F2 rather than edited.

_security finished 2026-09-16T21:22:15Z (code 0dbe5cbadc28aaf4) -- see Findings above._

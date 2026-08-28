---
slug: a-manual-deploy-kills-the-in-flight-weekly-restic-
created: 2026-08-28
status: todo
frozen: false
---

# a manual deploy kills the in-flight weekly restic backup and leaves the repo locked

## Original plan

Found 2026-08-28 while finishing rotation item 10. The user ran
`restic-backblazeWeekly key remove` and hit:

```
repo already locked, waiting up to 0s for the lock
unable to create lock in backend: repository is already locked by PID 1534937
on homelab by root ... lock was created at 2026-08-21 09:36:41 (172h27m ago)
```

The stale lock was the symptom. The cause is worse.

**A deploy killed an eight-hour backup mid-flight.**

```
2026-08-28T03:00:22  Starting restic-backups-backblazeWeekly.service   (PID 434197)
                     ... runs 8h 28min, uploads 66.2 GB outgoing ...
2026-08-28T11:27     generation 353 activated (the homelab-usb-uas-quirk deploy)
2026-08-28T11:28:41  Remove(<lock/93045c06f1>) failed: rclone stdio connection already closed
2026-08-28T11:28:44  restic-backups-backblazeWeekly.service: Failed with result 'exit-code'
                     Consumed 1h19m CPU over 8h28m wall, 66.2G outgoing IP traffic
```

Generation 353 activates at 11:27; restic dies 84 seconds later. The
service is not restart-safe: `switch-to-configuration` restarts units
whose definition changed, and killing restic mid-run discards the whole
run — restic has no resume.

**The guard that exists does not cover this.**
`hosts/homelab/configuration.nix` sets
`myAutoUpdate.protectedUnits = [ "restic-backups-backblazeWeekly.service" ]`
with a comment saying the weekly run "can take multiple days" and that
"a same-cycle switch would kill it mid-run." That is exactly right, and it
only guards the **auto-switch** path. A manual `nixos-rebuild switch`
consults nothing.

That gap is currently the *whole* exposure, not an edge case: all
scheduled deploys are disabled fleet-wide, so **manual deploys are the
only way anything gets deployed right now.** The protection covers the
path nobody uses and misses the path everybody uses.

**Consequences observed:**

- Last *successful* backup is **2026-08-21 08:37:35**. The repository
  holds a single snapshot, `549f74e6` from 2026-08-18, 536.817 GiB.
- Two stale locks accumulated — `f598391f…` from the 2026-08-21 run and
  `93045c06f1…` from today's killed run, whose own cleanup failed because
  rclone was already gone. Non-exclusive locks do not block `snapshots`
  or `key list`, which is why item 10's verification passed cleanly and
  the problem only surfaced at `key remove`.
- `myHealthAlerts` pages on `last-success` older than 336h/14 days.
  2026-08-21 + 14d means it fires around **2026-09-04**, which is also
  the next scheduled run. So the alarm would likely have been beaten to
  the punch by a successful run and never fired, leaving two weeks of
  no offsite backup undetected.

## Progress

- [ ] D1 decide how to protect a manual deploy
- [ ] D2 decide whether stale locks should be cleaned automatically
- [ ] confirm the 2026-09-04 run completes — the first real test
- [ ] consider whether one 536 GiB snapshot from 2026-08-18 is an
      acceptable offsite position while this is open

## Decisions (D)

### D1 — how should a manual deploy avoid killing a running backup? UNDECIDED

Options, none evaluated properly yet:

- **A pre-switch guard** that refuses (or warns) when
  `restic-backups-backblazeWeekly.service` is active. Fits the existing
  `deployGuardsScript` machinery. Has to reach manual `nixos-rebuild`
  too, which is the hard part — that is not a repo-controlled entry
  point.
- **Make the unit survive activation** rather than trying to schedule
  around it: `RemainAfterExit`/`X-RestartIfChanged = false`, or
  `systemd.services.<name>.restartIfChanged = false`, so
  switch-to-configuration leaves a running instance alone. Narrower and
  entirely within the repo's control. Needs care: a genuinely changed
  unit then does not take effect until the next run, which is a
  different kind of surprise.
- **Both**, since they fail differently: the guard stops a human at the
  right moment, `restartIfChanged = false` protects the case where the
  human is not watching.

Whatever is chosen belongs with
`rebuild-the-update-build-deploy-pipeline-properly-2026-08-27.md` rather
than being bolted on, since that plan is already reconsidering how
deploys are gated.

### D2 — should stale locks be cleaned up automatically? UNDECIDED

An interrupted run reliably leaves a lock, and a lock silently blocks the
*next* exclusive operation (prune, `key remove`, `unlock` itself) while
leaving read operations working. That combination is why this sat for a
week unnoticed.

`restic unlock` in `backupPrepareCommand` would clear stale locks before
each run. Worth weighing against the obvious objection: automatic
unlocking removes the safety property that a lock is supposed to provide,
and would mask exactly the "a run died" signal that surfaced this.
Possibly better as a health check that *reports* stale locks rather than
one that clears them.

## Gotchas (G)

### G1 — item 10's verification passed cleanly with the repository in this state

`restic-backblazeWeekly snapshots` and `key list` both take
**non-exclusive** locks, so they succeeded against a repository that had
been locked for a week and whose last backup had failed. The rotation
verification was sound for what it tested — the new password does open
the repository, and the key-slot marker did move — but it says nothing
about whether backups are *working*.

Worth generalising: "the credential works" and "the service works" are
different claims, and this audit has now been caught by that distinction
in the opposite direction too (WireGuard, factorio and the Discord
webhook all had working credentials that never reached their consumer).

### G2 — the kill was not caused by the audit's own deploys, and that is the point

Generation 353 (11:27) is the `homelab-usb-uas-quirk` deploy; this
session's deploys are 354 (12:28) through 358 (13:59), all after restic
had already failed at 11:28:44. So no rotation work caused this. It
matters only because it shows the failure needs no unusual circumstances
— an ordinary deploy on an ordinary Friday morning was enough.

## Findings (F)
*(populated by security/docs-updater when invoked)*

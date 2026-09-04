---
slug: automated-canary-based-backup-restore-and-verify-tier-1
created: 2026-09-04
status: in-progress
frozen: false
---

# Automated canary-based backup restore-and-verify (Tier 1)

## Original plan

Neither backup path (`zrepl` → `zbackup`, `restic` → Backblaze) has ever
been restored from — `docs/procedures/backup-restore.md` says so itself,
and the security audit's F-P6-15 and F-P6-07 both flag it: existing
alerting (`myHealthAlerts.backupStaleness`/`staleMarkerFiles`) only proves
data is *advancing*, never that it can actually be read back out.

Workshopped into three tiers by cost/depth. This plan covers **Tier 1
only**: a small, automated, low-cost restore-and-verify that runs on its
own schedule and fails loudly (existing Discord alert pipeline) the moment
either backup path's restore mechanism breaks. It does not attempt to
validate real user data or restore performance at scale — that's Tier 3
(`2026-08-25-build-and-test-a-full-restore-suite-scripts-proced.md`),
which this plan's canary infrastructure feeds into rather than duplicates.

Design, seeded by research into how this is done in practice (restic's own
forum, AWS Backup / DR-testing guides, real ransomware-recovery drills):

- **Canary files, not real data.** A small, static, known-content file
  seeded at a fixed relative path inside every dataset that's actually
  backed up (both by `zrepl` and, where they overlap, by `restic`).
  Restoring it and comparing content proves the whole mechanism —
  snapshot → replicate/upload → restore → readable → correct bytes —
  without the cost of validating real data.
- **zbackup path, daily:** `zfs clone` the target snapshot to ephemeral
  scratch, read + compare the canary, destroy the clone. Alternates
  between each dataset's newest and oldest still-retained snapshot
  (restic-forum lesson: always testing the newest hides a retention/prune
  regression that only shows up on the tail of the grid).
- **restic path, right after the weekly run:** restore just the canary
  files (small download, not the 885GB dataset), compare content, clean
  up. Triggered by `OnSuccess=` on `restic-backups-backblazeWeekly.service`
  rather than chained into its own `ExecStartPost` — keeps "backup
  succeeded" and "backup is provably restorable" as two independent
  signals instead of conflating them.
- **No new alert plumbing.** A failing check trips `systemctl --failed`
  (already caught by `health-check`'s `failed-units` check); a successful
  run touches a marker file registered in `myHealthAlerts.staleMarkerFiles`
  (already the "did this even run" pattern, dead-man's-switch style —
  matches industry practice of alerting on *absence* of a success signal,
  not just on failure).

## State

**2026-09-04, starting implementation.** Plan written and both design
decisions confirmed. Next: write `modules/nixos/backup-canary.nix` and
`modules/nixos/backup-restore-test.nix`, wire homelab/torrent/thinkpad,
verify-ladder, commit.

## Progress
- [x] D1
- [x] D2
- [x] `modules/nixos/backup-canary.nix` — seeds canary files via
      `systemd.tmpfiles.rules`
- [x] `modules/nixos/backup-restore-test.nix` — zbackup + restic
      restore-and-verify services
- [x] Wire `modules/flake/hosts.nix`
- [x] Wire `hosts/homelab/configuration.nix` (canary paths, restore-test
      config, `myHealthAlerts` markers, restic `OnSuccess=`)
- [x] Wire `hosts/torrent/configuration.nix` (canary paths)
- [x] Wire `hosts/thinkpad/configuration.nix` (canary paths)
- [x] Verify ladder (nixfmt --check, flake check --no-build, targeted
      build for all 5 hosts) — all green
- [ ] `/simplify`
- [x] G1
- [x] G2
- [x] G3
- [x] G4

## Decisions (D)

### D1 -- how much scope to build now: just the cheap automated tier, or more?
Workshopped three tiers (cheap automated canary check / monthly heavier
real-dataset spot check / rare manual full-DR drill). Asked whether to
build just Tier 1, Tier 1+2, or design all three now.


**ANSWERED 2026-09-04:** User: drop Tier 2 entirely, fold its real-data/scale-check value into Tier 3. Build Tier 1 now.

### D2 -- cadence for the automated canary check
zbackup and restic have very different cost profiles (local zfs clone vs
a B2 download after a multi-hour weekly upload) — asked whether they
should share one cadence or run independently.


**ANSWERED 2026-09-04:** User: zbackup daily (cheap local zfs clone), restic right after each weekly backblazeWeekly run.

## Gotchas (G)

### G1 -- canary seeding must survive impermanence, so it goes through tmpfiles, not a one-time write
homelab's `/` is impermanence-rolled-back with persistent state living
under `/nix/state`; thinkpad has `@blank` on *both* `zroot/local/root` and
`zroot/local/home` (`docs/backups.md`), meaning a plain one-time file write
under `/` or `/home` on thinkpad would vanish on the next reboot before
ever being snapshotted. `systemd.tmpfiles.rules` with `f+` (declarative,
re-asserted on every boot via `systemd-tmpfiles-setup.service`, run before
zrepl's 5m snapshot cadence would ever catch a stale/missing file) sidesteps
this entirely regardless of a host's impermanence status — recreates the
canary post-rollback with no separate seeding service needed.

### G2 -- restic's archived paths embed the variable snapshot name; the restore include-glob must match within one path segment, not rely on `**`
`backupPrepareCommand` mounts each snapshot at
`$RUNTIME_DIRECTORY/<dataset>@<zrepl-timestamp>/...`, and that whole path
is what restic backs up (`paths = [ "/run/restic-backups-backblazeWeekly" ]`).
The timestamp component varies every run, so the restore-test's
`--include` pattern uses a single `*` confined to the `<dataset>@*`
segment (e.g. `/run/restic-backups-backblazeWeekly/zdata/storage/storage@*/.backup-canary/canary.txt`)
rather than a cross-segment `**` glob, which not every restic version
matches consistently — kept the pattern to a form that's been reliable
across restic releases instead of assuming a specific glob dialect.

### G3 -- every restore-test `zfs clone` forces `mountpoint`/`canmount`, doesn't inherit them
`zfs clone -o mountpoint=legacy -o canmount=on` is set explicitly on every
clone this module makes, rather than trusting whatever the received
dataset's properties happen to be. This is cheap defense-in-depth against
the still-open F-P6-03 finding (a compromised source host can poison
`mountpoint`/`canmount` in its `zfs send` stream, and homelab's receive
side currently applies no override) — it does **not** fix F-P6-03 itself,
which is a receive-side fix belonging to `zrepl.nix`'s `mkRecv`, not this
module. Worth landing that fix around the same time rather than treating
them as unrelated.

### G4 -- restic's check hooks off `OnSuccess=`, not `ExecStartPost`, to keep the two signals independent
Chaining the restore-test into `restic-backups-backblazeWeekly`'s own
`ExecStartPost` (which already touches `last-success` for the existing
staleness check) would mean a broken *verification* step blocks that
touch and makes a perfectly good backup look stale/failed. `unitConfig.OnSuccess`
starts the restore-test service as a separate unit only once the backup
unit exits successfully, so a verification failure shows up as its own
distinct alert (its own marker file, its own `failed-units` entry) instead
of masquerading as a backup failure.

## Findings (F)
*(populated by security/docs-updater when invoked)*

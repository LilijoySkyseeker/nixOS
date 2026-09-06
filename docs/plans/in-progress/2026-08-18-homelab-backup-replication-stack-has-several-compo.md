---
slug: homelab-backup-replication-stack-has-several-compo
created: 2026-08-18
status: in-progress
frozen: false
---

# homelab backup/replication stack has several compounding risks if the box is powered off for an extended period (over a month), surfaced while reasoning through the full backup reset/re-test

## Original plan

- [ ] **2026-08-18: homelab backup/replication stack has several
      compounding risks if the box is powered off for an extended
      period (over a month), surfaced while reasoning through the full
      backup reset/re-test.** Grouped as one item since they originally
      shared a root cause (everything below was `Persistent = true`,
      firing its one missed catch-up run right at boot, all at once).
      **Partially reworked since 2026-08-18 — re-assessed 2026-08-25,
      not fully closed:**
      - **Boot-time contention pile-up — resolved 2026-08-25.** sanoid
        and syncoid (the original minutely/hourly `Persistent = true`
        timers this bullet was written about) no longer exist — replaced
        repo-wide by zrepl, a long-running daemon whose jobs run on
        their own internal interval from whenever the daemon starts, not
        systemd timer catch-up semantics. That already removed this
        specific pile-up mechanism for ZFS snapshotting/replication. The
        remaining three (`restic-backups-backblazeWeekly`'s timer plus
        both `myAutoUpdate` timers, fetch + switch) now have
        `Persistent = false` (`modules/nixos/auto-update.nix`,
        `hosts/homelab/configuration.nix`) instead of the
        `RandomizedDelaySec`/jitter approach first considered — a missed
        run after a long outage is skipped rather than fired
        immediately at boot, which removes the contention with zrepl's
        post-boot catch-up entirely rather than just spreading it over a
        smaller window. Chosen over jitter because none of the three
        need immediate catch-up (flake-update-test/auto-switch: a
        week's delay is a non-issue given `minSwitchInterval` already
        treats weekly cadence as normal; restic: already has a
        336h/14-day staleness alert via `myHealthAlerts` as a backstop,
        so a skipped cycle isn't silent). **Deployed to homelab
        2026-08-26** (`nixos-rebuild switch --flake .#homelab
        --target-host root@homelab`, off master post-merge — the
        `worktree-stagger-boot-timers` branch was already fully merged,
        this just landed it on the live box) — confirmed live via
        `systemctl cat` on all three units
        (`restic-backups-backblazeWeekly.timer`, `auto-switch.timer`,
        `flake-update-test.timer`) showing `Persistent=false`, no
        failed units post-switch. Still not observed through a real
        long-outage reboot (nothing to trigger that intentionally).
      - **Compounds directly with the item above**: **partially
        addressed.** `hosts/homelab/configuration.nix` now sets
        `myAutoUpdate.protectedUnits = [
        "restic-backups-backblazeWeekly.service" ]`, and
        `modules/flake/deploy-guards.nix`'s
        `check_protected_units_inactive` makes a scheduled auto-switch
        skip (and retry next cycle) rather than switch while that unit
        is active — see the git-identity entry in `docs/DONE.md`. This
        closes the specific "switch kills a mid-run backup" collision,
        but doesn't address the raw boot-time resource contention
        itself (previous bullet).
      - **Self-inflicted history loss from the `--keep-daily 2`
        retention** (disaster-recovery-only, not versioning, per
        explicit choice): once the first post-outage backup succeeds,
        its prune step drops straight to the 2 most recent backup-days,
        permanently discarding all pre-outage B2 history at that point.
        Intentional given the retention philosophy, but worth having a
        documented awareness of before it surprises someone during an
        actual recovery. Unchanged, still applies.
      - **Syncoid resume-base pruning — moot, mechanism replaced.** The
        specific failure mode (a stuck syncoid target's incremental base
        getting pruned before it catches up) no longer applies now that
        syncoid is gone; zrepl has its own hold/bookmark-based
        incremental-base guarantees (see the zrepl entry in
        `docs/DONE.md`), which is a different mechanism with different
        (already-encountered-and-fixed) failure modes, not a direct
        continuation of this specific risk.
      - **B2 key expiration — confirmed 2026-08-25 (user checked the B2
        web console): no expiration set** on the application key backing
        `homelab_backblaze_rclone_config`. Closed.
      Still open: the `--keep-daily 2` history-loss caveat above
      (intentional, just needs to stay documented) and observing the
      `Persistent = false` deploy through an actual long-outage reboot.

## State
**2026-08-30.** Manually triggered `restic-backups-backblazeWeekly` end to
end (2026-08-29 22:50 -> 2026-08-30 08:46, 9h56m) to clear the Aug 21
staleness and check on the Aug 28 failure. Run succeeded, `last-success`
marker updated, `restic check` reports no errors. Confirmed pruning is
already automatic (G1) and captured a full timing/throughput benchmark
(G3) for sizing future backup work. One loose end: G2's orphaned-pack
warning should be re-checked on the next scheduled run (Fri 2026-09-04)
to confirm it clears on its own.

**2026-09-04.** Re-checked: it did **not** clear on its own. The
`restic-backups-backblazeWeekly.service` run at 03:00 today logged the
same `63 additional files were found in the repo, which likely contain
duplicate data` message, then `no errors were found` on the integrity
check — identical to the 2026-08-30 count. Automatic `forget --prune`
is not reaching these packs. Assumption in G2 below was wrong; a manual
`restic prune` is the actual fix, not a wait-and-see.

## Progress
- [x] G1 -- confirmed pruning is already automatic
- [ ] G2 -- confirm orphaned-pack warning clears on the 2026-09-04 scheduled run
- [x] G3 -- captured full-run timing/throughput benchmark

## Decisions (D)


## Gotchas (G)
### G1 -- pruning is already automatic, not something to add
Confirmed against the pinned nixpkgs `nixos/modules/services/backup/restic.nix`
(`pruneCmd`/`checkCmd` construction, ~line 409-464): when `pruneOpts` is
non-empty, the module appends `restic unlock` + `restic forget --prune
<pruneOpts>` to the *same* `ExecStart` as the backup itself, then `restic
check` -- all inside one `restic-backups-backblazeWeekly.service` run, in
that order. `hosts/homelab/configuration.nix`'s `backblazeWeekly` block
already sets `pruneOpts = [ "--retry-lock 15m" "--keep-daily 2" ]`, so
this was already wired up. The 2026-08-30 manual run's own journal
confirms it executed: `Applying Policy: keep 2 daily snapshots` /
`keep 2 snapshots: 549f74e6 ... 6ec73aed ...`. Nothing to fix here --
noting it so a future read of this plan doesn't re-propose it.

### G2 -- an interrupted run leaves orphaned B2 pack data that the very next automatic prune doesn't fully clear
The 2026-08-30 run's `restic check` step (which runs *after* `forget
--prune` in the same service invocation, see G1) reported: `63 additional
files were found in the repo, which likely contain duplicate data. This
is non-critical, you can run 'restic prune' to correct this.` These are
almost certainly leftover pack files from the 2026-08-28 run that failed
with `unable to save snapshot: context canceled` -- data was uploaded to
B2 but never referenced by a completed snapshot/index, so the following
run's `forget --prune` (which prunes data unreachable from *kept*
snapshots) didn't have a snapshot to hang the cleanup off. Working
hypothesis, not yet confirmed: this self-resolves via the `rclone backend
lifecycle ... daysFromHidingToDeleting=1` B2 setting
(`hosts/homelab/configuration.nix` `ExecStartPre`) once whatever `prune`
already hid finishes its 1-day hide-to-delete window, and/or clears on
the *next* scheduled run's `forget --prune` once the orphan packs are
visible to that run's index load. **Needs a check on the next scheduled
run (Fri 2026-09-04)**: if the "additional files" warning is gone,
hypothesis confirmed, nothing to do. If it persists or grows, that's a
real gap -- interrupted runs need an explicit `restic prune` (or
`unlock` + `prune`) as part of recovering from a failure, not just
waiting for the next weekly run.

### G3 -- full manual-run timing/throughput benchmark (2026-08-29 22:50 -> 2026-08-30 08:46, 9h56m total)
Captured while watching this run live (hourly ETA checks cross-referenced
against `zpool iostat`, `/proc/<pid>/io`, and a Cloudflare upload-speed
test), useful as a real baseline for sizing any future backup redesign:
- **Scan/hash phase: ~45 min.** CPU-bound (restic pegged ~97% of one
  core hashing for content-defined chunking). Read up to ~500 MB/s where
  ZFS ARC-cached, but the *real* disk-bound ceiling -- confirmed via
  `zpool iostat -v` sustained samples once cache-cold -- is **~260-280
  MB/s combined**, split ~130-140 MB/s per disk across the `zdata`
  mirror's 2x HGST Ultrastar He12 (`HUH721212ALE601`, 12TB, 7200rpm,
  USB-attached). That matches this drive model's rated sustained
  sequential throughput -- the mirror isn't doubling single-disk speed
  here, ZFS is splitting reads across both sides of the mirror.
- **Upload phase: ~9h, the dominant cost.** Steady, remarkably flat
  **~2.5 MB/s** the entire time (verified hour over hour: 2.54, 2.53,
  2.52, 2.55, 2.55, 2.54 MB/s) -- this matches homelab's directly
  measured upload bandwidth (**2.31 MB/s / 18.5 Mbps**, via a 50MB
  upload to `speed.cloudflare.com/__up`) almost exactly. **Home upload
  bandwidth, not disk, not CPU, not B2/rclone, is the hard ceiling on
  this backup's runtime.** Total uploaded this run: 83.31 GB -- larger
  than any working hypothesis tried along the way (not just the ~66 GB
  the failed 2026-08-28 run had pushed before erroring), so this genuinely
  was a heavier-than-usual delta, not just a re-push of the failed run's
  data.
- **Check phase: ~3.5 min** (`--read-data-subset=1%`, 380/380 packs, no
  errors -- see G2 for the one non-error note it did raise).
- **Sizing implication:** at the measured ~2.3 MB/s (~8.3 GB/hour)
  upload ceiling, runtime is now essentially `(new/changed data in GB) /
  8.3` hours, full stop, once the ~45min scan overhead is accounted for.
  A future redesign (dedicated backup-window scheduling, WAN upgrade,
  smaller backup scope, more frequent/smaller runs to cap the worst-case
  delta) should size against this rate, not against the `~2.9TiB of I/O`
  estimate in `modules/nixos/auto-update.nix`'s comment or the original
  2026-08-18 plan bullet above -- that figure predates any real
  measurement and looks like a pessimistic guess (actual dataset
  `refer` size is ~885 GB today, and the very first full backup on
  2026-08-21 uploaded 522.8 GB, not 2.9 TiB).

## Findings (F)
*(populated by security/docs-updater when invoked)*

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

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

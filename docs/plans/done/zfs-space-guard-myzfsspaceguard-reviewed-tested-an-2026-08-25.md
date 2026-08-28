---
slug: zfs-space-guard-myzfsspaceguard-reviewed-tested-an
created: 2026-08-25
status: done
frozen: true
---

# `zfs-space-guard` (`myZfsSpaceGuard`) reviewed, tested, and simplified down to what the actual use case needs

## Original plan

- [x] **2026-08-25: `zfs-space-guard` (`myZfsSpaceGuard`) reviewed,
      tested, and simplified down to what the actual use case needs.**
      Split out of the (now-superseded, see below) `myBackupPush` item's
      checklist since this module is still live and unrelated to that
      item's fate.

      **Reviewed and tested, both automated and manual.** Found and
      fixed a real bug while reviewing: `cap=$(zpool list -Hpo capacity
      $pool)` on a failed/garbage read (bad pool name, exported pool,
      transient hiccup) made the numeric threshold test error out, and
      bash treats a failed `[ ]` as the `if` being false — so the old
      script fell through to the *unconditional prune* branch instead of
      skipping. Reproduced directly: `bash -c 'cap=""; if [ "$cap" -lt
      85 ]; then echo skip; else echo PRUNE; fi'` prints PRUNE. Now
      validates `$cap` is non-empty/numeric first and exits 1 instead of
      falling through. Added `tests/zfs-space-guard.nix`
      (`checks.zfs-space-guard`, `nix build
      .#checks.x86_64-linux.zfs-space-guard`), a permanent runNixOSTest
      covering healthy/pressure/keepMin-floor/zrepl-style-hold-tolerance/
      emergency-prune/this-bug's-regression — all green. Manually
      verified live on torrent (thinkpad skipped — identical setup,
      torrent's testing translates): timer active, journal showed no
      evidence the bug had ever fired for real (real capacity has been
      sitting at 79%, close to the 85% trigger); confirmed the real
      no-op path, then temporarily raised `freeThresholdPercent` to 25 to
      force a real trigger at that capacity, `build`+`switch`+ran it for
      real — pruned `zroot/local/{home,root}` from 30 snapshots down to
      exactly `keepMin`=2 each, then reverted the threshold and switched
      back (clean, byte-identical store path to before). Also ran
      `zfs-emergency-prune.service` for real, down to the single newest
      snapshot per dataset. Confirmed the safety net held throughout:
      homelab's zrepl pull for torrent stayed incremental with no forced
      full-send, replicating the very snapshots taken during/after the
      test.

      **Same day, follow-up: re-examined the actual use case and removed
      the auto-prune half entirely.** The real need is "I downloaded a
      game, disk is nearly full, I delete something to install a
      different one and need that space back *right then*" — not a
      background timer. Capacity-threshold auto-pruning down to a
      keep-newest floor doesn't solve that: ZFS doesn't free a deleted
      file's blocks until every snapshot referencing them is gone, and
      whatever snapshot is newest at delete time was almost always taken
      *before* the delete (zrepl snapshots on its own 5m clock, unrelated
      to when you delete something) — proved this empirically in the VM
      test before removing anything: writing a file, snapshotting it,
      deleting it, then running the old "keep newest 1" emergency-prune
      left real pool space unreclaimed, because the one surviving
      snapshot still held the file.
      Removed `zfs-space-guard.timer`/`.service` and the
      `pool`/`freeThresholdPercent`/`keepMin`/`checkInterval` options
      entirely — dead weight that never solved the actual problem. Kept
      and repointed `zfs-emergency-prune.service`: now destroys every
      local snapshot except one named exactly `@blank` (the impermanence
      rollback point disko creates once at install), instead of "keep
      the newest one" — since every host is expected to end up on
      impermanence, `@blank` is the one snapshot that must never go, and
      destroying everything else guarantees full reclaim regardless of
      snapshot timing. On a host without `@blank` yet (torrent — see the
      impermanence migration item), this destroys everything, which is
      the documented fallback, not a bug. `tests/zfs-space-guard.nix`
      rewritten to match (blank-preservation + real space-reclaim +
      no-blank-fallback + hold-tolerance); host configs on torrent and
      thinkpad updated to drop the removed options; both hosts build
      clean.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

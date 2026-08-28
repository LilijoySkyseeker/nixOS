---
slug: torrent-s-backup-push-torrent-service-home-dataset
created: 2026-08-23
status: done
frozen: true
---

# torrent's `backup-push-torrent.service` (`home` dataset) is now stuck — needs a decision, not further automated action

## Original plan

- [x] **2026-08-23: torrent's `backup-push-torrent.service` (`home`
      dataset) is now stuck — needs a decision, not further automated
      action.** The initial full send finished transferring all ~3.13TB
      successfully, but the same syncoid invocation then tried to also
      send a trailing incremental to catch up to the latest snapshot, and
      that failed: the base snapshot it needed had already been pruned by
      torrent's own local sanoid retention during the ~38-40h transfer.
      Needed a decision on whether to force a full resend or leave the
      stale backup as-is, plus a structural fix so a future large
      transfer can't hit the same trap (widen source retention, or split
      the full-send/incremental-catchup syncoid invocations so a bookmark
      always lands after a successful full send).

      **Superseded 2026-08-25, not actually resolved on its own terms.**
      The zrepl migration (above) deleted `backup-push.nix` and the
      syncoid-based push mechanism entirely, replacing it with zrepl's
      pull-based topology repo-wide — the stuck `home` dataset, the
      pruned-bookmark trap, and the retention-window fix this item called
      for all describe a mechanism that no longer exists. Moved here
      rather than left open since there's nothing left to act on; the
      underlying lesson (a long-running transfer can outlast source-side
      snapshot retention, breaking the incremental base) is still valid
      and worth remembering for any future large `zfs send`, but the
      specific fix no longer applies to this repo's current backup
      architecture.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

---
slug: docs-procedures-backup-restore-md-needs-real-conte
created: 2026-08-20
status: done
frozen: true
---

# `docs/procedures/backup-restore.md` needs real content once the `zbackup` restructuring lands

## Original plan

- [x] **2026-08-20: `docs/procedures/backup-restore.md` needs real
      content once the `zbackup` restructuring lands.** Was a placeholder
      — restore steps were deliberately deferred pending the in-flight
      `zbackup` restructuring and a separate `zfs-pool-recovery-restore`
      sanoid-module refactor.

      **Landed.** `docs/procedures/backup-restore.md` is now 140 lines of
      real zrepl-restore content (dataset-path mechanics, clone-based
      file recovery, rollback, full-dataset restore), confirmed live
      2026-08-25. It already self-documents its own remaining gap ("
      written from the mechanics, not yet exercised... tracked in
      `TODO.md`"), which is exactly what `TODO.md`'s still-open "build
      and test a full restore suite" entry covers — no separate action
      needed here.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

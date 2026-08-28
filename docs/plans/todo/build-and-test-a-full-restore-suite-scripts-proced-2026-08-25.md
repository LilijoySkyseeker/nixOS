---
slug: build-and-test-a-full-restore-suite-scripts-proced
created: 2026-08-25
status: todo
frozen: false
---

# build and test a full restore suite (scripts + procedures) against real data — out of scope of the zrepl migration itself

## Original plan

- [ ] **2026-08-25: build and test a full restore suite (scripts +
      procedures) against real data — out of scope of the zrepl
      migration itself.** The zrepl migration (branch
      `worktree-zrepl-migration-plan`) documents restore *paths* in
      `docs/procedures/backup-restore.md`, but per its handoff notes
      these remain unexercised against real data: the VM test
      (`docs/procedures/vm-testing.md`) only covers clone-based file
      recovery, and rollback / full-dataset restore have never been
      run for real. Needs: actual restore drills (clone-based file
      recovery, full-dataset rollback, disaster-recovery-from-scratch)
      for each host's `zbackup/backup/<host>/...` data, ideally scripted
      and repeatable rather than one-off manual runs, plus writing up
      the verified procedure in `docs/procedures/backup-restore.md` in
      place of the current unexercised steps. Supersedes the 2026-08-20
      "`docs/procedures/backup-restore.md` needs real content" entry,
      moved to `docs/DONE.md` 2026-08-25 once confirmed the doc already
      has real (if unexercised) content — this item is what's left.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

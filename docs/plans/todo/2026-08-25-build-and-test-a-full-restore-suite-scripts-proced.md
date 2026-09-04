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

**2026-09-04 addendum:** workshopped into a tiered backup-testing design.
This plan is now specifically **Tier 3** of that design — the rare,
manual, full-scale drill (full-dataset restore, disaster-recovery-from-
scratch, against real data) — rather than the whole testing effort. A
cheap, fully automated **Tier 1** (canary-file restore-and-verify, daily
for `zbackup`/weekly for restic, wired into the existing Discord alert
pipeline) now runs independently and is tracked in
`2026-09-04-automated-canary-based-backup-restore-and-verify-tier-1.md` —
that plan does not replace this one, since a canary file restoring
correctly says nothing about whether a multi-hundred-GB real restore
completes in a sane time or preserves real-world file metadata
(permissions, xattrs, symlinks, unusual filenames). A previously-considered
middle tier (an automated monthly real-dataset spot check) was dropped as
its own cadence — not necessary to satisfy "tested regularly, fails
loudly," which Tier 1 already covers — and its value (real data, at real
scale) folded into this plan's scope instead: the drill(s) built here
should include a real-data restore-timing/fidelity check, not just the
mechanics already covered by Tier 1's canary.

**2026-09-04, second addendum (user):** the drill must be a hybrid of
fire-drill and real recovery tooling, not a separate test harness that
imitates one. The script(s) and runbook this plan produces should *be* the
actual procedure a real disaster recovery would run — the goal is that
running the drill periodically **is** exercising the real deal, so there
is never a gap between "what we tested" and "what we'd actually do,"
which is the classic way DR runbooks silently rot: a test script drifts
from the real procedure and nobody notices until the real recovery hits a
step the drill never covered. Concretely: `docs/procedures/backup-restore.md`
should stop being hand-written prose describing commands to type, and
become (or directly wrap) the same scripted procedure the drill executes
-- one artifact, used for both the periodic drill and a real recovery,
not two that are supposed to stay in sync by discipline.

## State

**2026-09-04.** Not started. Scope narrowed to Tier 3 (see addendum
above); still todo, no drill has been run yet against either backup path.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

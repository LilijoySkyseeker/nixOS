---
slug: git-reset-checkout-do-not-revert-a-path-with-no-he
created: 2026-08-27
status: done
frozen: true
---

# git reset/checkout do not revert a path with no HEAD version

## Original plan

Discovered while committing the work tracked in the (now frozen)
`2026-08-27-establish-the-workflow-and-plan-file-system.md`: the
`.githooks/pre-commit` frozen-file check correctly blocked a real
corruption in `docs/plans/done/2026-08-25-add-fail2ban-to-vps-defaulting-to-an-
immediate-ban.md` -- 5 leftover "tampered content" lines from
earlier hook testing that this session's own cleanup steps claimed to
have reverted, repeatedly, and were wrong every time.

## Progress

- [x] Root-caused, fixed (removed the 5 stray lines, restored the correct
      placeholder line, recomputed and corrected the checksum manifest
      entry, removed one other stale manifest entry for an already-deleted
      throwaway test file), and verified all 22 manifest entries now match
      their files' actual content.
- [x] Confirmed no other file in the repo carries the same leftover text
      (`git grep -l "tampered content"` repo-wide, clean).

## Decisions (D)

## Gotchas (G)

### G1 — `git reset`/`git checkout` on a path with no HEAD version does nothing useful
The test pattern used repeatedly this session —
`git add "$f" && ./pre-commit-test && git reset -- "$f" && git checkout -- "$f"`
— silently failed to revert anything, every single time it was used
against a file that had never been through an actual `git commit` (true
for every `docs/plans/` file created this session, since nothing had been
committed yet). `git reset -- "$f"` resets the *index* entry for that path
back to whatever is in `HEAD` — but `HEAD` has no entry for a path that's
never been committed, so the effect is to **unstage** the addition, not
restore prior content. `git checkout -- "$f"` (checkout-from-index) then
has nothing valid to check out for a path that no longer has a proper
index/HEAD relationship, and either errors (`pathspec ... did not match
any file(s) known to git`, seen but wrongly dismissed as inconsequential
at the time) or leaves the working-tree file exactly as it was —
tampered. The `git diff --stat` check used to "confirm" the revert only
compares *tracked/staged* content, so once the file was unstaged by
`git reset`, the diff had nothing to compare against and printed nothing
— which looked exactly like a clean revert, and was reported to the user
as one, incorrectly, more than once in this session's transcript.

**The actual fix for this test pattern going forward**: for a file that
has never been committed, revert test tampering with `git show
:"$f" > "$f"` only works if something is still staged and correct to
restore from -- more robust is to just keep a real backup copy (`cp`)
before tampering and restore from that, exactly as this session did
correctly for the deadnix/statix positive-detection test
(`cp tests/zfs-space-guard.nix /tmp/...bak`) but did NOT do for the
frozen-file tamper tests. The git-native "revert" pattern is only safe
once a file has at least one real commit to reset/checkout back to.

## Findings (F)
*(populated by security/docs-updater when invoked)*

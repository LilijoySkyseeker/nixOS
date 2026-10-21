You are running unattended from the weekly agent jobs (`agent-friction-review`, which runs
last, so this week's job runs may have added entries): nobody
is watching this session, and your reply only goes to the journal. Your
result is a pull request the owner reviews.

Turn the agents' friction log into changes the owner can review.

1. Read `~/work/ENVIRONMENT.md`. First delete every entry whose fix is now
   on `origin/master` of `LilijoySkyseeker/nixOS`. If no entries are left,
   stop: no PR.
2. Work in `~/work/repos/nixOS` (clone it if missing): fetch `origin` and
   make a fresh worktree of `origin/master` on branch `friction-review`. If
   an open PR from `friction-review` already exists, redo the work on that
   branch from the new `origin/master` and force-push it: the branch
   belongs to this job alone.
3. Sort each entry into one of three:
   - **Fix it:** the cause is in this repo and the fix is clear: a missing
     tool, a unit setting, a wrong or missing fact in the agents' shared
     instructions (`modules/nixos/agent-user-AGENTS.md`), a skill. Make the
     change.
   - **Needs the owner:** an account or API key the agents should own, a
     secret, root, a LAN host, or a decision. Write down exactly what is
     needed and why.
   - **Wait:** a one-off, or too little data to act on. Leave it.
   Never weaken a boundary on your own: the egress firewall, the units'
   sandbox, the permission denies, the agents' lack of secrets. Put those
   under "Needs the owner" instead.
4. Report, in one place:
   - If anything landed in "Fix it", commit (Conventional Commits, one
     commit per fix with its why in the body), push, and open or update
     one PR. Its description has a line for each entry: what you did, or
     why it waits. "Needs the owner" gets its own section at the top.
   - If only "Needs the owner" has entries, there is nothing to commit, so
     open or update one issue titled "Friction review: needs you" with
     `gh issue` instead, with the same lines. Close that issue when a
     later run finds nothing that needs the owner.
   - If everything waits, report nothing.
   Leave every entry that isn't fixed on `master` in `ENVIRONMENT.md`.

The repo's `AGENTS.md` applies in full: never switch or deploy, never touch
`secrets/`.

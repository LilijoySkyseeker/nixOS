---
slug: resolve-whether-samba-s-var-lib-samba-persistence-
created: 2026-08-27
status: todo
frozen: false
---

# Resolve whether samba's /var/lib/samba persistence is actually necessary

## Original plan

Two independent, mutually contradictory claims about
`modules/services/samba.nix`'s `/var/lib/samba` impermanence persistence
entry, neither one build- or runtime-verified:

1. The 2026-08-26 security audit (`worktree-security-audit-plan` branch,
   `docs/audits/2026-08-26/P4-services.md:1337-1339`, an appreciative
   remark, not an investigated `F-P4-*` finding) asserts persistence is
   *required*: "`/var/lib/samba` is persisted, without which the whole
   mechanism would silently reset each boot."
2. The `security` subagent's live test run (see finding F1 in
   `establish-the-workflow-and-plan-file-system-2026-08-27.md`, a real
   invocation, not synthetic) asserts the opposite: `samba-user-
   provision`'s script (`modules/services/samba.nix:127-140`) checks
   `pdbedit -L` for the existing user and branches to `smbpasswd -s -a`
   (add) when absent vs. `smbpasswd -s` (set) when present -- so an
   unpersisted (wiped-every-boot) `/var/lib/samba` would simply always
   take the "add" branch, which should recreate the user cleanly each
   time (Samba's tdbsam backend auto-creates `passdb.tdb` on first write).
   If true, the persistence is not just unneeded but actively costs
   something: the NTLM password hash in `passdb.tdb` rides along in
   `zroot/local/state`, which is zrepl-replicated to the unencrypted
   `zbackup` pool and one of the two datasets pushed to Backblaze weekly.

Neither claim has been verified against an actual boot -- both are
source-reading-level reasoning (the audit's more so; the subagent's traces
the actual conditional logic but still stops short of a real test). Per
`docs/procedures/workflow.md`'s trust hierarchy, this needs to climb to
"local build with output inspected" or a real VM/host boot before either
side is trusted -- **explicitly tabled, not fixed, per the user's
instruction.**

## Progress

- [ ] Test on an actual boot (VM per `docs/procedures/vm-testing.md`, or a
      real homelab reboot window) whether wiping/renaming
      `/var/lib/samba` and letting `samba-user-provision` run from empty
      state produces a working `android-smb` login afterward.
- [ ] If the subagent's claim holds, remove `/var/lib/samba` from
      homelab's impermanence persistence list and redeploy; if the
      audit's claim holds (something else in that directory genuinely
      needs to survive a reboot), document why in a comment citing this
      plan, and correct/annotate F1 in the frozen plan's citation trail
      (the frozen file itself can't be edited -- this plan's own
      resolution is where that correction lives).

## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

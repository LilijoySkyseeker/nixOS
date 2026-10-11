# Full-disk encryption and Secure Boot on thinkpad

## Goal

A stolen thinkpad shouldn't hand over its data or its sops age key
(accepted-risks D5: neither laptop has FDE, and thinkpad hibernates to
unencrypted swap).

## Your decisions

- 2026-10-06: keep this for thinkpad. Dropped: PC impermanence and the
  distributed-builders work that shared a plan with it.

## State

Not started on master. A drafted plan and partial implementation exist
on the stale branch `origin/worktree-fde-secureboot-plan` (19 commits,
last touched 2026-08-20): FDE + Secure Boot + TPM2 auto-unlock, per-host
`RECOVERY.md` runbooks and a `scripts/reinstall-host.sh`. It predates the
zrepl migration and everything since, so treat it as direction, not
code to merge. It also folded in PC impermanence, which is now dropped.

## Next

Decide the approach (LUKS + TPM2 unlock with lanzaboote, or LUKS with a
passphrase only) and whether thinkpad's hibernation stays. This is a
reinstall, so it needs the user at the machine and a verified restore
path first.

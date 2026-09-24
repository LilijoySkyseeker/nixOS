---
slug: migrate-torrent-and-thinkpad-to-impermanence
created: 2026-08-18
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# migrate torrent and thinkpad to impermanence

## State

Not started. Predates the `## State` schema; added 2026-09-24 alongside G1
so the file lints.

## Original plan

- [ ] **2026-08-18: migrate torrent and thinkpad to impermanence.**
      Agreed as a prerequisite for eventually shrinking the zfs-backup
      scope of these two hosts (the original zfs-backup item this
      referenced, `myBackupPush`, was superseded by the zrepl migration
      — see `docs/DONE.md`) — both hosts currently
      keep `zroot/local/root` as durable state, impermanence would wipe
      root on boot and move real state to an explicit persist dataset.
      Needs its own disko layout changes + persist-path audit per host,
      and should be VM-tested before real hardware per
      `feedback_test_remote_deploys_in_vm`. Not started directly, but see
      the `worktree-fde-secureboot-plan` branch noted at the top of this
      file — its Phase 2 explicitly folds this migration in as part of a
      larger FDE/Secure Boot/TPM2 plan.

## Progress


## Decisions (D)


## Gotchas (G)

### G1 -- persist `/var/log`, or these hosts come up with a volatile journal

Added 2026-09-24 from the routine flake update
(2026-09-24-routine-flake-update-2026-09-24-and-the-journald-extraconfig-removal.md#G6),
because this is a trap that fires at migration time and is silent when it
does.

journald is pinned to `Storage=persistent`, which writes to
`/var/log/journal`. On an impermanent host where `/var/log` is not in the
persistence list, that directory is gone every boot: the journal restarts
empty, `journalctl` shows only the current boot, and alloy ships nothing
from before the reboot. Nothing errors -- the config is valid and the
service is healthy, there is just no history.

Both hosts already impermanent persist `/var/log` wholesale
(`hosts/vps/configuration.nix:258`, `hosts/homelab/configuration.nix:854`);
torrent and thinkpad must do the same when they migrate.

`docs/hardening.md` states this convention scoped to `security.auditd`
only. Since the alloy rollout it applies to *any* alloy host, which is
all of them -- worth broadening that rule, either here or when the next
host is added.

- [ ] `/var/log` in torrent's persistence list
- [ ] `/var/log` in thinkpad's persistence list
- [ ] verify after first reboot with `journalctl --list-boots` showing
      more than the current boot



## Findings (F)
*(populated by security/docs-updater when invoked)*

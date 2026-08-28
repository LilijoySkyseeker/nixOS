---
slug: migrate-torrent-and-thinkpad-to-impermanence
created: 2026-08-18
status: todo
frozen: false
---

# migrate torrent and thinkpad to impermanence

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


## Findings (F)
*(populated by security/docs-updater when invoked)*

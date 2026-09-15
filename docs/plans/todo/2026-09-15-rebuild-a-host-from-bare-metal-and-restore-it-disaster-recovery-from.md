---
slug: rebuild-a-host-from-bare-metal-and-restore-it-disaster-recovery-from
created: 2026-09-15
status: todo
frozen: false
kind: task
priority: normal
blocked_by:
---

# rebuild a host from bare metal and restore it (disaster recovery from scratch)

## State

**2026-09-15, not started.** Spun out of
`2026-08-25-build-and-test-a-full-restore-suite-scripts-proced.md` by
user decision, so that plan can close on the dataset-level work it has
actually finished instead of staying open on a much larger exercise.
Nothing here has been attempted.

## Original plan

Restoring a *dataset* is solved and exercised: `scripts/restore-drill`
covers file / dataset / stream / rollback / restic, all five paths PASS
against real backup data, and an 873G same-pool restore was
GUID-verified at ~23MB/s (that plan's G7). What is **not** exercised is
losing a whole machine -- the disk dies, the host is stolen, the pool is
unrecoverable -- and rebuilding it from nothing but this repo plus the
offsite backups.

That is a different exercise, and the gap is mostly not the data:

- **Getting to a booting NixOS at all.** `nixos-anywhere` + `disko` is
  the declared path (`docs/procedures/new-host.md`,
  `hosts/<host>/disko.nix`), but a from-scratch rebuild is the case
  where an ISO, network, and a machine that will PXE/boot it are all
  part of the problem.
- **The sops chicken-and-egg.** Secrets are encrypted to per-host age
  keys derived from each host's SSH host key. A host rebuilt from
  scratch has a *new* host key, so it cannot decrypt anything until it
  is added as a recipient and `sops updatekeys` is run -- which requires
  a working machine with the private key already. Ordering this
  correctly is the single most likely thing to go wrong under pressure,
  and `docs/procedures/secrets.md` documents recipient rotation but not
  this ordering.
- **Whether the offsite copy is sufficient on its own.** The restic
  path is proven to restore. Whether restic's contents alone are enough
  to reconstitute a host -- as opposed to being enough to refill a host
  that already exists -- has never been tested.
- **The hybrid rule still applies.** The 2026-09-04 second addendum on
  the parent plan holds here: whatever is built should *be* the real
  recovery procedure, not a test harness imitating one.

Scope note: this is deliberately about one host end to end, not the
whole fleet. `homelab` is the interesting case (it holds the data);
`vps` is the cheap rehearsal, since it is already a disposable droplet
rebuilt by `nixos-anywhere` once before
(`2026-08-25-full-vps-reinstall-via-nixos-anywhere-automated-an.md`) and
losing it costs nothing.

## Progress

- [ ] decide which host is the drill target, and whether it is a real
      rebuild or a VM stand-in (D1)
- [ ] write down the sops recipient-rotation ordering for a host whose
      host key no longer exists
- [ ] rehearse end to end on vps, timing it
- [ ] fold the result into `docs/procedures/backup-restore.md` as real
      procedure, not a second document

## Decisions (D)

### D1 -- real bare-metal rebuild, or a VM stand-in?

Open. A VM stand-in is repeatable and safe but skips exactly the parts
most likely to bite (firmware, disks, network, physical access). A real
rebuild of `vps` is cheap and genuinely from-scratch. Not yet discussed.

## Gotchas (G)
*(none yet)*

## Findings (F)
*(populated by security/docs-updater when invoked)*

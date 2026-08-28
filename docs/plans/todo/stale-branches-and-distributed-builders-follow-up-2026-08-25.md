---
slug: stale-branches-and-distributed-builders-follow-up
created: 2026-08-25
status: todo
frozen: false
---

# Stale branches and distributed-builders follow-up

## Original plan

- [ ] **2026-08-25: two branches with substantial unmerged progress have
      been idle for 5-6 days and aren't reflected anywhere in this file —
      reviewed, not yet touched, needs a decision on whether to revive
      them.** Both diverged from `master` at the same point (merge-base
      `2026-08-18`, `master` now ~179 commits ahead of that point for
      either), so either would need a real rebase, not a fast-forward.
      - **`worktree-distributed-build-todo`** (7 commits, last touched
        2026-08-19): looks feature-complete for the "layer distributed
        builders across the tailnet" item below — `modules/nixos/
        build-worker.nix`/`build-fleet.nix`/`build-submitter.nix` wire
        `nix.distributedBuilds`/`buildMachines` across homelab/thinkpad/
        torrent, per-worker SSH keys added to `secrets/secrets.yaml`,
        config centralized in a later commit. Footprint is small and
        targeted (host configs + 3 new modules + secrets), so a rebase
        is plausible without much conflict, but it predates the zrepl
        migration, the auto-updater rearchitect, and everything else
        that's landed since — needs a real rebase-and-rebuild check, not
        just a fast-forward, before trusting it.
      - **`worktree-fde-secureboot-plan`** (19 commits, last touched
        2026-08-20): a large drafted plan *and* partial implementation
        for FDE + Secure Boot + TPM2 auto-unlock on homelab/thinkpad/
        torrent, phased (Phase 2 explicitly folds in the "migrate
        torrent/thinkpad to impermanence" item below), with per-host
        `RECOVERY.md` runbooks (TPM2-unseal failure, Secure Boot key
        loss, full hardware failure) and a `scripts/reinstall-host.sh`
        orchestrator (temp backup via syncoid → disko-install over the
        recovery ISO → restore → Secure Boot Setup Mode → TPM2 PCR7
        enrollment). Unlike the branch above, this one touches nearly
        every doc and host config in the repo (`TODO.md` alone diffs at
        +1495/-unknown against current `master`) and predates the
        dendritic-pattern restructuring — reviving this is a real
        project (effectively re-deriving the plan against current
        `master`'s architecture), not a quick rebase. Also proposes a
        LUKS-recovery-passphrase escrow scheme flagged as needing the
        user's own sign-off, not an agent decision.
      Neither is locked by another session. Not started on either —
      logged here so the next session (or the user) can decide whether
      to revive, rebase, or abandon them, rather than losing this
      progress silently.


---

**Related, cross-referenced item (originally separate, combined here since
`worktree-distributed-build-todo` above looks like a feature-complete
implementation of this):**

- [ ] **2026-08-18: layer distributed builders across the tailnet**.
      vps's rebuilds are already offloaded off-box — homelab builds and
      pushes vps's closure via `myPushDeploy` (see
      `hosts/homelab/configuration.nix`), vps itself never
      evaluates/builds. This item is the optional
      follow-on, and applies beyond just vps: set
      `nix.distributedBuilds = true` + `nix.buildMachines` (pointing at
      other tailnet hosts, e.g. homelab/thinkpad/torrent as capacity
      allows) so actual compilation — not evaluation, which stays local
      to whichever machine initiates a given host's rebuild — fans out
      across the tailnet instead of always landing on one machine.
      Purely a build-time-distribution optimization, not required for
      any host's correctness. See the stale-branch entry at the top of
      this file — `worktree-distributed-build-todo` looks like a
      feature-complete implementation of this, unreviewed/unmerged.

## Progress


## Decisions (D)

### D1 — revive, rebase, or abandon `worktree-distributed-build-todo`?
Feature-complete for the distributed-builders item, small footprint, but
predates the zrepl migration and auto-updater rearchitect — needs a real
rebase-and-rebuild check before trusting it, not just a fast-forward.

### D2 — revive, rebase, or abandon `worktree-fde-secureboot-plan`?
Large drafted plan + partial implementation for FDE/Secure Boot/TPM2,
predates the dendritic restructuring — reviving is a re-derivation project,
not a quick rebase. Also contains a LUKS-recovery-passphrase escrow scheme
explicitly flagged in the original text as needing the user's own
sign-off, not an agent decision, independent of whether the branch itself
is revived.

## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

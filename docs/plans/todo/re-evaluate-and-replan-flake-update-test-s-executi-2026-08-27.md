---
slug: re-evaluate-and-replan-flake-update-test-s-executi
created: 2026-08-27
status: todo
frozen: false
---

# Re-evaluate and replan flake-update-test's execution model (D11)

## Original plan

- [ ] **2026-08-27: re-evaluate and replan `flake-update-test` (D11) —
      how it should execute, with a benefits/risk analysis.** Deferred
      deliberately rather than answered during the audit; it should not
      be inherited by default.

      **What it does today.** Weekly (`Wed 03:00` on homelab) it runs
      `git reset --hard origin/master`, `nix flake update`, and — if
      `nixos-rebuild build` succeeds — `git merge --ff-only` and
      `git push origin master`. So a green build is the *only* gate on
      writing to `master`, and `master` is unattended fleet root.

      **Why it needs a replan rather than a yes/no.** Commit `3f2c418`
      repaired a mechanism that had never once completed (zero automated
      `flake.lock` commits in 1371). Deploying it makes it live for the
      first time, so there is no track record to judge it on. Points to
      weigh:
      - *Benefit*: upstream input updates get build-tested weekly instead
        of accumulating into one large risky bump.
      - *Risk*: a build-success gate does not test **behaviour**. A
        change that builds and breaks at runtime merges anyway, and the
        next `auto-switch` deploys it fleet-wide unattended.
      - *Risk*: it is an unattended writer to fleet root, which is the
        exact asset `F-P0-01`/H1 is about. Branch protection now blocks
        force-pushes and deletions but not this.
      - *Alternative*: push an `auto-update` branch on success and let a
        human merge — keeps the testing, removes the unattended write.
      - *Alternative*: keep auto-merge but gate on the VM test suite
        (`nix flake check`) rather than a bare build.
      - Note it does an unguarded `git checkout master && git reset
        --hard`, so it will also move `/etc/nixos` off any other branch
        it finds — relevant while a host is deliberately parked on one.

      **Also decide the interaction with `auto-switch`**, which is the
      other half: `flake-update-test` (Wed) writes master and
      `auto-switch` (Thu) deploys it, so the two together are a fully
      unattended upstream-to-production pipeline with no human in it.
      *(D11, F-P7-10, H1)*

## Progress


## Decisions (D)

### D1 -- how should flake-update-test execute: auto-merge on green build, auto-merge gated on the full VM test suite, or propose-a-branch-for-human-merge?
Deferred deliberately during the audit rather than answered -- deploying the F-P7-10 openssh fix makes this live for the first time (it has never once completed in 1371 commits), so there's no track record to judge it on. A build-success gate doesn't test behavior; a change that builds and breaks at runtime merges anyway and auto-switch deploys it fleet-wide unattended. Also decide the interaction with auto-switch together -- the two form a fully unattended upstream-to-production pipeline with no human in it. Sequencing: belongs with the deploy-pipeline project's stage 1/2 design (D11, F-P7-10, H1).

## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

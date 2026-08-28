---
slug: homelab-s-etc-nixos-has-diverged-from-origin-with-
created: 2026-08-27
status: todo
frozen: false
---

# homelab's /etc/nixos has diverged from origin with an unpushed auto-update commit

## Original plan

- [ ] **homelab's `/etc/nixos` has diverged from origin and holds an
      unpushed auto-update commit.** Found 2026-08-27 while checking
      gates for the vps deploy. `git rev-list --left-right --count
      master...origin/master` on homelab returns **1 31** — one
      local-only commit, thirty-one behind:

          1c2eec5 chore: automated flake.lock update

      That commit **exists nowhere else** — not on origin, not on any
      branch in the repo (`git log --all --grep` finds nothing, even
      after a fetch). Working tree is clean.

      **This is `flake-update-test` having actually run.** It bumped
      `flake.lock`, built successfully, merged to local `master` — and
      then failed to `git push`, which is exactly `F-P7-10`: that unit
      had no `openssh` on its `PATH`, so any git operation over SSH
      fails. The commit has sat there ever since.

      Two things follow, both worth recording:

      - **The audit's evidence for `F-P7-10` was right about the remote
        and wrong about the machine.** "Not one `chore: automated
        flake.lock update` commit in the repository's 1371-commit
        history" is still true of the repo; it was not true of
        homelab's checkout. The run happened, it just could not
        publish.
      - **D11 was closer to firing than documented.** The auto-merge
        chain works end to end *except* the push, and this branch adds
        `openssh` to `flake-update-test`'s `path`. On the fixed code
        that push would have succeeded and it would have auto-merged to
        `origin/master` unattended. Worth adding to
        `docs/audits/2026-08-26/D11-analysis.md` when D11 is decided.

      **Also means `auto-switch` was doubly broken.** Even with the
      read-only-git-config fix, `fetch_and_merge_master` runs
      `git merge --ff-only origin/master`, which **fails on a diverged
      branch** — confirmed with `git merge-base --is-ancestor`. So
      homelab's scheduled deploys would have kept failing after the
      guard fix, for a second and unrelated reason.

      **Not urgent, and deliberately not fixed by an agent**: the
      timers are off, so nothing acts on this state. Resolving it means
      either discarding `1c2eec5` (`git reset --hard origin/master`,
      which is what `flake-update-test` itself does on every run) or
      keeping the lock bump deliberately. That is a judgement call on a
      live host's git state, so it is yours.

## Progress


## Decisions (D)

### D1 -- discard homelab's unpushed local commit (1c2eec5), or keep the flake.lock bump it contains?
A live host's git state, explicitly flagged in the original entry as "yours" (the user's) to decide, not an agent's -- resolving it means either `git reset --hard origin/master` on homelab (discarding it, which is what flake-update-test itself does on every run) or deliberately keeping the lock bump.

## Gotchas (G)

### G1 -- F-P7-10's evidence was right about the remote, wrong about the machine
"Not one `chore: automated flake.lock update` commit in the repository's 1371-commit history" is still true of the repo; it was not true of homelab's checkout -- the run happened, flake-update-test just could not publish (no openssh on PATH for the git push over SSH). D11 was closer to firing than documented: the auto-merge chain works end to end except the push.

### G2 -- auto-switch was doubly broken, for an unrelated second reason
Even with the read-only-git-config fix, `fetch_and_merge_master` runs `git merge --ff-only origin/master`, which fails on a diverged branch (confirmed via `git merge-base --is-ancestor`) -- so homelab's scheduled deploys would have kept failing after the guard fix regardless.

## Findings (F)
*(populated by security/docs-updater when invoked)*

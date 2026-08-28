---
slug: rebuild-the-update-build-deploy-pipeline-properly
created: 2026-08-27
status: todo
frozen: false
---

# Rebuild the update/build/deploy pipeline properly

## Original plan

- [ ] **PROJECT: rebuild the update/build/deploy pipeline properly.**
      Scoped 2026-08-27 out of the D11 analysis
      (`docs/audits/2026-08-26/D11-analysis.md`), which found the
      current pipeline is not a small fix away from correct — it is the
      wrong shape. This entry is the design brief. **The goal is to do
      this right, not to do it cheaply**; it is explicitly allowed to be
      slow and to change a lot.

      **Status: auto-updates are DISABLED fleet-wide in the meantime**
      (see the entry below). That is deliberate and temporary — active
      development means the hosts are getting deployed by hand anyway,
      so the scheduled path buys nothing right now while carrying all of
      the risk below. **This project is to be implemented before focused
      development pauses**, because the moment hand-deploys stop is the
      moment the fleet silently goes stale.

      ### 1. The problem

      Today one systemd unit on homelab does all three of: fetch new
      inputs, decide whether they are acceptable, and publish them to
      the branch every host deploys from. Those are three different
      jobs with three different trust levels, and collapsing them is
      what produces every specific defect below.

      Facts, all verified rather than assumed (details and sources in
      `D11-analysis.md`):

      - **The gate covers 1 of 4 hosts.** `flake-update-test` builds
        only `.#homelab`, which is the sole host on `nixpkgs-stable`;
        vps, torrent and thinkpad run `nixpkgs-unstable`. It cannot see
        breakage in the nixpkgs most of the fleet uses.
      - **Two inputs are never built at all.** `stylix` and `nvf` are
        imported only by `profile-pc`, which homelab does not use.
      - **The repo's five VM tests never run.** The gate is
        `nixos-rebuild build`, not `nix flake check`, and there is no CI
        (`.github/` does not exist).
      - **The update runs on a deploy target**, writing to homelab's
        `/etc/nixos`. The machine being tested is the machine doing the
        testing.
      - **It pushes straight to `master`** — unattended fleet root — with
        no PR, no diff, no revert point.
      - **Eleven third-party inputs are tracked at branch HEAD** with no
        cooldown, versus the two nixpkgs channels which are gated
        upstream by Hydra.
      - **Nothing rolls back** a switch that builds fine but leaves a
        host unreachable.
      - **All four hosts deploy at `Thu 03:00`** with no randomisation
        and no reboot window, and homelab — which the laptops
        NFS/Samba-mount — reboots unconditionally on kernel change.

      ### 2. Target architecture — three stages, deliberately separate

      This is the industry-consensus shape, and upstream nixpkgs is the
      proof it works unattended: `nixos-unstable` is **not** `master`;
      it advances only after Hydra's `trunk-combined/tested` job passes.
      Nobody approves a channel bump — a gate that covers everything
      shipped does. Copy that principle, not the scale.

      1. **Propose.** Update `flake.lock` on a schedule, **off the
         deploy targets**, and open a **PR**. Never push to `master`.
      2. **Gate.** Build **every** host configuration, run `nix flake
         check` (all VM tests), publish a per-host `nvd` closure diff on
         the PR. Automerge on green is fine and keeps it unattended —
         the point is coverage and an audit trail, not a human.
      3. **Adopt.** Hosts consume the reviewed lock and **never resolve
         inputs themselves** (`--no-update-lock-file`), so every machine
         converges on the same package set. Staggered, with a reboot
         window, and with automatic rollback.

      ### 3. Where the build farm fits — this is the same project

      The reason this is one project and not two: **stage 2 needs
      somewhere to build all four hosts, and stage 3 needs the results
      to be cheap to fetch.** That is exactly what the stale
      `worktree-distributed-build-todo` and `worktree-nix-cache`
      branches were reaching for.

      The general directions worth keeping from them:

      - **homelab serves a binary cache** (harmonia was the vehicle) so
        the laptops and vps fetch closures instead of rebuilding them.
        vps especially — it has ~2 GB RAM and a from-scratch build was
        measured at ~1.7 GB + swap, which is why it stopped building
        for itself.
      - **Distributed builds across the fleet**, with homelab as the
        primary builder.
      - **homelab pre-builds the other hosts' closures** to warm the
        cache before they deploy — which, done in the new shape, *is*
        stage 2's gate. Building all four hosts stops being an
        expensive addition and becomes the thing that makes stage 3
        fast.
      - **Stagger the fleet's scheduled jobs across the week** rather
        than firing them together.

      **Treat those branches' actual implementations as suspect.** They
      predate this audit, were written with less knowledge, and will be
      redone — take the direction, re-derive the code. Specifically
      re-check: the cache signing-key model, the builder SSH key model
      (per-worker vs per-edge), and anything touching host-key
      verification, since `push-deploy`'s TOFU gap is a known open
      issue.

      ### 4. Design questions to settle before writing code

      - **Where does the gate run?** GitHub Actions is free for a public
        repo but has no fleet cache and slow cold builds. homelab has
        the CPU and the store but is a deploy target. A hybrid —
        homelab builds and *proposes*, CI verifies — may be right.
        Decide deliberately; this is the crux.
      - **Does `master` stay the deploy branch**, or do hosts track a
        separate `deployed`/`release` ref that only advances when the
        gate passes? The latter decouples "I pushed work" from "the
        fleet takes it", which matters given active hand-deploys.
      - **Cooldown or pinning for the eleven third-party inputs?**
        Renovate's `minimumReleaseAge` is the ecosystem answer; pinning
        to tags is the manual equivalent. This is the *only* lever that
        touches supply-chain risk — no build gate addresses it.
      - **Rollback mechanism.** `deploy-rs`-style magic rollback
        (canary + confirm-or-revert on the target) is the reference.
        Adopting deploy-rs wholesale vs borrowing the confirm-or-revert
        timer into the existing push/pull modules.
      - **Signature verification** — D2 and `F-P0-01` option (b). If the
        fleet auto-adopts a ref, verifying who signed it is the control
        that makes that safe. Settle alongside, not after.
      - **Does `vps` move to `nixpkgs-stable` first?** (own entry
        below). It shrinks the gate's surface and makes stage 2 cheaper.

      ### 5. Definition of done

      - No host resolves flake inputs by itself.
      - Nothing reaches a deploy target that has not had **its own**
        configuration built and the VM tests run.
      - A bad deploy reverts without a human.
      - Every fleet-wide change has a diff and a revert point.
      - Losing any single host does not stop the others updating.
      - `docs/architecture.md` and `docs/procedures/workflow.md`
        describe the new shape, and the old auto-update entries in this
        file are moved to `docs/DONE.md`.

      ### 6. Related entries

      The two smaller items below (simultaneous deploys, no automatic
      rollback) are subsumed by this project — keep them for now as the
      concrete symptoms, and close them out with it. `vps` →
      `nixpkgs-stable` is a useful prerequisite. `F-P7-09`'s
      profile-staleness check (done 2026-08-27) is the safety net that
      makes disabling the timers survivable: if the fleet stops
      deploying, `myHealthAlerts` now says so within three weeks.

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

- [ ] **The whole fleet deploys at once, with no randomisation and no
      reboot window.** Surfaced 2026-08-27 while researching D11.
      `auto-switch` (homelab), `pull-deploy` (torrent, thinkpad) and
      `push-deploy-vps` all fire at **`Thu 03:00`**-ish, and homelab
      reboots unconditionally on a kernel change
      (`reboot-if-kernel-changed`) with no window.

      homelab is the NFS/Samba server the laptops mount, so the
      worst case is homelab rebooting into a broken generation at the
      same moment both laptops are mid-deploy against it.

      Upstream's `system.autoUpgrade` has `randomizedDelaySec`,
      `fixedRandomDelay`, `rebootWindow` and `persistent` for exactly
      this (verified in the pinned nixpkgs,
      `nixos/modules/tasks/auto-upgrade.nix`). This repo replaced that
      module with `modules/nixos/auto-update.nix` and **dropped all of
      them**. Cheap fix: stagger the `OnCalendar` values and add a
      reboot window. See `docs/audits/2026-08-26/D11-analysis.md` §7.

- [ ] **Adopt a real deployment tool — `deploy-rs` or equivalent — so a
      bad change rolls itself back.** Raised from the D11 research and
      sharpened by the 2026-08-27 deploys, which made the gap concrete
      rather than theoretical.

      **The problem.** `nixos-rebuild switch --target-host` has no
      safety net. A change that *builds perfectly* but leaves the host
      unreachable — a bad firewall rule, a broken sshd, a network
      change — is unrecoverable except by hand, and on **vps** that
      means the provider's console. Nothing detects it, nothing
      reverts it, and the deploying side cannot tell "activated fine"
      from "activated and fell off the network", because both look like
      a closed SSH connection.

      **This is not hypothetical here.** vps was deployed on
      2026-08-27 with changes that rewrote the raw-table firewall
      chains on a public-facing remote host, including a *new* IPv6
      PREROUTING chain. It went fine — but the only reason anyone knows
      that is a human ran ~8 verification commands afterwards
      (ipsets present, both `vps-ratelimit` chains correct, DNAT right,
      CrowdSec allowlist intact, site serving over v4 **and** v6).
      Had it not gone fine, the recovery path was a console login.
      A deploy where correctness depends on someone remembering to
      check is not a deploy process.

      **What the tooling buys, in priority order:**

      1. **Confirm-or-revert (the actual point).** `deploy-rs`'s "magic
         rollback": after activation it writes a canary and reconnects
         to confirm the host is still reachable; if confirmation never
         arrives, *the target* rolls itself back on a timer. This is
         the one feature that makes remote deploys safe, and it must
         run on the target, since the deployer may be exactly what got
         cut off.
      2. **Health checks as a gate**, not as a human checklist — the
         verification above expressed as code that runs every time.
      3. **Multi-host orchestration** with per-host success/failure,
         replacing the current split of `myPushDeploy` (vps) and
         `myPullDeploy` (laptops) and their duplicated guard logic.
      4. **A real dry-run/diff step** before activation.

      **Evaluate, do not assume `deploy-rs`.** It is the best-known
      option for magic rollback, but `colmena` is the other serious
      contender (better multi-host ergonomics, no equivalent rollback
      last time this was checked — verify rather than trust that).
      Weigh adopting a tool wholesale against borrowing just the
      confirm-or-revert timer into the existing modules: this repo's
      push/pull modules already carry real logic (the deploy guards,
      the arithmetic-injection fix, `onDeployUnits`) that should not be
      thrown away casually.

      **Sequencing.** This belongs to stage 3 ("adopt") of the pipeline
      project above and should be decided with it, not separately —
      the same decision about where deploys are driven from determines
      what tool makes sense. **Highest value on `vps`**: remote,
      public-facing, push-deployed, and the only host where a mistake
      costs a console session rather than a walk to the machine.

      References: [deploy-rs](https://github.com/serokell/deploy-rs),
      [Serokell's write-up](https://serokell.io/blog/deploy-rs),
      [colmena](https://colmena.cli.rs/), and
      `docs/audits/2026-08-26/D11-analysis.md` §7.

- [ ] **Move `vps` from `nixpkgs-unstable` to `nixpkgs-stable`.** Raised
      2026-08-27 while writing the D11 analysis, which surfaced the
      split: `modules/flake/hosts.nix` builds **homelab** from
      `nixpkgs-stable` (nixos-26.05) with `home-manager-stable`, but
      **vps**, **torrent** and **thinkpad** from `nixpkgs-unstable`.

      vps is the other *server*, and the only host with a public
      interface — it should track the same conservative branch homelab
      does, not the fast-moving one. Today it takes unstable's churn on
      the box running Caddy, CrowdSec and the wireguard endpoint, and it
      is deployed unattended (homelab builds its closure and pushes it).

      Two reasons this is more than tidiness:

      - **It shrinks D11's blast radius directly.** The auto-merge gate
        builds only homelab, i.e. only `nixpkgs-stable`. Moving vps to
        stable means two of the four hosts are covered by the input the
        gate actually tests, instead of one.
      - vps has ~2GB RAM and builds nothing itself; a stable branch
        means fewer, smaller rebuilds pushed to it.

      Not a one-liner: check what on vps needs unstable (`copyparty` is
      isoimage-only, so probably nothing), whether the stable branch has
      the CrowdSec/Caddy versions in use, and swap `home-manager` for
      `home-manager-stable` in its `specialArgs` the way homelab does to
      avoid a version mismatch. Build-verify before deploying, and diff
      the closure with `nvd` — this changes essentially every package on
      the host. See `docs/audits/2026-08-26/D11-analysis.md` §2.

      **Write the rule down as part of this.** The intended convention
      is **servers track `nixpkgs-stable`, PCs track
      `nixpkgs-unstable`** — servers want boring and predictable, and
      the desktops are where new packages are actually wanted. That
      rule currently exists nowhere: it has to be inferred from
      `modules/flake/hosts.nix`, and inferring it from today's code
      gives the *wrong* answer, because vps contradicts it. That is
      probably how vps drifted in the first place, and it is exactly
      the "durable convention living only in someone's head" case
      `docs/procedures/updating-documentation.md` exists for.

      **The rule is now written** — `docs/architecture.md`, "Which
      nixpkgs a host tracks", with vps named as a known deviation
      pointing back here. Done ahead of the move itself, deliberately:
      the undocumented convention is the part that keeps costing, and a
      rule with a named exception beats no rule. What remains here is
      the actual move, after which that deviation note comes out.

## Progress

- [ ] Settle the five design questions (D1-D5) before writing any code.
- [ ] Stage 1 (Propose): update flake.lock on a schedule, off the deploy targets, open a PR, never push to master.
- [ ] Stage 2 (Gate): build every host configuration, run nix flake check (all VM tests), publish a per-host nvd closure diff on the PR.
- [ ] Stage 3 (Adopt): hosts consume the reviewed lock, never resolve inputs themselves; staggered, with a reboot window and automatic rollback.
- [ ] Move vps from nixpkgs-unstable to nixpkgs-stable (prerequisite -- shrinks the gate's surface, two of four hosts covered by the tested input instead of one). The convention ("servers track nixpkgs-stable, PCs track nixpkgs-unstable") is already written in docs/architecture.md's "Which nixpkgs a host tracks", with vps named as the known deviation -- what remains is the actual move.
- [ ] Stagger the fleet's scheduled jobs across the week; add a reboot window to homelab's unconditional-reboot-on-kernel-change behavior (cheap fix, doesn't need to wait on the rest of the project).
- [ ] Evaluate deploy-rs vs. colmena vs. borrowing just the confirm-or-revert timer (see D4).

## Decisions (D)

### D1 -- where does the gate run (homelab hybrid, CI, or both)?
GitHub Actions is free for a public repo but has no fleet cache and slow cold builds; homelab has the CPU/store but is itself a deploy target. A hybrid (homelab builds and proposes, CI verifies) may be right -- flagged in the original entry as "the crux."

### D2 -- does `master` stay the deploy branch, or do hosts track a separate `deployed`/`release` ref?
The latter decouples "I pushed work" from "the fleet takes it," which matters given active hand-deploys.

### D3 -- cooldown or pinning for the eleven third-party inputs tracked at branch HEAD?
Renovate's `minimumReleaseAge` is the ecosystem answer; pinning to tags is the manual equivalent -- the only lever that touches supply-chain risk, since no build gate addresses it.

### D4 -- rollback mechanism: adopt deploy-rs wholesale, or borrow just the confirm-or-revert timer into the existing push/pull modules?
This repo's push/pull modules already carry real logic (deploy guards, the arithmetic-injection fix, `onDeployUnits`) that a wholesale tool swap would discard. Evaluate deploy-rs vs. colmena rather than assuming -- colmena has better multi-host ergonomics but no equivalent rollback last checked (verify, don't trust).

### D5 -- signature verification for an auto-adopted ref (D2 and F-P0-01 option (b))?
If the fleet auto-adopts a ref, verifying who signed it is the control that makes that safe -- settle alongside D2, not after.

## Gotchas (G)

### G1 -- one already-live consequence: homelab's /etc/nixos diverged with an unpushed auto-update commit
Tracked as its own plan (2026-08-27-homelab-s-etc-nixos-has-diverged-from-origin-with-.md) since it's a live-host state question needing the user's own judgement call, not blocked on this redesign.

## Findings (F)
*(populated by security/docs-updater when invoked)*

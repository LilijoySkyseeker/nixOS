# TODO / plans & goals

Running log of plans and goals discussed for this repo, so they can be
referenced across sessions. Not a replacement for host-specific docs
(e.g. `hosts/*/README.md`) — this is for higher-level, cross-host
or longer-horizon items.

Convention: add a dated entry when a new plan/goal is agreed on; once it
lands, move the entry to [`docs/DONE.md`](docs/DONE.md) (append a dated
"landed" note rather than editing the original text away) instead of
checking it off in place; prune stale/abandoned items rather than letting
them rot.

## Active


- [ ] **2026-08-27: restructure ZFS so ordinary temp/cache data in
      ordinary locations is not snapshotted or replicated.** Today the
      laptops snapshot `/tmp`, `/var/tmp` and `~/.cache` every 5 minutes
      and ship them to homelab, because those paths sit inside datasets
      that are snapshotted wholesale. That is what forced the awkward
      "generate keys in `/dev/shm`" workaround in the credential rotation
      runbook, and it is the mechanism behind `F-P7-02`.

      **The constraint that decides the shape of the fix: ZFS snapshots
      whole datasets.** There is no exclude list. You cannot keep
      `~/.cache` out of a `zroot/local/home` snapshot by configuring
      zrepl — the only way to exclude a path is to make it *its own
      dataset* and leave that dataset out of the snapshot set. So this is
      genuinely a restructure (disko layout + zrepl dataset lists), not a
      settings change.

      **homelab already has the right shape; the laptops do not.**
      Measured live 2026-08-27:

      | host | `/tmp` lives on | snapshots on it | replicated? |
      |---|---|---|---|
      | homelab | `zroot/local/root` | **1** — `@blank` only | no |
      | torrent | `zroot/local/root` | **61** zrepl snapshots | yes → `zbackup` |
      | thinkpad | `zroot/local/root` | same shape | yes → `zbackup` |

      homelab gets this for free from impermanence: its root is rolled
      back to `@blank` on boot and only `zroot/local/state` +
      `zdata/storage/*` are in `myZrepl.local.datasets`. The laptops
      serve `zroot/local/root` and `zroot/local/home` whole
      (`hosts/torrent/configuration.nix:92-95`), so everything transient
      on them is versioned and replicated. The goal is to give the
      laptops the property homelab already has, by whichever route suits
      them — they are daily drivers, so wipe-on-boot is not obviously the
      right answer for them the way it is for a server.

      **Two separate costs, worth keeping distinct:**

      - *Security.* A secret written to a normal temp location becomes
        unretractable. `F-P7-02` is the live proof: the **live** zrepl
        puller private key (`vars.zreplPullerKey`'s private half, mode
        0600, dated 2026-08-23) is still at `/tmp/homelab_zrepl_key` on
        torrent, and confirmed present inside
        `/.zfs/snapshot/zrepl_20260827_231641_000/tmp/` — one of 61
        snapshots, plus homelab's replica. Deleting the file retracts
        nothing. This is also why rotation item 9 cannot be closed by
        tidying.
      - *Volume.* On torrent, `~/.cache` is **22 GB** of regenerable
        churn being snapshotted hourly and replicated (7.5G spotify,
        3.6G appimage-run, 2.3G nix, 1.1G chromium…), plus 791M of
        `~/.local/share/Trash` and 162M in `/tmp`. `~/Downloads` is
        **957 GB** and is also where `iso-autobuild` drops built ISOs —
        rebuildable artefacts in an hourly-snapshotted, replicated
        dataset. torrent's replica on homelab is 3.16T.

      **Direction, decided 2026-08-27:**

      - **All hosts get impermanence.** homelab is the model, not the
        exception — the laptops should get the same wipe-on-boot root.
        That settles the `/tmp` and `/var/tmp` half of this entry
        structurally: a root that rolls back to `@blank` every boot
        cannot accumulate temp data for a snapshot to capture, which is
        exactly why homelab's `zroot/local/root` carries one snapshot
        and torrent's carries 61. It also folds in the thinkpad
        impermanence scaffolding already flagged as inert (`F-P5-14`:
        `environment.persistence` evaluates to `{}` and there is no
        `zfs rollback …@blank` in its initrd, so `/` is durable today and
        `@blank` is decorative) — that becomes real work rather than a
        comment.
      - **`boot.tmp.useTmpfs = true` — agreed, worth doing.** No
        `boot.tmp.*` is set anywhere in this repo today, so `/tmp` is
        on-disk and never cleaned on all four hosts. This is the cheapest
        single improvement and is worth landing *ahead of* the
        impermanence work rather than waiting for it: it is one option,
        it needs no disko changes, and it makes `/dev/shm`-style hygiene
        the default instead of something to remember at exactly the
        moment you are handling a private key. Watch the memory cost on
        hosts that build large derivations in `/tmp`.

      **Impermanence does not finish the job — be clear about what is
      left.** It fixes `/`, and therefore `/tmp` and `/var/tmp`. It does
      **not** touch `/home`, which is persisted by design and is where
      the volume actually is: `~/.cache` at 22 GB and `~/Downloads` at
      957 GB, both inside the hourly-snapshotted, replicated
      `zroot/local/home`. Those still need the dataset split, because of
      the whole-dataset constraint above. So the plan is two independent
      pieces, and landing impermanence should not be read as closing this
      entry.

      **Still undecided:**

      - Split `~/.cache` and `~/.local/share/Trash` into their own
        datasets, excluded from `serve.datasets`. Low controversy —
        both are regenerable by definition.
      - `~/Downloads` is a judgement call. 957 GB of it is not obviously
        disposable, and "not backed up" is a promise to the user as much
        as a storage decision. Splitting the `iso-autobuild` output
        directory out of it may be the narrower, better move.
      - Whether `zroot/local/root` needs replicating on a laptop at all
        once it is impermanent, given `/nix` is excluded already and the
        config is in this repo.

      **Do not treat this as a prerequisite for rotation item 9.**
      Rotating the zrepl key is what retracts it; this entry stops the
      *next* one happening.

- [ ] **2026-08-27: decide what to do with the 9 branches left after the
      merged-worktree prune — 6 of them exist only on this machine and
      are one `rm -rf` away from being lost.** A cleanup pass removed 34
      merged worktrees (+ their local branches) and 18 merged remote
      branches; everything below was deliberately kept because it holds
      commits not in `master`. Counts are commits ahead of
      `origin/master` as of 2026-08-27.
      - **Local-only — never pushed, no remote copy anywhere.** This is
        the risk: pruning one of these worktrees, or losing the disk,
        loses the work outright. Worth pushing them to `origin` purely
        as a backup even if nobody intends to revive them soon.
        `worktree-nix-cache` (10 commits, last 2026-08-19),
        `worktree-distributed-build-todo` (7, 2026-08-19),
        `worktree-crowdsec-bouncer-fix` (3, 2026-08-25),
        `worktree-crowdsec-bouncer-docs` (2, 2026-08-25),
        `worktree-statusline-spacing-effort` (2, 2026-08-25),
        `worktree-sops-reorg` (1, 2026-08-20).
      - **Remote-only — no local worktree.** Their local worktrees were
        pruned as merged, which was correct for the *local* branch tip,
        but the remote tip carries extra commits that never landed. Easy
        to forget precisely because nothing on disk points at them:
        `worktree-vps-exit-node` (3 commits, last 2026-08-19),
        `worktree-auto-updater-rearchitect` (1, 2026-08-25),
        `worktree-jellyfin-gpu-accel` (1, 2026-08-18 — remote-only for
        longer than the others, no local worktree at any point in this
        pass).
      - Both `worktree-distributed-build-todo` and
        `worktree-fde-secureboot-plan` already have a fuller
        content-level review in the 2026-08-25 entry below; this entry
        is about the *inventory* (what exists where, and what is
        unbacked), not a re-review of those two.
      Not started — logged so the next session can decide push-as-backup
      vs. rebase vs. abandon per branch, rather than discovering a gap
      after something is already gone.

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

- [x] **homelab's `/etc/nixos` has diverged from origin and holds an
      unpushed auto-update commit.** — resolved 2026-08-27, see below. Found 2026-08-27 while checking
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

      **RESOLVED 2026-08-27, on the user's decision.** Surfaced again
      while preparing rotation item 8, whose verification step is
      `systemctl start push-deploy-vps` on homelab — and
      `myPushDeploy.flakeDir` is `/etc/nixos`. Running it in that state
      would have built `.#vps` from a pre-audit tree still containing
      `publicKey = "GH5vw+bR1d28…"` and pushed it to vps, taking back the
      old WireGuard key, breaking the tunnel a second time, and reverting
      the config vps is actually running. The rotation would have looked
      like it failed for reasons unrelated to the key.

      The user chose to discard the commit. `/etc/nixos` is now checked
      out on `worktree-worktree-security-audit-plan` at `eb8ce08` with a
      clean tree, local `master` reset to `origin/master` (`9f39873`),
      and `1c2eec5` abandoned. Verified afterwards that the checkout
      carries both the rotated peer key and the `restartUnits` fix.

      **Two consequences to keep in mind while the branch is deployed:**
      `push-deploy-vps` and `auto-switch-now` both build from
      `/etc/nixos`, so they now deploy the *audit branch*, not master.
      That is what we want during this work and wrong afterwards — put
      `/etc/nixos` back on `master` once the branch lands. All the
      relevant timers are off, so only a manual `systemctl start` acts on
      this.

- [ ] **Nothing ever verifies that the alert sink actually works.**
      Found 2026-08-27 while rotating `discord_webhook`: the new value
      was pasted as a bare URL, but `myHealthAlerts` calls
      `curl -sS -K <file>`, and `-K` is *config-file* mode — it needs
      `url = "https://…"`. A bare URL makes curl fail with
      `config file option 'https' is unknown`, exit 2.

      **The failure is completely silent in normal operation**, which is
      the actual finding. `notify` only runs when something is already
      wrong, its curl output goes to `/dev/null`, and its exit status is
      discarded — so a broken sink is invisible until the moment you
      need it, and then it fails at exactly the wrong time. It was
      caught only because the rotation runbook has an explicit
      "send a real message and confirm it arrives" step.

      Worth fixing in at least one of these ways:

      - **Check curl's exit status in `notify`** and log loudly on
        failure. Cheapest, and turns a silent failure into a journal
        line the failed-units check can eventually see.
      - **A periodic heartbeat/canary post** — the only thing that
        proves the whole path works end to end, including the URL still
        being valid at Discord's side. Would also catch a webhook
        deleted at the provider, which nothing detects today.
      - **Validate the file shape at build time** (an assertion that the
        secret is a curl config, not a bare URL) — cannot be done from
        the encrypted value, but the *rendered* template could be
        checked, and the option description could be much louder.

      Related: this is the same class as `F-P7-09` — a control that
      reports nothing when it is broken — but one level further out. The
      audit made deploy *failures* visible; nothing makes the reporting
      channel itself visible.

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

- [ ] **2026-08-26: fleet-wide security hardening audit + "is this
      still needed?" config review, run as a multi-agent pass.**
      Originally scoped to homelab only (see trigger below); widened
      2026-08-26 to cover **every host and every shared module in this
      repo**, on two axes at once:
      1. **Hardening.** Conformance to `docs/hardening.md`'s standing
         rules (dedicated service users, systemd sandboxing, SSH
         lockdown, no-sudo/run0, swap/secrets, forwarded-port rate
         limiting), *plus* general security review beyond what that
         doc already codifies — anything an auditor would flag that
         we simply never wrote a rule for.
      2. **Needed/used.** Whether each option, service, package,
         firewall hole, group membership, and secret is still
         actually used and still actually justified. Dead config is a
         security finding here, not just tidiness: an unused
         `openFirewall`, a group nobody needs, or a service kept
         "just in case" is attack surface with no owner.

      **Why multi-agent.** ~6.9k lines of Nix across 5 hosts + shared
      modules + flake infra, and a careful audit needs the pinned
      nixpkgs source checked per option rather than recalled. That
      does not fit one agent's context at the depth this deserves, so
      the config is split into the parts below and a security-audit
      subagent is dispatched per part, each producing a report to a
      fixed schema, followed by a consolidation pass.

      **Trigger (original homelab scope, still in force).** homelab's
      LAN NIC turned out to already carry a real, globally-routable
      public IPv6 address (ISP RA-delegated), which quietly changes
      the risk model for every host-wide (non-interface-scoped)
      firewall rule on that box — a class of gap that was invisible
      under IPv4-only CGNAT. sshd/jellyfin/minecraft/factorio's
      host-wide exposure is already fixed, deployed, and
      reboot-verified (`f93ca49`, `deaf882`, `9134a47`, `0a774e5` —
      see `docs/DONE.md`). The question this audit answers is what
      *else*, on any host, assumes "this box has no real public
      address" the way sshd/jellyfin did.

      ### Phase 0 — threat model (do first, single agent)
      Write `docs/audits/2026-08-26/00-threat-model.md`: the actual
      adversaries and trust boundaries, so all eight audits rate
      severity on the same scale instead of each inventing one. At
      minimum: the public internet vs. `vps` (only host with a real
      public IPv4 + listeners); the public internet vs. `homelab`'s
      RA-delegated IPv6 on the LAN NIC; anything already on the LAN;
      a tailnet-authorized device (today the *only* gate on most
      services — is device authorization alone sufficient?); a
      roaming laptop on an untrusted network (`thinkpad`, `torrent`,
      whose own IPv6/NAT posture is unpredictable in a way a known
      home ISP's is not); a compromised backup *source* host (zrepl's
      pull direction was chosen for exactly this); supply chain via
      the auto-update/deploy path; and local unprivileged-user → root
      on the workstations.

      ### Phase 1 — parallel audits (one subagent per part)
      Each part is coherent enough to audit without the others.
      Cross-cutting concerns are assigned to exactly one owner to
      keep findings from being reported eight times.

      - **P1 — shared baseline & profiles.**
        `modules/profiles/{default,server,PC}.nix` (~635 lines).
        Highest blast radius: every host inherits this. Owns
        `networking.firewall.enable`, run0/sudo-alias,
        `nix.settings.allowed-users`, auditd, and every
        desktop-profile grant. Already-spotted seeds: `PC.nix:306`
        `initialPassword = "123456"` on the login user; `PC.nix:289`
        `services.avahi.openFirewall = true` (host-wide mDNS on
        roaming laptops); `PC.nix:313` `docker` group on `lilijoy`
        (docker socket membership is root-equivalent — check whether
        the podman/`dockerCompat` setup at `PC.nix:113` makes it
        unnecessary); `PC.nix:320` Steam `remotePlay.openFirewall`
        host-wide (folded in from the original entry — and audit
        whether roaming makes it *worse* than the fixed-server case,
        not better).
      - **P2 — `vps`, the internet-facing edge.**
        `hosts/vps/{configuration,disko,hardware-configuration}.nix`
        (~827 lines). The only host with real public listeners:
        caddy, anubis, crowdsec + firewall bouncer, fail2ban,
        wireguard `wg0`, `networking.nat` game-server forwarding and
        the `firewall.extraCommands` rate limiting that backstops it,
        cloud-init, GRUB, impermanence. Also owns the `vps-deploy`
        identity: polkit rule, `nix.settings.trusted-users`, and the
        `vpsDeployDispatcher` shell script — audit that dispatcher as
        *hostile input handling*, since it is what a compromised
        homelab would reach.
      - **P3 — `homelab`, host config.**
        `hosts/homelab/{configuration,disko,hardware-configuration}.nix`
        (~742 lines). restic → Backblaze, docker daemon settings,
        nvidia/GPU, `systemd.tmpfiles` permissions,
        networkd-dispatcher, `boot.zfs.extraPools`, the impermanence
        persist list, sshd. Folded in from the original entry:
        `bootctl` warns every boot that `/boot`'s mount point and its
        `loader/random-seed` file are world-accessible ("which is a
        security hole"), surfaced in the 2026-08-26 reboot journal.
      - **P4 — services: containers & network shares.**
        `modules/services/{minecraft,factorio,jellyfin,samba,nfs,
        copyparty-iso}.nix` (~625 lines). Container capability sets,
        read-only rootfs, port exposure, share ACLs and auth
        identities. `minecraft.nix`/`factorio.nix` were done
        carefully and are the reference standard — confirm the rest
        got the same treatment. Seed: `copyparty-iso.nix:43` opens
        3923 host-wide while `:34-37` serves `/` with `A = [ "*" ]`
        (admin, unauthenticated) — probably deliberate for a recovery
        ISO, but it needs an explicit written justification rather
        than an implicit one.
      - **P5 — workstations: `thinkpad` + `torrent`.**
        `hosts/thinkpad/*` and `hosts/torrent/*` (~550 lines).
        Roaming/untrusted-network threat model, interaction with the
        P1 desktop profile, `PermitRootLogin forced-commands-only`,
        torrent's own exposure, nvidia.
      - **P6 — backup & replication.**
        `modules/nixos/{zrepl,zfs-space-guard,nfs-homelab-mounts}.nix`
        (~1232 lines) plus homelab's restic jobs by reference. The
        largest single module and a root-run daemon: audit the
        `authorized_keys` forced-command boundary, the
        server-side-fixed identity, the pull-not-push trust
        direction, `zfs allow` delegations, and what a compromised
        peer can actually reach.
      - **P7 — deploy, update & control plane.**
        `modules/nixos/{auto-update,pull-deploy,push-deploy,
        iso-autobuild,health-alerts}.nix` (~899 lines),
        `modules/flake/deploy-guards.nix`, `scripts/bootstrap-host.sh`.
        This is the "what can cause code to run as root across the
        fleet" surface — arguably the highest-value target after P2.
        Audit authn/authz on every trigger path, what is signed or
        verified vs. merely reachable, and the blast radius of a
        compromised trigger.
      - **P8 — supply chain, flake infra, secrets plumbing, user env.**
        `flake.nix`, `modules/flake/*`, `modules/home-manager/*`
        (incl. `claude-code.nix`), `modules/nixos/{tooling,kde,
        virtual-machines,wooting}.nix`, `tests/*`, `files/`. Input
        pinning and `flake.lock` provenance, substituters/trusted
        public keys, `nix.settings` across hosts, udev rules, and the
        **sops wiring** — `secrets/.sops.yaml` key/recipient policy
        and per-host `sops.secrets` declarations, ownership and mode.
        Strictly the plumbing: per `docs/procedures/secrets.md`, no
        agent decrypts or edits `secrets/*`, ever.

      ### Contract every audit subagent follows
      - **Read-only.** No edits, no rebuilds against live hosts, no
        `switch`, no secret decryption. Findings only.
      - **Verify against the pinned nixpkgs**, not recall — what a
        module option actually does in *this* flake's nixpkgs, since
        defaults differ by version and that is exactly where a
        hardening assumption silently fails.
      - **Apply the Phase 0 threat model** for severity, and state
        explicitly *who* reaches the issue and *from where*.
      - **Cover both axes** — a part's report must address
        needed/used, not just hardening.
      - **Separate CONFIRMED from PLAUSIBLE**: say which lines were
        actually read and which claims are inference.
      - **Fixed output schema** per finding: id, `file:line`,
        severity, reachability/threat path, confidence, whether it
        violates an existing `docs/hardening.md` rule or is a
        *candidate for a new one*, proposed fix, and the risk/blast
        radius of applying that fix.
      - Report to `docs/audits/2026-08-26/P<n>-<part>.md`.

      ### Phase 2 — consolidation
      Dedupe across the eight reports, reconcile severity, and write
      `docs/audits/2026-08-26/findings.md`: one ranked list, with
      fleet-wide/systemic findings (a whole class of mistake repeated
      across hosts) called out separately from one-off ones — those
      are the ones that become new baseline rules.

      ### Phase 3 — remediation, in waves
      Sequenced, not one giant branch. Shared-baseline changes (P1)
      land first since they move every host at once and need the most
      testing; per-host changes follow. Every wave goes through the
      repo's own gates — `nixos-rebuild build --flake .#<host>` for
      each affected host, a VM test where behaviour (not just config)
      changes, and no `switch` without being asked. Anything
      requiring the user's own sign-off (accepting a risk, moving a
      trust boundary) is surfaced as a decision, not decided by an
      agent.

      ### Phase 4 — documentation harvest
      The audit's real output is not just fixes but *knowledge*, and
      it goes back into the docs rather than dying in a report:
      - New standing rules and newly-understood gotchas → the
        relevant `docs/` file, primarily `docs/hardening.md`, which
        is already the codified baseline and so is where "we now
        always do X" belongs.
      - The written threat model → kept as a durable doc, since every
        future service decision needs it.
      - `docs/audits/` is a new directory: add a row for it to
        `AGENTS.md`'s "Where things live" table, per
        `docs/procedures/updating-documentation.md`.
      - Accepted-risk items (audited and deliberately *not* fixed)
        get written down with their justification, so a future pass
        does not re-litigate them from scratch.
      - Plus whatever the user directs into `TODO.md` as follow-up:
        remediation that is deferred rather than done stays tracked
        here, not in a report file nobody reads.

      **Phase 4 landed 2026-08-27.** All four parts done:
      `docs/hardening.md` gained a **Standing rules** section with the
      ten rules from `findings.md` §4 (the eleventh,
      `AllowTcpForwarding`, was already applied in wave 2), including a
      new OCI-container rule the doc had no equivalent of;
      `docs/threat-model.md` is a new stable pointer at the model;
      `docs/accepted-risks.md` is new; `AGENTS.md` gained rows for both.
      Also corrected `docs/procedures/remote-access.md`, which asserted
      the `vps-deploy` forced-command allowlist was "the actual security
      boundary" when root arrives anyway via the polkit grant beside it,
      and updated the audit skill's own Phase 4 guidance so the next run
      inherits the layout rather than re-deciding it.

      **Three judgement calls were decided by the agent, not the user**,
      because Phase 4 is documentation-only and every one of them is
      cheap to reverse. Flagged here so they can be overruled:
      1. *How much reasoning goes inline.* Rules are short and
         imperative; the `file:line` evidence stays in the audit and is
         linked. `docs/hardening.md` went 138 → ~264 lines rather than
         doubling on justification.
      2. *Where the threat model lives.* It stays in
         `docs/audits/2026-08-26/` — the eight part reports cite it by
         section and a copy would drift — with `docs/threat-model.md` as
         a stable path to link instead, carrying a supersession rule.
      3. *Accepted risks could only be scaffolded.* §1 holds the six
         risks whose acceptance is genuinely not in question (public
         repo, homelab→vps root, zrepl-as-root, the two unlocked shell
         paths, no-CI-on-purpose, NFS without `noexec`). §2 lists
         D1–D14 as **explicitly not accepted** — the risk each one would
         be accepting if answered that way. It cannot be finished until
         those are decided.

      **Progress.** Phase 0 done 2026-08-26:
      `docs/audits/2026-08-26/00-threat-model.md` — exposure map,
      principals, six trust-boundary analyses, nine adversaries, the
      severity rubric P1–P8 must apply, six recurring failure modes to
      probe for, and seven open questions. Every claim in it is cited
      by `file:line` and the citations were verified against source.
      P0's own cross-cutting findings are recorded in the standard
      finding schema at `docs/audits/2026-08-26/P0-findings.md`
      (F-P0-01..07) so Phase 2 consolidates them rather than losing
      them in prose; that file is also the format reference P1-P8
      write against. Phase 1 dispatched 2026-08-26: eight audit
      subagents running against the parts below.
      Two things it turned up that reframe the audit before it starts:
      `origin/master` on GitHub is an unsigned, unattended root
      credential for all four real hosts (§4.1), and there is no
      meaningful security boundary between homelab and vps — the
      vps-deploy ForceCommand allowlist bounds shells and accidents,
      not root (§4.2).

      **Status as of 2026-08-27.** Phases 0–2 done: 158 findings, **3
      CRITICAL, 31 HIGH, 38 MEDIUM, 53 LOW, 35 INFO**, consolidated into
      3 CRITICAL clusters, 10 HIGH clusters and 34 tail entries. Phase 3
      **wave 1 is complete, and wave 2 is complete as far as an agent can
      take it**: 2.3, 2.4, 2.5, 2.7 and 2.8 done, 2.6 two-thirds done,
      and 2.1/2.2/2.9 blocked on user decisions (D9, D13, D14) rather
      than on work. **Item 2.1 landed 2026-08-27** once D13 was answered
      — `myDockerPublishGuard` filters the four published game ports in
      FORWARD via DOCKER-USER, allowing only wg0 and tailscale0, VM-tested
      with a real container and client. **Wave 4 / Phase 4 is done** (see
      above); wave 3 is user-only by definition and not started. All work
      is on
      `worktree-worktree-security-audit-plan`, build-verified on
      homelab, vps, torrent and thinkpad, and **never switched**.

      Four changes are VM-tested rather than merely built: the
      `zfs-emergency-prune` sandbox, the vps `ipset` fail-open fix
      (including the parameter-drift scenario itself), both halves of
      2.8 (including a simulated hostile sender), and 2.1's DOCKER-USER
      guard. `tests/zrepl-replication.nix` and `tests/zfs-space-guard.nix`
      both grew permanent subtests, and `tests/docker-publish-guard.nix`
      is a new nine-subtest check that drives real packets at a real
      container rather than asserting on rule text alone.

      Read `docs/audits/2026-08-26/RESUME.md` first — it is written to
      be picked up cold.

      **Deferred out of wave 1, tracked so it does not get lost:**
      - ~~Item **2.9** (interface-scoping the desktop profile's host-wide
        firewall openings)~~ **DONE 2026-08-27**, and smaller than
        scoped: the user's D9 answers *removed* two of the three port
        groups (Steam remote play, avahi/mDNS) rather than narrowing
        them, leaving only KDE Connect to scope to `tailscale0`. No
        per-host LAN-interface option was needed and thinkpad did not
        need to be online.
      - ~~UDP 10400/10401 unattributable~~ **RESOLVED 2026-08-27.** They
        were Steam Remote Play's, opened by
        `programs.steam.remotePlay.openFirewall` alongside TCP
        27036/27037 and UDP 27031-27035, and closed when 2.9 dropped that
        option. Found by evaluating
        `options.networking.firewall.allowedUDPPorts.definitionsWithLocations`
        rather than grepping — the numbers appear nowhere as literals in
        this repo, which is why the original search failed. Lesson worth
        keeping: **attribute a port to the option that opens it, not to
        the port number**; the audit's inventory listed 27036/27037 and
        10400/10401 as separate items and never connected them.
      - ~~The *skipped*-deploy half of `F-P7-09`~~ — **done 2026-08-27**,
        build- and VM-verified, **not deployed**. Wave 1 item 1.9 made a
        **failed** deploy visible on the laptops; a skipped one was still
        silent, because every guard in `deploy-guards.nix` ends in
        `exit 0`.

        Closed by measuring the *outcome* rather than the attempt: all
        four hosts now watch `/nix/var/nix/profiles/system` for staleness
        via the existing `staleMarkerFiles`, so "this host has not
        actually been activated in N weeks" is caught regardless of
        cause — skip, failure, or a timer that stopped firing. A bespoke
        per-unit marker was rejected because it would have alarmed on
        hand-deployed hosts that were perfectly current. Separately,
        homelab's `systemd.services.auto-switch.onSuccess` is replaced by
        `myAutoUpdate.onDeployUnits`, gated on a real activation —
        the old wiring was observed starting the vps closure build in the
        same second the min-interval guard deferred the switch.

        **Two corrections to what this entry used to say**, both from
        homelab's journal. The units did **not** fail "every run since
        2026-08-25": the 08-25T13:18 runs skipped cleanly and the
        failures were the next scheduled runs at 08-27T03:00 and 03:15,
        about ten overnight hours. And the gap was **not** notification —
        both entered `systemctl --failed`, `myHealthAlerts` checks that
        every 15 minutes and ran 246 times in the window without a
        `curl` error, so the alert was sent. The real hole was that a
        *skipped* deploy produces nothing to detect at all, which is what
        the change above fixes.
      - **`push-deploy-vps` is the one piece of 2.6 not done**, and it is
        deferred on purpose. Its misleading comment is corrected; the
        sandbox is not applied, because `nixos-rebuild --target-host`
        shells out to `ssh`/`nix-copy-closure` and `PrivateTmp` +
        `ProtectSystem = "strict"` can break the SSH control-master path
        and nix's fetcher cache. It needs a VM test with a **real remote
        target**, and a wrong guess means vps silently stops updating.
      - A resumed `zfs recv` is not covered by 2.8's new test. `-o` on
        resume has historically been fussy; noted in the test header.
      - ~~**The containers have no resource ceilings.**~~ **Done
        2026-08-27** for `--memory` and `--pids-limit`, build-verified
        and confirmed in the rendered start scripts, **not deployed.**
        D15 was answered "no container may exceed 50% of the host's
        memory" → `--memory=7g` on both (MemTotal 15.54 GiB), with
        `--pids-limit=512` on `factorio-main` and `1024` on
        `minecraft-vanilla-plus`, both far above their measured peaks of
        19 and 123 and far below the host default of 19038.

        The memory figure is **an estimate, not a measurement** — the
        user said so explicitly, since the servers are mostly idle
        playerwise. It bounds the blast radius rather than tuning
        anything. Caveat recorded at D15: both containers carry the same
        50% cap, so simultaneous worst cases still exhaust the host;
        that is inherent in a per-container percentage and accepted,
        since it stops any *single* runaway. `--cpus` remains unset and
        undecided. Original note follows.

      - **The three containers have no resource ceilings.** Phase 4
        wrote the rule (`docs/hardening.md` standing rule 10); it is not
        yet applied. None of minecraft, `factorio-main` or
        `factorio-new` sets `--pids-limit`, `--memory` or `--cpus`, so a
        fork bomb or a memory leak in any of them is *host* OOM pressure
        on the box holding `zbackup`, and the kernel picks its own
        victim among jellyfin, smbd, nfsd and the restic job.
        `--pids-limit` is safe at a generous few thousand; `--memory`
        must come from measured RSS with headroom, **not** from
        minecraft's `MEMORY = "4G"`, which is JVM heap only (off-heap,
        DistantHorizons and the 1 GiB `/tmp` tmpfs sit on top of it). A
        ceiling set too low becomes an OOM-kill loop that reads as a
        game crash. *(F-P4-07)*

        **First measurement taken 2026-08-27** (`factorio-new` is gone
        since `7a047b7`, so this is two containers, not three). Read from
        each container's cgroup on homelab — host has 15.54 GiB:

        | | `memory.peak` | `pids.peak` | `memory.max` | `pids.max` |
        |---|---|---|---|---|
        | `factorio-main` | 1.06 GB | 19 | `max` | 19038 (host default) |
        | `minecraft-vanilla-plus` | 4.90 GB | 123 | `max` | 19038 |

        Confirms both halves of the finding: no ceiling is set on either,
        and minecraft's real RSS (4.90 GB) is ~0.9 GB *above* its
        `MEMORY = "4G"` JVM heap, so sizing from that setting would have
        been wrong in the OOM-kill direction.

        **These are not peaks.** Both containers had 37 minutes uptime
        (restarted by the 13:15 switch) and were almost certainly idle —
        `memory.peak` resets on restart, so there is no longer-run data.
        Treat them as a floor. `--pids-limit` can be set from them now
        with enormous margin (peaks of 19 and 123 against a 19038
        default); `--memory` needs either a load-representative
        observation window or a deliberately generous
        bound-the-blast-radius value chosen by the user, since only they
        know the real player load. **That choice is the open question.**
      - **`userns-remap` is not set** in
        `virtualisation.docker.daemon.settings`, so container uid 0 is
        host uid 0 on every bind mount and an escape lands as real root
        rather than a mapped subuid. Enabling it re-maps ownership of
        existing volumes, so it is not a one-line change — it needs its
        own VM test and a plan for the game-server data directories.
        *(F-P4-07)*

      **Everything requiring the user** — the ten credentials to rotate,
      the `secrets/*` edits agents may not make, and decisions D1–D14 —
      is a live checklist at
      [`docs/audits/2026-08-26/user-actions.md`](docs/audits/2026-08-26/user-actions.md).
      Two are free, reversible and should not wait: `chmod 600
      ~/.config/sops/age/keys.txt` (currently 0644 on the daily driver)
      and checking GitHub branch protection (there is no CI, so it is
      the only remaining control on fleet root).

      **Standing decision still open, carried over from the original
      entry:** homelab has no intrusion detection at all (no
      CrowdSec/fail2ban, unlike vps). Fine today *if* access really is
      gated entirely by tailscale's own device authorization
      (ACLs/key approval) rather than exposed ports — which is
      precisely what Phase 0 and P3 must confirm rather than assume.
      Needs an explicit decision on whether that trust boundary is
      sufficient long-term or whether basic protections belong at the
      homelab layer too.

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

- [ ] **2026-08-27: the three Minecraft/Factorio mod-supply tightenings
      that survive auto-update.** D14 was answered "keep auto-updating"
      and the risk is accepted in `docs/accepted-risks.md` AR-7 — but
      three things can still be tightened *without* giving up
      auto-update, and none was done yet. All three need a start-and-play
      check, which is why they are here rather than done.

      1. **Mark non-critical projects optional with a `?` suffix.**
         Upstream supports `pl3xmap?`, and optional projects are
         **excluded from the `VERSION_FROM_MODRINTH_PROJECTS`
         calculation** — so one lagging mod stops holding the whole
         server on an old Minecraft version, and merely warns instead of
         aborting startup when it has no compatible build. This is the
         highest-value one: it directly serves the "track the newest
         stable automatically" goal, because today *any single* mod of
         the sixteen can pin the server indefinitely. Needs a judgement
         call per mod on what is actually load-bearing for the world
         (e.g. geyser/floodgate almost certainly are; a mapper or a
         client-perf mod may not be), which is the user's call, not an
         agent's.
      2. **Pin individual projects by version** where a specific mod
         matters more than its freshness — syntax is `project:versionId`
         or `project:2.21.2`, and it composes with `?`. Worth doing for
         anything that has broken a world before.
      3. **Reconsider `MODRINTH_DOWNLOAD_DEPENDENCIES = "required"`.**
         It pulls transitive artifacts that appear nowhere in this repo,
         so the actual installed set is larger than the sixteen listed
         projects and is not visible from the config. At minimum, record
         what it actually resolves to once, so there is a baseline.

      Related but separate, already tracked above: the containers still
      have no `--pids-limit`/`--memory` ceilings, and `userns-remap` is
      unset. *(F-P4-03, F-P4-13, AR-7)*

- [ ] **2026-08-27: set up the new network printer/scanner (Brother
      MFC-L2740DW).** The old USB Brother is gone. `modules/profiles/PC.nix`
      is currently in a deliberate **placeholder state**: CUPS is enabled
      with `drivers = [ ]` and no printer declared, and `services.avahi`
      has been removed entirely (audit decision D9 option c — a static
      printer address needs no discovery protocol, which is less surface
      than firewalling UDP 5353 open on a roaming laptop). So nothing
      prints today, by design, until this is worked through.

      Steps, in order:
      1. **Give the printer a static address** — a DHCP reservation on
         the router is fine and is the least surprising option.
      2. **Try driverless first.** The MFC-L2740DW supports IPP
         Everywhere/AirPrint, so a queue of the form
         `ipp://<static-ip>/ipp/print` with model `everywhere` should
         need no vendor driver at all — keeping `drivers` empty.
         **Use the IP, not the usual `._ipp._tcp.local` URI**: that form
         resolves through avahi, and re-adding avahi to make printing
         work would undo D9. Declare the queue declaratively
         (`hardware.printers.ensurePrinters`) rather than clicking
         through the CUPS web UI.
      3. **Only if driverless fails**, add a driver — `brlaser` covers
         many Brother lasers, but check it actually lists this model
         before assuming, per the repo's check-the-source rule.
      4. **Scanning is a separate problem from printing** and is not set
         up at all right now. Prefer `sane-airscan` (driverless eSCL over
         the same static IP) over Brother's `brscan4` blob for the same
         reason as above; verify against the pinned nixpkgs rather than
         from memory.
      5. Note there is a known CUPS wrinkle where driverless queues added
         through the web UI or autodetection can silently fail to print
         while ones added via `lpadmin -m everywhere` work. If pages come
         out blank or jobs vanish, that is the first thing to check —
         it is a queue-creation problem, not a network one.

      Build-verified as a placeholder on torrent and thinkpad; no
      switch. *(D9, F-P1-04, F-P5-06)*

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

- [ ] **2026-08-25: build and test a full restore suite (scripts +
      procedures) against real data — out of scope of the zrepl
      migration itself.** The zrepl migration (branch
      `worktree-zrepl-migration-plan`) documents restore *paths* in
      `docs/procedures/backup-restore.md`, but per its handoff notes
      these remain unexercised against real data: the VM test
      (`docs/procedures/vm-testing.md`) only covers clone-based file
      recovery, and rollback / full-dataset restore have never been
      run for real. Needs: actual restore drills (clone-based file
      recovery, full-dataset rollback, disaster-recovery-from-scratch)
      for each host's `zbackup/backup/<host>/...` data, ideally scripted
      and repeatable rather than one-off manual runs, plus writing up
      the verified procedure in `docs/procedures/backup-restore.md` in
      place of the current unexercised steps. Supersedes the 2026-08-20
      "`docs/procedures/backup-restore.md` needs real content" entry,
      moved to `docs/DONE.md` 2026-08-25 once confirmed the doc already
      has real (if unexercised) content — this item is what's left.

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

- [ ] **2026-08-18: verify Android SMB share end-to-end** (homelab,
      `modules/services/samba.nix`, commits c5c0f0e..24c4913, moved to
      the dendritic `modules/services/` layout during the
      worktree-android-smb-share rebase). Added Samba alongside the
      existing NFS export (`modules/services/nfs.nix`) so
      Android — which has no usable native NFS client — can reach
      `/storage` and `/storage-bulk` read-write over the tailnet.
      Firewall/interface scoping mirrors nfs.nix (tailscale0 only, port
      445, nmbd/winbindd disabled, plus a `hosts allow`/`hosts deny`
      pair in smb.conf itself for defense-in-depth). Dedicated
      `android-smb` system user (multimedia group, no shell/login) is
      the SMB auth identity; smbd itself still runs as root since the
      upstream module gives it no user/group option and
      setuid-per-request is how Samba works — capability set is
      trimmed with the same always-safe systemd flags used elsewhere in
      this repo instead. `/var/lib/samba` added to homelab's
      impermanence persistence list so the SMB password survives
      reboot. The SMB password itself is now fully declarative: sops
      secret `homelab_samba_android_smb_password` (added by the user
      2026-08-19) plus an idempotent `samba-user-provision` oneshot
      that syncs it into passdb.tdb on every boot/activation before
      samba-smbd starts, auto-restarted on secret rotation via
      sops-nix's `restartUnits` — no manual `smbpasswd` step needed
      anymore. `server signing`/`smb encrypt` mandatory, `ntlm auth =
      ntlmv2-only`, spoolss/printer sharing disabled, and
      `wide links`/`follow symlinks = no` on both shares were added on
      top for defense-in-depth (commit c140108); `samba-user-provision`
      and `samba-smbd` both carry this repo's standard systemd
      hardening flags (`ProtectSystem=strict` on the provisioner,
      `NoNewPrivileges`/`Protect*`/`RestrictNamespaces`/`PrivateTmp` on
      smbd — full `ProtectSystem=strict` deliberately left off smbd
      itself, judged too likely to silently break auth/logging without
      enumerating every path it touches). **Deployed to homelab
      2026-08-21** (`nixos-rebuild switch --target-host root@homelab`)
      — see "homelab auto-update raced a manual deploy" incident note
      below for what happened during the first attempt. Testing done
      post-deploy (from `smbclient`, a real SMB3 client, run both
      locally on homelab and remotely over the tailnet — not yet from
      an actual Android device/app):
      - [x] `samba-user-provision.service` ran successfully
            (`Added user android-smb.` in its journal) and
            `samba-smbd.service` is active
            (`smbd: ready to serve connections...`).
      - [x] `smbclient -L localhost -U android-smb` authenticates with
            the sops-set password and lists both `storage` and
            `storage-bulk`.
      - [x] Read/write confirmed on `/storage`: created a dir + file,
            listed real existing share content (confirms it's serving
            the actual dataset, not empty), landed with
            `android-smb:multimedia` ownership, `0660`/`0770`+setgid
            masks — matches config exactly. Cleaned up afterward.
      - [x] `smb encrypt = mandatory`/`server signing = mandatory`
            didn't reject `smbclient` — since Samba refuses a
            connection outright if a client can't negotiate mandatory
            signing/encryption, successful read/write is direct proof
            both were in effect for this client.
      - [x] Tailnet-only lockdown smoke-tested for real (not just
            firewall-rule inspection): confirmed default-deny via
            `iptables -L nixos-fw` (`nixos-fw-log-refuse` catches
            everything not explicitly accepted) plus `-i tailscale0`
            scoping on both ports, then verified live from a separate
            LAN machine (`torrent`, also on homelab's 192.168.1.0/24) —
            explicit connections to homelab's **LAN IP**
            (`192.168.1.154`) on ports 445 and 2049 both timed out /
            unreachable; the same ports on homelab's **Tailscale IP**
            (`100.98.142.41`) connected successfully. (First attempt
            gave a false "reachable" result for the LAN IP — turned out
            to be a self-connect-via-loopback artifact when tested from
            homelab itself, `ip route get <own-LAN-IP>` resolved to
            `dev lo`; the LAN-vs-tailscale test from a genuinely
            separate host is the one that counts, and it passed.)
      - [x] Connected from an actual Android device — CX File Explorer,
            over Tailscale (`100.98.142.41:445`) — and confirmed
            genuine two-way read/write: created `test.txt` on-device,
            server-side `echo "hello world" > /storage/test.txt`
            (ownership stayed `android-smb:multimedia`, confirming the
            file was the same one the app created, not a new one), and
            the updated content showed up back on the device after
            refresh. End-to-end confirmed working.
            (Two FOSS clients were tried first and ruled out along the
            way, not app/config bugs: **Material Files** — connection
            attempts never reached the server at all, confirmed via
            zero smbd log entries and zero firewall packet/byte counts
            across multiple exact-timestamped retries; root cause
            unconfirmed, suspected app-side state bug, not a server
            config issue. **Ghost Commander** — correctly rejected by
            the server for being SMB1/2-only, real jcifs library, no
            SMB3 support; server's `server min protocol = SMB3` working
            as intended. **SambaLite** (Play Store + F-Droid, Apache
            2.0, SMBJ-based, explicit SMB2/3 support) was researched
            and recommended as the best remaining FOSS option but not
            yet tried, since CX File Explorer — proprietary, not
            FOSS — already confirmed the server side works correctly.
            Worth trying SambaLite for daily use if a FOSS client is
            wanted going forward.)
      - [ ] Still needed: rotate the password once (edit the sops
            secret — user does this, not Claude — then redeploy) and
            confirm `samba-user-provision.service` restarts
            automatically via sops-nix's `restartUnits` and the new
            password takes effect without a manual `smbpasswd` step.

      **Incident note (2026-08-21):** the first deploy attempt landed
      correctly, but `nixos-upgrade.service` (homelab's scheduled
      auto-update job, normally `Thu 03:00` — this run was off-schedule,
      cause unconfirmed) started *before* the manual deploy and finished
      *after* it, activating its own build from homelab's local
      `/etc/nixos` checkout (stale — predates even the dendritic
      migration) and silently reverting the manual switch. That
      auto-update run itself then failed (exit 4) once its own
      switch-to-configuration hit conflicting unit state. No data loss,
      no failed *service* beyond `nixos-upgrade.service` itself, no
      reboot needed — waited for it to fully finish, then redeployed
      cleanly. Separately worth noting: homelab's local `/etc/nixos` is
      still on an old commit (`e8b3458`) with uncommitted `flake.lock`
      changes and an untracked `hosts/android/` directory — worth
      reconciling so the next scheduled auto-update run doesn't build
      from stale/dirty state again.
- [ ] **2026-08-20: test the Geyser/Minecraft changes on homelab once
      deployed.** `services/minecraft.nix` (merged to master at
      `3270eae`, **not yet deployed**) now sets Geyser's
      `above-bedrock-nether-building: true` (fixes Bedrock players
      softlocking above the Nether roof — confirm with a live Bedrock
      client), `ENABLE_AUTOPAUSE`/`MAX_TICK_TIME=-1`/`--cap-add=NET_RAW`
      (confirm the container actually pauses when empty and resumes
      cleanly on the next connection, and that the watchdog doesn't
      fire on resume), and `VERSION = "LATEST"` instead of a pinned
      `26.2` (confirm the modded stack — Geyser, Floodgate,
      DistantHorizons, etc. — still starts cleanly on whatever version
      resolves, since none of `MODRINTH_PROJECTS` pins a mod version).
      None of this has been tested against the running container yet.

      **Confirmed deployed 2026-08-25** via live inspection: the
      container (now named `minecraft-vanilla-plus`, up 21h, `healthy`)
      has `ENABLE_AUTOPAUSE=TRUE`, `MAX_TICK_TIME=-1`, `VERSION=LATEST`,
      and `CAP_NET_RAW` all present — the config-level rollout is done.
      Still unverified: the actual Bedrock-client/nether-roof behavior.

      **2026-08-26: autopause confirmed broken**, surfaced for free by a
      full homelab reboot (done to verify the tailscale0-only firewall
      re-scoping survives a real boot, see the security-audit items
      above). Container logs on fresh start:
      `could not open eth0: ... Operation not permitted`,
      `[Autopause loop] Failed to start knockd daemon`. Docker itself
      does grant the capability (`docker inspect
      minecraft-vanilla-plus --format '{{.HostConfig.CapAdd}}'` →
      `[CAP_NET_RAW CAP_SETGID CAP_SETUID]`), but it doesn't survive the
      entrypoint's privilege drop from root to the unprivileged
      `minecraft` user — plain `setuid` clears effective capabilities
      unless something explicitly keeps them (ambient caps / `prctl
      PR_SET_KEEPCAPS` / file capabilities), none of which this image's
      entrypoint appears to do for knockd. So autopause has likely never
      actually worked since it was deployed 2026-08-20 — the container's
      been running continuously since then, so this is the first fresh
      start to reveal it. Needs a real fix, not just more testing: either
      get `CAP_NET_RAW` into knockd's effective set post-setuid (image-side
      fix, not something this repo controls) or use the workaround the
      log itself suggests — `AUTOPAUSE_KNOCK_INTERFACE` env var — if that
      routes around the packet-capture path entirely rather than hitting
      the same capability wall.

      **2026-08-26: root-caused and fixed in code (not yet deployed).**
      The image *does* have a post-setuid mechanism for this — itzg's
      Dockerfile runs `setcap cap_net_raw=ep /usr/local/sbin/knockd` at
      build time (added in itzg/docker-minecraft-server#2625, closing
      #2421, specifically so knockd regains `NET_RAW` after gosu's setuid
      drop to the unprivileged `minecraft` user without needing `sudo`).
      File capabilities granted on `execve()` are exactly what Docker's
      `--security-opt=no-new-privileges:true` disables by design (that's
      the flag's entire purpose) — `modules/services/minecraft.nix` had
      that flag set, so it was silently blocking the very mechanism the
      image relies on. `AUTOPAUSE_KNOCK_INTERFACE` (interface-name
      selection, default `eth0`) was a dead end, unrelated to this
      permission failure. `--security-opt=no-new-privileges:true` removed
      from `minecraft-vanilla-plus`'s `extraOptions`
      (`modules/services/minecraft.nix`); `factorio.nix` keeps it
      unchanged since factorio has no autopause/knockd. Accepted
      trade-off documented inline: `--cap-drop=ALL` already limits the
      bounding set to `SETUID`/`SETGID`/`NET_RAW`, so removing
      no-new-privileges only lets those three already-granted
      capabilities be exercised via setuid/file-cap binaries inside the
      container — nothing beyond what `--cap-add` already grants.
      `nixos-rebuild build --flake .#homelab` confirmed clean, and the
      built unit's `ExecStart` was inspected directly in the nix store to
      confirm `--security-opt=no-new-privileges` is gone while
      `--cap-drop=ALL`/`--cap-add=SETUID`/`--cap-add=SETGID`/
      `--cap-add=NET_RAW` are unchanged. **Not yet deployed** — needs
      `nixos-rebuild switch` on homelab (will restart the container,
      disrupting any players currently online) and then a real fresh
      container start to confirm knockd actually launches this time and
      autopause survives a full pause/knock/resume cycle without the
      watchdog firing.

      **2026-08-26: deployed, tested live, then autopause deliberately
      disabled again — resolved, differently than planned.** Deployed
      the no-new-privileges fix to homelab
      (`nixos-rebuild switch --flake .#homelab --target-host root@homelab`,
      PR #20 branch `worktree-minecraft-autopause-fix`) and confirmed the
      fix itself worked: fresh container starts showed knockd launching
      cleanly (no more `Operation not permitted`), the JVM paused via
      SIGSTOP repeatedly with no errors, and a real player join
      (LilijoySkyseeker, over Tailscale) triggered a clean knock-triggered
      resume with no watchdog kill — the root-caused bug is genuinely
      fixed. But live testing surfaced a bigger problem with keeping
      autopause on at all: this port is public (DNAT'd through vps for
      friends without Tailscale), and it gets knocked by internet
      background scanners every ~2-3 minutes regardless of real players
      — confirmed via `conntrack -L` on vps mid-cycle, both source IPs
      were Oracle Public Cloud, not the user. Under knockd's default 120s
      `AUTOPAUSE_TIMEOUT_KN` re-pause window, that noise alone kept the
      JVM resumed roughly 65-75% of "idle" time. Since pausing only ever
      saves CPU (a SIGSTOP'd JVM keeps its full heap resident — homelab
      has just 3.4GB RAM available with `MEMORY=4G` already pinned by
      this container alone, unaffected either way), most of autopause's
      actual benefit was already gone under real conditions. Considered
      shrinking `AUTOPAUSE_TIMEOUT_KN` to ~20-30s to reclaim most of that
      CPU-saving benefit cheaply, but the user chose the simpler option:
      **disable autopause entirely.** `modules/services/minecraft.nix`
      now drops `ENABLE_AUTOPAUSE`/`MAX_TICK_TIME`/`AUTOPAUSE_TIMEOUT_*`/
      `AUTOPAUSE_PERIOD` (letting the image's own tick watchdog apply
      again, no longer needing to be disabled) and `--cap-add=NET_RAW`,
      restoring `--security-opt=no-new-privileges:true` — now safe to
      restore since knockd's file-capability escalation is no longer
      exercised, leaving this container's bounding capability set
      *tighter* than before this whole investigation started
      (`SETUID`/`SETGID` only, vs. the original `SETUID`/`SETGID`/
      `NET_RAW`). Redeployed and confirmed live: `docker inspect` shows
      `CapAdd=[SETGID SETUID]`/`SecurityOpt=[no-new-privileges:true]`,
      container reaches `healthy`, clean startup logs with zero
      autopause/knockd references. `VERSION = "LATEST"` was also
      incidentally re-confirmed multiple times during this session's
      repeated fresh-container-start testing — Geyser/Floodgate/
      DistantHorizons/C2ME all load cleanly every time. **Still
      unconfirmed**: the Bedrock-client/nether-roof behavior — every
      live test this session connected over Java Edition, not Bedrock/
      Geyser, so `above-bedrock-nether-building: true` remains untested
      against a real Bedrock client.

- [ ] **2026-08-20: wg0 IPv4-endpoint fix — deployed and working; still
      needs to survive a real IPv6 address rotation unwatched.**
      `hosts/homelab/configuration.nix`'s wg0 peer now points at vps's
      stable IPv4 (`137.184.45.18:51820`) instead of vps's IPv6
      literal, fixing a bug where the tunnel died silently whenever
      homelab's RFC4941 privacy IPv6 address rotated (confirmed live:
      0% ping both directions despite `persistentKeepalive`).

      **Confirmed deployed and healthy 2026-08-25**: `wg show wg0` on
      homelab shows the peer endpoint as `137.184.45.18:51820` with a
      handshake ~2 minutes old. Still unconfirmed: this fix hasn't been
      watched live through an actual IPv6 rotation event yet (nothing to
      indicate one has happened since deploy) — confirm `wg show wg0`
      keeps a fresh handshake and jellyfin/minecraft/factorio stay
      reachable across the next one or two rotations (homelab's privacy
      addresses appear to rotate on the order of hours-to-a-day, based
      on prior observation).

- [ ] **2026-08-18: homelab backup/replication stack has several
      compounding risks if the box is powered off for an extended
      period (over a month), surfaced while reasoning through the full
      backup reset/re-test.** Grouped as one item since they originally
      shared a root cause (everything below was `Persistent = true`,
      firing its one missed catch-up run right at boot, all at once).
      **Partially reworked since 2026-08-18 — re-assessed 2026-08-25,
      not fully closed:**
      - **Boot-time contention pile-up — resolved 2026-08-25.** sanoid
        and syncoid (the original minutely/hourly `Persistent = true`
        timers this bullet was written about) no longer exist — replaced
        repo-wide by zrepl, a long-running daemon whose jobs run on
        their own internal interval from whenever the daemon starts, not
        systemd timer catch-up semantics. That already removed this
        specific pile-up mechanism for ZFS snapshotting/replication. The
        remaining three (`restic-backups-backblazeWeekly`'s timer plus
        both `myAutoUpdate` timers, fetch + switch) now have
        `Persistent = false` (`modules/nixos/auto-update.nix`,
        `hosts/homelab/configuration.nix`) instead of the
        `RandomizedDelaySec`/jitter approach first considered — a missed
        run after a long outage is skipped rather than fired
        immediately at boot, which removes the contention with zrepl's
        post-boot catch-up entirely rather than just spreading it over a
        smaller window. Chosen over jitter because none of the three
        need immediate catch-up (flake-update-test/auto-switch: a
        week's delay is a non-issue given `minSwitchInterval` already
        treats weekly cadence as normal; restic: already has a
        336h/14-day staleness alert via `myHealthAlerts` as a backstop,
        so a skipped cycle isn't silent). **Deployed to homelab
        2026-08-26** (`nixos-rebuild switch --flake .#homelab
        --target-host root@homelab`, off master post-merge — the
        `worktree-stagger-boot-timers` branch was already fully merged,
        this just landed it on the live box) — confirmed live via
        `systemctl cat` on all three units
        (`restic-backups-backblazeWeekly.timer`, `auto-switch.timer`,
        `flake-update-test.timer`) showing `Persistent=false`, no
        failed units post-switch. Still not observed through a real
        long-outage reboot (nothing to trigger that intentionally).
      - **Compounds directly with the item above**: **partially
        addressed.** `hosts/homelab/configuration.nix` now sets
        `myAutoUpdate.protectedUnits = [
        "restic-backups-backblazeWeekly.service" ]`, and
        `modules/flake/deploy-guards.nix`'s
        `check_protected_units_inactive` makes a scheduled auto-switch
        skip (and retry next cycle) rather than switch while that unit
        is active — see the git-identity entry in `docs/DONE.md`. This
        closes the specific "switch kills a mid-run backup" collision,
        but doesn't address the raw boot-time resource contention
        itself (previous bullet).
      - **Self-inflicted history loss from the `--keep-daily 2`
        retention** (disaster-recovery-only, not versioning, per
        explicit choice): once the first post-outage backup succeeds,
        its prune step drops straight to the 2 most recent backup-days,
        permanently discarding all pre-outage B2 history at that point.
        Intentional given the retention philosophy, but worth having a
        documented awareness of before it surprises someone during an
        actual recovery. Unchanged, still applies.
      - **Syncoid resume-base pruning — moot, mechanism replaced.** The
        specific failure mode (a stuck syncoid target's incremental base
        getting pruned before it catches up) no longer applies now that
        syncoid is gone; zrepl has its own hold/bookmark-based
        incremental-base guarantees (see the zrepl entry in
        `docs/DONE.md`), which is a different mechanism with different
        (already-encountered-and-fixed) failure modes, not a direct
        continuation of this specific risk.
      - **B2 key expiration — confirmed 2026-08-25 (user checked the B2
        web console): no expiration set** on the application key backing
        `homelab_backblaze_rclone_config`. Closed.
      Still open: the `--keep-daily 2` history-loss caveat above
      (intentional, just needs to stay documented) and observing the
      `Persistent = false` deploy through an actual long-outage reboot.

- [ ] **2026-08-18: add IPv6 support for the vps's forwarded game
      ports — reviewed 2026-08-26, parked as a long-term/low-priority
      project, not actively planned.** (Minecraft 25565/19132, Factorio
      34197/34198 — the latter added 2026-08-20 for `new.factorio`, same
      treatment needed). Currently IPv4-only: `net.ipv6.conf.all.forwarding`
      is explicitly off on the vps and there are no `ip6tables` DNAT
      rules for these ports, so `minecraft`/`factorio`'s DNS records
      were made A-only (`modules/services/octodns.nix`) after a live
      bug where the AAAA records
      advertised IPv6 reachability that didn't exist, silently
      breaking any client (confirmed: a Bedrock client) that prefers
      IPv6 when a hostname resolves to both. The apex still has an
      AAAA record since Caddy on the vps itself is native IPv6, no
      forwarding needed — this item is specifically about the DNAT'd
      raw TCP/UDP game ports.
      **Confirmed still unaddressed, 2026-08-25**: `net.ipv6.conf.all.
      forwarding` is still `0` live on vps, no ip6tables DNAT rules for
      these ports exist beyond the stock empty `nixos-nat-pre` chain.

      **2026-08-26 cost/benefit review, parked:** benefit is narrow —
      dual-stack clients (the large majority in 2026) already connect
      fine over the existing A records today; this would only help
      clients with *no* IPv4 path at all (genuinely IPv6-only networks),
      an unconfirmed and likely small slice of this server's actual
      whitelisted/friends-and-family player base. Cost is real and
      non-trivial, so not worth it speculatively:
      - True per-interface IPv6 forwarding doesn't exist on current
        mainline kernels (confirmed against an active 2025 LKML patch
        thread, `force_forwarding`, proposing to add it) — the only
        lever available is the blanket `net.ipv6.conf.all.forwarding`
        sysctl, a broader posture change than "wg0 egress only" as
        originally scoped above (narrowable via firewall FORWARD-chain
        rules, but not avoidable at the sysctl level).
      - Bigger issue found during this review: homelab's LAN interface
        already carries a real, globally-routable IPv6 address today
        (ISP RA-delegated, confirmed live). Making the game containers
        IPv6-reachable needs Docker dual-stack
        (`virtualisation.docker.daemon.settings.ipv6`), and
        `modules/services/minecraft.nix`/`factorio.nix` currently open
        their ports host-wide, not interface-scoped — so without *also*
        re-scoping those to `wg0` only, this would make the game
        containers directly reachable from the raw internet over IPv6,
        bypassing every one of vps's defenses (CrowdSec, fail2ban,
        per-IP rate limiting) entirely. This exact exposure pattern
        (host-wide firewall rule + homelab's already-public IPv6)
        already exists today for sshd/jellyfin, independent of this
        item — see the new item immediately below.
      - Full scope ends up touching wg0 addressing on both hosts, vps's
        NAT/DNAT plus a full parallel set of ip6tables rate-limit rules,
        homelab's Docker daemon (bounces both game containers on
        deploy), CrowdSec's tailnet allowlist, and DNS — roughly
        doubling the surface of an already carefully-tuned setup, in a
        corner (dual-stack Docker + WireGuard + custom ip6tables chains)
        fiddly enough that it's hard to fully validate without a real
        client on a real IPv6 path — this repo's other "confirmed
        deployed, not confirmed with a real client" items suggest that
        gap tends to linger.
      Conclusion: not worth pursuing unless a specific player is
      confirmed IPv6-only. Revisit if that ever comes up; otherwise this
      can sit indefinitely.

      **2026-08-26: long-term direction, separate from the above
      near-term "not worth it" call.** The parked verdict is about
      *this specific, narrow* ask (game-port forwarding only, bolted on
      ad hoc). The actual long-term goal for this repo is full dual-stack
      IPv4+IPv6 support everywhere, with the architecture and docs
      treating IPv6 as a first-class default going forward rather than
      an afterthought retrofitted host-by-host — i.e. new services and
      new hosts should be designed dual-stack from the start (including
      the "does this interface's IPv6 address also happen to be public"
      question this session kept running into), instead of repeating
      the same host-wide-firewall-rule-plus-surprise-public-IPv6
      discovery each time. That's a real architecture/documentation
      project of its own — worth scoping once the homelab
      security-audit item above has run its course and the general
      pattern (interface-scoped firewall rules as the default, not the
      exception; dual-stack assumed rather than special-cased) is
      better understood across the whole fleet, not just vps/homelab.

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

## Done

Completed items live in [`docs/DONE.md`](docs/DONE.md), not here — move an
item there (don't just check it off in place) once it's landed.

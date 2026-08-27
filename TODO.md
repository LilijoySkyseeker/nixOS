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
      than on work. Waves 3–4 not started. All work is on
      `worktree-worktree-security-audit-plan`, build-verified on
      homelab, vps, torrent and thinkpad, and **never switched**.

      Three changes are VM-tested rather than merely built: the
      `zfs-emergency-prune` sandbox, the vps `ipset` fail-open fix
      (including the parameter-drift scenario itself), and both halves of
      2.8 (including a simulated hostile sender). `tests/zrepl-replication.nix`
      and `tests/zfs-space-guard.nix` both grew permanent subtests.

      Read `docs/audits/2026-08-26/RESUME.md` first — it is written to
      be picked up cold.

      **Deferred out of wave 1, tracked so it does not get lost:**
      - Item **2.9** (interface-scoping the desktop profile's host-wide
        firewall openings) was moved from wave 1 to wave 2. It is not a
        mechanical edit: KDE Connect's 1714-1764 range is opened by the
        nixpkgs module itself with no `openFirewall` toggle, thinkpad
        declares no interface names at all, and it needs a decision on
        whether LAN discovery keeps working.
      - **UDP 10400/10401 are open on torrent and are not attributable
        to anything in this repo.** An unexplained open port is its own
        finding; identify it before 2.9 scopes a port set containing it.
      - The *skipped*-deploy half of `F-P7-09` is still open. Wave 1
        item 1.9 made a **failed** deploy visible on the laptops; a
        skipped one is still silent, because every guard in
        `deploy-guards.nix` ends in `exit 0`.
      - **`push-deploy-vps` is the one piece of 2.6 not done**, and it is
        deferred on purpose. Its misleading comment is corrected; the
        sandbox is not applied, because `nixos-rebuild --target-host`
        shells out to `ssh`/`nix-copy-closure` and `PrivateTmp` +
        `ProtectSystem = "strict"` can break the SSH control-master path
        and nix's fetcher cache. It needs a VM test with a **real remote
        target**, and a wrong guess means vps silently stops updating.
      - A resumed `zfs recv` is not covered by 2.8's new test. `-o` on
        resume has historically been fussy; noted in the test header.

      **Everything requiring the user** — the ten credentials to rotate,
      the `secrets/*` edits agents may not make, and decisions D1–D11 —
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

- [ ] **2026-08-20: deploy `new.factorio`** — merged to master
      (`c7796c9`), not yet deployed. A second Factorio server
      (`modules/services/factorio.nix`'s `factorio-new` container,
      floating `stable` tag, fresh random world) alongside the
      existing `old.factorio` (still pinned to the experimental
      2.1.14 line). Needs: `nixos-rebuild switch` on homelab (brings
      up the container) and vps (opens the 34198/udp DNAT/firewall/
      ratelimit rules), then an `octodns-sync` run (or its hourly
      timer) to push the new `old.factorio`/`new.factorio` A + SRV
      records to Cloudflare. See `hosts/vps/README.md`'s Status
      section. Once deployed, verify: `new.factorio` reachable by
      hostname alone (SRV lookup, untested — first real use of SRV
      records in this repo) and by `:34198`, `docker-factorio-new`'s
      preStart actually rsyncs `old.factorio`'s mods on a real start,
      and `old.factorio` (34197) still works unaffected.

      **2026-08-21: reported unreachable from an actual game client —
      needs investigation.** Everything checked so far looks healthy,
      which makes this confusing:
      - `factorio-new` container on homelab: up 7h, in-game
        (`ServerMultiplayerManager` state `InGame`), authenticated with
        Factorio's auth server, and registered on the public matching
        server (`MatchingServer.cpp: Matching server game '1232520' has
        been created`) at `97.206.73.106:34198` per its own logs.
      - `new.factorio.skyseekerlabs.net` resolves correctly to the vps
        (`137.184.45.18`), and a UDP probe (`nc -u -z -v`) to
        `:34198` got no ICMP unreachable back.
      - Despite both of the above, the user reports the client cannot
        actually connect/join.
      Not yet checked (as of 2026-08-21): whether the vps's DNAT/
      firewall/ratelimit rules for 34198 were actually deployed — the
      container could be up on homelab while the vps-side forwarding was
      never switched; the SRV-record lookup was also unverified; and a
      UDP `nc` probe getting no ICMP-unreachable isn't proof the DNAT
      rule itself forwards traffic all the way through.

      **2026-08-25 live triage: every infra layer now checks out.** On
      vps, `iptables -t nat -L nixos-nat-pre -n -v` shows the DNAT rule
      live and correct (`udp dpt:34198 to:10.100.0.2:34198`), alongside
      the working 25565/19132/34197 rules. DNS resolves correctly both
      ways: `dig SRV _factorio._udp.new.factorio.skyseekerlabs.net` →
      `0 0 34198 new.factorio.skyseekerlabs.net.`, and the A record
      resolves to vps's IPv4. The `factorio-new` container itself is
      still up (21h) alongside `factorio-main`/`minecraft-vanilla-plus`.
      vps's `current-system` was rebuilt today (2026-08-25 13:21, likely
      via the auto-updater rearchitect's deploy), so the 34198 rule's
      packet counters were freshly zeroed and can't confirm whether real
      client traffic has hit it since — that's the one thing this
      triage pass couldn't settle. Given everything on the infra side is
      now confirmed correctly configured and deployed, the original
      "vps-side forwarding was never switched" hypothesis no longer
      holds as an explanation; what's still missing is a genuine
      client-join retest to confirm the original Aug 21 report is
      actually resolved.

      **2026-08-26: still marked as needing an actual fix, not just more
      diagnosis** — flagged explicitly by the user rather than left to
      linger as an open investigation. Note this now also intersects with
      this session's homelab firewall re-scoping (see the security-audit
      item above): `modules/services/factorio.nix`'s 34197/34198 UDP
      rules moved from host-wide to `tailscale0`/`wg0`-interface-scoped
      only, which is exactly the DNAT'd-through-wg0 path `new.factorio`
      traffic already takes — shouldn't regress anything, but the
      pending client-join retest should happen *after* that firewall
      change lands, not before, so a retest failure can't be
      misattributed to the wrong change.

      **2026-08-26: that firewall change has now landed and is
      reboot-verified** (`deaf882`, `9134a47`, `0a774e5` — see
      `docs/DONE.md`), so the client-join retest is unblocked. Still
      needs a real game client to actually attempt joining
      `new.factorio` — not something checkable from infra inspection
      alone.

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

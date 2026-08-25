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

- [ ] **2026-08-25: add fail2ban to vps, defaulting to an immediate ban
      for any connection attempt against a non-present/non-listening
      service.** Requested by the user alongside the CrowdSec bouncer
      credential fix (landed 2026-08-25, see `docs/DONE.md`) — a
      complementary, simpler layer: rather than
      CrowdSec's scenario-based detection, fail2ban here should treat
      any probe of a port/service vps doesn't actually offer as
      inherently hostile (e.g. scanners hitting closed ports or
      non-existent vhosts) and ban on first sight rather than after a
      threshold. Needs: figure out what "non-present services" means
      concretely on vps (firewall-reject/deny log lines via the
      existing iptables logging, Caddy's access log for unmatched
      vhosts, etc.), a fail2ban jail per source, and `findtime`/
      `maxretry`/`bantime` tuned for immediate-ban-on-first-hit rather
      than fail2ban's normal repeated-failure default. Not started.

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
      Still unverified: the actual Bedrock-client/nether-roof behavior,
      and whether autopause/resume + the watchdog behave as intended —
      none of that is checkable without a live game client.

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
        so a skipped cycle isn't silent). Build-tested (`nixos-rebuild
        build --flake .#homelab`); not yet deployed or observed through
        a real long-outage reboot.
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
      - **Unverified**: whether the B2 application key
        (`homelab_backblaze_rclone_config` secret) has an expiration
        date set on Backblaze's side. Couldn't check without exposing
        the secret's contents; confirm on the B2 web console if this
        needs certainty. Unchanged.
      Still needs: deploy the `Persistent = false` change to homelab and
      confirm the B2 key expiration.

- [ ] **2026-08-18: sops-nix `age.keyFile` fallback doesn't actually
      fire when `age.sshKeyPaths` fails during early boot** (torrent).
      `profiles/PC.nix` configures both `sops.age.sshKeyPaths = [
      "/home/lilijoy/.ssh/id_ed25519" ]` and `sops.age.keyFile =
      "/var/lib/sops-nix/key.txt"`, with `keyFile` explicitly intended
      as the early-boot fallback since `/home` isn't mounted yet during
      initrd-stage activation (see the comment there). On a real boot,
      the initrd-stage `sops-install-secrets` run failed entirely
      (`Cannot read ssh key '/home/lilijoy/.ssh/id_ed25519': ... no such
      file or directory` immediately followed by `Error getting data
      key: 0 successful groups required, got 0`) instead of falling
      back to `keyFile` — `/run/secrets` never got populated for the
      rest of that boot (git identity, and presumably other
      home/root-critical secrets, all missing) until manually re-run
      post-boot via `run0 sops-install-secrets ...` (which then
      succeeded immediately, confirming `key.txt` itself and its
      `.sops.yaml` registration were never the problem). Looks like a
      real sops-nix bug/limitation: a failed `sshKeyPaths` entry seems
      to poison the whole identity list rather than gracefully falling
      through to `keyFile`. Needs: check for a known upstream sops-nix
      issue/fix, or restructure so boot-critical secrets don't depend on
      an identity path that's guaranteed to fail during initrd (e.g.
      drop `sshKeyPaths` from the boot-time identity list entirely and
      rely on `keyFile` alone there). Not yet reproduced against a clean
      reboot (holding off per the no-unconfirmed-local-restarts rule).

      **Confirmed still present in code, 2026-08-25** (path moved to
      `modules/profiles/PC.nix` post-dendritic, same content): both
      `sops.age.sshKeyPaths` and `sops.age.keyFile` are still configured
      in the same vulnerable order, unchanged. Still open, still
      unreproduced against a clean reboot.

- [ ] **2026-08-18: add IPv6 support for the vps's forwarded game
      ports** (Minecraft 25565/19132, Factorio 34197/34198 — the
      latter added 2026-08-20 for `new.factorio`, same treatment
      needed). Currently IPv4-only: `net.ipv6.conf.all.forwarding` is
      explicitly off on the vps and there are no `ip6tables` DNAT
      rules for these ports, so `minecraft`/`factorio`'s DNS records
      were made A-only (`modules/services/octodns.nix`) after a live
      bug where the AAAA records
      advertised IPv6 reachability that didn't exist, silently
      breaking any client (confirmed: a Bedrock client) that prefers
      IPv6 when a hostname resolves to both. The apex still has an
      AAAA record since Caddy on the vps itself is native IPv6, no
      forwarding needed — this item is specifically about the DNAT'd
      raw TCP/UDP game ports. Needs: enable IPv6 forwarding for wg0
      egress only (not blanket `net.ipv6.conf.all.forwarding`), add
      matching `ip6tables`/`nat` DNAT + FORWARD-accept rules alongside
      the existing IPv4 ones in `hosts/vps/configuration.nix`, an
      IPv6-capable SNAT equivalent so return traffic survives
      WireGuard's cryptokey routing (mirrors the existing IPv4
      POSTROUTING SNAT rule), then re-add the AAAA records.
      **Confirmed still unaddressed, 2026-08-25**: `net.ipv6.conf.all.
      forwarding` is still `0` live on vps, no ip6tables DNAT rules for
      these ports exist beyond the stock empty `nixos-nat-pre` chain.

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

- [ ] **2026-08-18: caddy hits a permission-denied race against the
      anubis unix socket right after vps reboots.** Found trawling
      vps's logs: from 03:18–03:47 (right after a 23:47 reboot), every
      request to `jellyfin.skyseekerlabs.net` 502'd with `dial unix
      /run/anubis/anubis-jellyfin/anubis.sock: connect: permission
      denied` (36 requests total), then self-resolved and hasn't
      recurred since (0 in the following ~13h). `caddy`'s `id` shows
      it *is* in the `anubis` group (`hosts/vps/configuration.nix`
      already has `users.users.caddy.extraGroups = [ "anubis" ]`,
      added for exactly this failure mode per the comment there) — so
      this looks like a boot-order race, not a missing-permission bug:
      caddy's group membership or the socket itself isn't ready by the
      time caddy starts serving. Needs: add an explicit
      `systemd.services.caddy.after`/`wants` (or similar ordering) on
      the anubis service/socket so caddy doesn't start accepting
      traffic until anubis's socket exists with the right group perms
      already applied.
      **Confirmed still unfixed in code, 2026-08-25** (no explicit
      caddy→anubis systemd ordering in `hosts/vps/configuration.nix`),
      but unverified live either way: vps hasn't rebooted since
      2026-08-20, so the race hasn't had a chance to reproduce (or be
      confirmed fixed) since it was first noticed.

      **Re-checked live 2026-08-25 (same session as the CrowdSec bouncer
      fix above, no reboot involved):** both `caddy.service` and
      `anubis-jellyfin.service` still show uptime since the 2026-08-20
      boot (today's crowdsec-only deploys didn't touch/restart either),
      so still no fresh data on the race itself. Swept caddy's entire
      journal history for the `dial unix .../anubis.sock: permission
      denied` signature: all 36 occurrences are confined to the single
      Aug 18 03:30–03:31 window already described above, zero since —
      consistent with "self-resolved, boot-order race" rather than a
      persistent config problem. Socket perms
      (`srwxrwx--- anubis:anubis`) and caddy's `anubis` group membership
      both currently correct. Live functional check: `curl
      https://jellyfin.skyseekerlabs.net/` → `HTTP 302` (working
      normally). Still needs an actual reboot to confirm one way or the
      other whether the race recurs.

## Done

Completed items live in [`docs/DONE.md`](docs/DONE.md), not here — move an
item there (don't just check it off in place) once it's landed.

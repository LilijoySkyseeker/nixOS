# TODO / plans & goals

Running log of plans and goals discussed for this repo, so they can be
referenced across sessions. Not a replacement for host-specific docs
(e.g. `hosts/*/README.md`) — this is for higher-level, cross-host
or longer-horizon items.

Convention: add a dated entry when a new plan/goal is agreed on; check
items off or move them to "Done" as they land; prune stale/abandoned
items rather than letting them rot.

## Active

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

- [ ] **2026-08-18: add IPv6 support for the vps's forwarded game
      ports** (Minecraft 25565/19132, Factorio 34197). Currently
      IPv4-only: `net.ipv6.conf.all.forwarding` is explicitly off on
      the vps and there are no `ip6tables` DNAT rules for these ports,
      so `minecraft`/`factorio`'s DNS records were made A-only
      (`services/octodns.nix`) after a live bug where the AAAA records
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
      any host's correctness.

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

- [ ] **2026-08-19: `octodns-sync.service` failing on homelab —
      transient DNS resolution error.** Found during a read-only log
      trawl through homelab (checked against exposed services in
      `hosts/homelab/configuration.nix`; no signs of compromise, SSH
      and service access all traced to known keys/tailnet/LAN). Job
      failed with `requests.exceptions.ConnectionError` /
      `NameResolutionError` trying to reach `api.cloudflare.com`
      (`Failed to resolve 'api.cloudflare.com' ... Temporary failure
      in name resolution`). Timer retries hourly so this may self-heal,
      but worth confirming it isn't recurring (e.g. flaky upstream
      resolver, or the service starting before network-online.target).

- [ ] **2026-08-19: `flake-update-test.service` failing on homelab —
      root has no git identity configured.** Found during the same log
      trawl. The update-branch step fails with `fatal: unable to
      auto-detect email address (got 'root@homelab.(none)')` right
      after the flake inputs are bumped, because `git config
      --global user.email`/`user.name` were never set for root on
      homelab. Needs: set a git identity for root declaratively (e.g.
      via `home-manager.users.root.programs.git` in
      `profiles/server.nix`, alongside the existing root home-manager
      block) so `myAutoUpdate`'s commit step succeeds.

- [ ] **2026-08-19: coordinate the 10 parallel homelab-blocked branch
      sessions into a merge order** (live coordination in progress;
      merges to master approved piecemeal as sessions clear their own
      gates, but no `nixos-rebuild switch` on homelab until the backup
      finishes). Homelab is tied up running
      `restic-backups-backblazeWeekly` (a from-scratch B2 backup after
      a deliberate bucket wipe, ~587GiB). As of latest check-in:
      174.85GiB uploaded (~29.8%), ~2.16MiB/s (WAN-capped), ETA ~54.3h
      (~2.3 days) remaining. Status per session:

      - **backblaze homelab reset** (`worktree-b2-backup-reset`) — the
        blocker, still running. 3 commits already deployed live to
        homelab (`ea562c4`, `560a635`, `edd8c1e`). 1 more
        (`1977e94`, drops `Nice`/`CPUSchedulingPolicy`) held back
        until the backup finishes.
      - **wireguard ipv6 bug** (`worktree-vps-exit-node`) — done,
        committed, unmerged. Holding: will rebase onto master and
        redo the restic-unit store-path diff once backblaze-reset's
        commit lands, then deploy together in one `switch`.
      - **minecraft geyser version update**
        (`worktree-mc-geyser-nether-roof`) — **merged to master**
        (`3270eae`). Holding on `switch`: a diff-check found the
        branch was built from a stale base (predates
        backblaze-reset's 3 live fixes) — switching now would
        silently revert retention/lifecycle/scope changes on homelab.
        Waiting for backblaze-reset's fixes to land on master, then
        will rebase/re-check before switching.
      - **jellyfin gpu acceleration** (`worktree-jellyfin-gpu-accel`)
        — **merged to master** (`d80c538`). Holding on `switch` for
        two reasons: same base-staleness issue as geyser, plus
        backblaze-reset flagged that any nvidia/videoDrivers-driven
        kernel-module reload is inherently too risky to apply mid-
        backup regardless of unit diff (shared-kernel/whole-box
        stability risk) — holding until the backup fully completes,
        not just until rebased.
      - **verify crawler rate limiting** (`worktree-vps-base-ratelimit`)
        — **merged to master** (`1edea5b`) and **deployed live to
        vps** (`nixos-rebuild switch` from torrent, confirmed: new
        80/443 iptables rate-limit rule present, 0 drops so far).
        vps-only, no interaction with the homelab backup at all.
        Final end-to-end verification (real traffic through jellyfin)
        is on hold since jellyfin's backend rides the same dead wg0
        tunnel wireguard-ipv6-bug is fixing — will finish once that
        deploys.
      - **nix build cache setup** (`worktree-nix-cache`) — done,
        build-clean, committed, not pushed. Diffed directly against
        distributed-nix-builds-setup: no semantic option conflict
        (separate `nix.*` keys, distinct sops secret names). Resolved
        the same-line `imports` collision unilaterally on its own
        side — moved its two homelab imports to the end of the
        imports list (away from the other branch's insertion point),
        rebuilt clean (pure reorder, same output path), committed.
        Also confirmed backblaze-reset never touched
        `backblazeWeekly`'s `OnCalendar` field directly (still Fri
        03:00 on their side, unchanged from master) — no direct
        collision with this branch's move to Thu 03:00, though the
        surrounding restic block (storage-bulk scope) still needs a
        careful look at actual merge time. Holding push/merge/switch
        for backup clearance.
      - **distributed nix builds setup**
        (`worktree-distributed-build-todo`) — done, build-clean,
        committed (`2aba77c`), not pushed. Placeholder values mostly
        filled in with real data: torrent's `maxJobs`=16 (confirmed
        via `nproc`, session's shell was running on torrent itself;
        also confirmed torrent has no `/sys/class/power_supply`,
        validating no AC-gating needed there), homelab's real SSH
        host key pinned via `ssh-keyscan` as `publicHostKey` in
        thinkpad's/torrent's `nix.buildMachines` entries. **Bug
        caught and fixed**: the original plan's `publicHostKey`
        encoding was wrong (base64'd just the key field instead of
        the full `.pub` file content) — verified against actual
        nixpkgs source (`nix-remote-build.nix`) and corrected in all
        three host configs. Still open, genuinely blocked pre-deploy:
        thinkpad's/torrent's own `publicHostKey` (needs sshd running,
        which needs this to deploy first — chicken-and-egg, fix in a
        follow-up commit after each host's first deploy), homelab's
        own `maxJobs` (no admin SSH login from this session), and
        thinkpad's AC power-supply node name (pending user booting
        thinkpad). Import-list conflict with nix-build-cache resolved
        on the other side (see above) — nothing further needed here.
      - **add samba smb share** (`worktree-android-smb-share`) — in
        progress. Since last full report, added a new not-yet-
        committed change: made the Samba password declarative (sops-
        managed secret + idempotent provisioning systemd unit,
        replacing a manual one-time smbpasswd) — needs the user to
        add `secrets/secrets.yaml` key
        `homelab_samba_android_smb_password` before it'll even build.
        Live tailnet-lockdown smoke test (port 445/2049 unreachable
        off-tailnet) still not run — blocked on both that secret and
        homelab's backup lock. Not pushed/merged yet.
      - **zfs backups plus spaceguard** (`worktree-zfs-backup-push`)
        — sops-secret blocker **cleared**: user generated both
        keypairs, added to `secrets/secrets.yaml`, all three hosts
        (homelab/torrent/thinkpad) build clean end-to-end. Ran a real
        dry-run merge test (`git merge --no-commit --no-ff` against
        zfs-pool-recovery-restore's pushed branch, then aborted
        cleanly) — result: `disko.nix` and
        `hosts/homelab/configuration.nix`, the files everyone worried
        about, merged with **zero conflicts** (different regions
        touched). Real conflicts are minor/mechanical: thinkpad's/
        torrent's `configuration.nix` imports lists and `TODO.md`,
        both appending in the same spot — trivial manual interleave.
        Agreed directly with zfs-pool-recovery-restore: this branch
        merges first once backup/live-pool sequencing clears, they
        rebase the small thinkpad/torrent bit on top after. Holding
        push/merge/switch — the live storage-bulk rename must land
        atomically with a homelab switch, and any switch right now
        risks disturbing the in-progress backup.
      - **zfs pool recovery restore** (`worktree-fde-secureboot-plan`)
        — large secure-boot/LUKS/impermanence reinstall project, all
        commits pushed to origin. Everything Phase-2 (LUKS/secure-
        boot/impermanence) gated behind `myPhase2.reinstalled=false`
        — inert, safe regardless of merge order. Merge-order agreed
        with zfs-backups+spaceguard (see above). One small follow-up
        pushed to its own branch (thinkpad.conf value matching the
        other branch's new zbackup naming) — script config only, not
        a live-host change. Reinstall order thinkpad → torrent →
        homelab (last), no reinstall attempted on any host yet — low
        urgency, well after this round of merges.

      **Current working order** (backup ETA ~2.3 days as of latest
      check-in; only step 1 is a hard blocker, everything else is
      diffed/prepped and ready to land as each session's own gate
      clears):
      1. backblaze-homelab-reset finishes the B2 backup, lands
         `1977e94`, merges to master.
      2. Already merged to master, holding only on `switch`:
         minecraft-geyser (needs backblaze-reset's fixes on master
         first, then rebase+recheck), jellyfin-gpu-accel (needs the
         backup fully done, not just rebased, due to the driver-
         reload risk). crawler-rate-limiting is fully done (merged +
         deployed to vps already).
      3. wireguard-ipv6 rebases on master, deploys together with
         backblaze-reset's commit in one `switch`.
      4. nix-build-cache and distributed-nix-builds-setup: conflict
         resolved, nix-build-cache ready to push/merge; distributed-
         nix-builds-setup has 3 small pre-deploy items outstanding
         (thinkpad/torrent host keys post-first-deploy, homelab
         maxJobs, thinkpad AC node name) that don't block merging the
         code itself.
      5. add-samba-smb-share: needs the user to add the
         `homelab_samba_android_smb_password` sops secret, then a
         live smoke test, before push/merge.
      6. zfs-backups+spaceguard merges first (dry-run confirmed clean
         on the files that mattered), zfs-pool-recovery-restore
         rebases its small thinkpad/torrent bit on top after — both
         still gated on backup/pool-sequencing clearance.

      **2026-08-20: three more sessions joined, folded into this
      plan:**
      - **factorio server migration** (`worktree-factorio-new-server`)
        — done, committed locally (`520987f`), not pushed/merged.
        Adds a second `factorio-new` oci-container in
        `services/factorio.nix`, additive-only vps port/firewall
        entries for UDP 34198, new octodns A/SRV records, and one new
        homelab persistence-dir entry (`/srv/factorio/new`). No real
        conflict with anything already on this list; the persistence
        entry is just a note for whoever sequences the next homelab
        rebuild after the backup — not a conflict with the
        in-progress backup itself since unmerged.
      - **nelson migration dendritic flake**
        (`worktree-nelson-dendritic-plan`) — a repo-wide restructuring
        to flake-parts + import-tree. Functionally done and verified
        equivalent to master via derivation/closure diffing, but NOT
        merged (awaiting user go-ahead). Scope: `flake.nix` fully
        rewritten, `flake.lock` gets new inputs, `profiles/` and
        `services/` **moved** to `modules/profiles/` and
        `modules/services/` (git renames, every file also rewritten),
        every host's `configuration.nix` imports list trimmed, new
        `modules/flake/{vars,pkgs,systems,hosts,devshell}.nix`. 50
        files changed (+3088/-2577). **High blast radius** — direct
        conflicts flagged with jellyfin-gpu-accel
        (`services/jellyfin.nix` moved), minecraft-geyser
        (`services/minecraft.nix` + geyser-config dir moved),
        factorio-server-migration (`services/factorio.nix` moved);
        likely conflicts with distributed-nix-builds/nix-build-cache
        (`flake.nix` rewritten) and anything touching
        `hosts/*/configuration.nix` imports (zfs-backups+spaceguard,
        zfs-pool-recovery-restore, backblaze-homelab-reset,
        wireguard-ipv6, crawler-rate-limiting — though for most of
        these only the imports section changed, not the config body).
        add-samba-smb-share's new `services/samba.nix` would need to
        land under `modules/services/` post-migration or go unscanned
        by import-tree. **User decision (2026-08-20): dead-last.**
        This branch merges only after every other in-flight branch
        (backblaze-homelab-reset, wireguard-ipv6, minecraft-geyser
        switch, jellyfin-gpu-accel switch, nix-build-cache,
        distributed-nix-builds, samba, zfs-backups+spaceguard,
        zfs-pool-recovery-restore, factorio-server-migration) has
        landed on master — one rebase at the end, resolved as a pure
        file-move/reorg rather than N-way. All affected sessions
        notified and acknowledged; several correctly noted they still
        need their own user's explicit go-ahead before merging (a
        relayed instruction from this session isn't authorization in
        their own session). No change to any other branch's own
        blocking status — this only fixes where the dendritic branch
        sits in the queue.
      - **nelson security review** — read-only audit, no branch, no
        code changes, clean tree on master. Has a *proposed but not
        yet applied* plan to split `.sops.yaml` into per-host secret
        scoping — worth a second look later since zfs-backups
        +spaceguard, samba, and distributed-nix-builds all add new
        sops secrets to the current single `.sops.yaml`, but nothing
        actioned yet so no current conflict.

      Nothing has been switched on homelab yet in this round;
      crawler-rate-limiting is the only branch fully live (vps, an
      unrelated host).

## Done

- [x] **2026-08-18: confirmed + fixed — crowdsec was never actually
      banning anything on vps.** Root cause found via
      `curl http://127.0.0.1:6060/metrics` (crowdsec's own prometheus
      endpoint) and `cscli explain`: `services.caddy.virtualHosts.
      <host>.logFormat` defaults to `null` in the pinned nixpkgs caddy
      module (confirmed by reading
      `nixos/modules/services/web-servers/caddy/default.nix` directly,
      not just docs), so no `log {}` block was ever emitted for
      `jellyfin.skyseekerlabs.net` — caddy only wrote sparse
      error/tls/acme events to the journal, never real per-request
      access logs. crowdsec's `crowdsecurity/caddy-logs` parser (which
      needs the `request` object only access-log entries carry) had
      **0 hits in its entire runtime**, confirmed both via its
      prometheus counter being entirely absent from `/metrics` and via
      a live test request producing no new parser activity — despite
      heavy leakix.net-style vulnerability-scanner traffic hitting the
      host over the preceding 24h. (Side note while debugging: `sudo
      -u crowdsec cscli ...` silently no-ops with exit 200 and zero
      output on this host, since `sudo` is aliased to `run0` which
      can't switch to `crowdsec`'s `nologin` shell — use
      `runuser -u crowdsec --` instead; my first pass at this
      investigation used the broken `sudo -u crowdsec` form and
      wrongly reported "zero decisions/alerts" as a real empty result
      rather than a broken command.) Fix: added an explicit
      `logFormat = "output stdout\nformat json"` to the jellyfin
      vhost in `hosts/vps/configuration.nix`, verified by inspecting
      the actual rendered `Caddyfile` (`log { output stdout; format
      json }` now present) and by confirming via `cscli explain` that
      a real captured caddy log line parses successfully and matches
      `crowdsecurity/http-crawl-non_statics` once given that JSON
      shape. **Deployed and confirmed live 2026-08-18**: after the
      `logFormat` fix, `crowdsecurity/caddy-logs` still had 0 hits —
      `journalctl -u crowdsec` showed `UnmarshalJSON: invalid
      character 'A' looking for beginning of value` on every caddy
      line. Second root cause: journalctl always prefixes lines with
      the syslog envelope (`Mon DD HH:MM:SS host caddy[pid]: `), and
      only `labels.type = "syslog"` (not `"caddy"`) routes events
      through `crowdsecurity/syslog-logs` to strip that prefix before
      `caddy-logs` sees the JSON — a known crowdsec gotcha
      (crowdsecurity/crowdsec#4098: "Journalctl sources MUST use
      syslog type"). Fixed the acquisition's `labels.type` to
      `"syslog"` in `hosts/vps/configuration.nix`, redeployed, then
      verified end-to-end live: sent real probe requests
      (`.env`, `.git/config`, `wp-login.php`, etc.) through
      `jellyfin.skyseekerlabs.net`, watched `cs_bucket_poured_total`
      increment across five caddy scenarios, and got a real
      `crowdsecurity/http-admin-interface-probing` ban decision back
      from `cscli decisions list` — then deleted that decision since
      it was our own test traffic, not a real attacker. crowdsec now
      genuinely bans scanners hitting jellyfin; before this it never
      had.

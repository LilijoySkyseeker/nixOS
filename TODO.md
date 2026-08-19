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
      sessions into a merge order** (planning only so far, no
      pushes/merges/switches until explicitly approved). Homelab is
      tied up running `restic-backups-backblazeWeekly` (a from-scratch
      B2 backup after a deliberate bucket wipe, ~587GiB, was ~28.5%
      done as of 2026-08-19 with an ETA of ~2.2 days), which several
      other branches need to avoid disturbing mid-run since it reads
      live ZFS snapshots. Status gathered by messaging each session
      directly (git branch/worktree name, files touched, commit state,
      overlaps):

      - **backblaze homelab reset** (`worktree-b2-backup-reset`) — the
        blocker. 3 commits already deployed live to homelab
        (`ea562c4`, `560a635`, `edd8c1e`: B2 bucket-scope, lifecycle
        rule, retention). 1 more commit held back deliberately
        (`1977e94`, drops `Nice`/`CPUSchedulingPolicy` from the restic
        unit) — build-verified safe but not deployed yet since
        deploying would restart the in-progress backup. Land this
        last commit (needs a real `nixos-rebuild switch`, not just
        build) once the backup finishes or is otherwise judged safe to
        restart.
      - **wireguard ipv6 bug** (`worktree-vps-exit-node`) — done,
        committed. One real change: `hosts/homelab/configuration.nix`
        wg0 peer endpoint for vps, IPv6 literal → IPv4 literal (fixes
        dead vps↔homelab tunnel breaking minecraft/factorio
        reachability). Same file as backblaze-reset's changes but a
        different stanza — already coordinated directly with that
        session: rebase on top of master once backblaze-reset's
        backup finishes and its commits land, deploy together in one
        `switch` to avoid multiple restic-unit restarts.
      - **minecraft geyser version update**
        (`worktree-mc-geyser-nether-roof`) — done, 3 commits already
        **pushed to origin** (not merged/deployed). Touches only
        `services/minecraft.nix` (nether-roof fix, autopause,
        VERSION pinned→LATEST) + new
        `services/minecraft-geyser-config/Geyser-Fabric/config.yml`.
        No overlap with anything else on this list — mergeable
        independently, any time.
      - **nix build cache setup** (`worktree-nix-cache`) — done,
        build-clean on all 5 hosts, not yet pushed. Adds
        `modules/nixos/nix-cache-{server,client,warm}.nix` (harmonia
        over tailscale). **Conflict risk:** moved
        `services.restic.backups.backblazeWeekly.timerConfig.OnCalendar`
        from Fri 03:00 to Thu 03:00 in
        `hosts/homelab/configuration.nix` — same block
        backblaze-homelab-reset is editing; diff carefully before
        merging, don't blind-merge. Also reshuffled
        `myAutoUpdate`/`myPushDeploy`/`myPullDeploy` schedule days
        across homelab/thinkpad/torrent. Flagged as a close relative
        of **distributed nix builds setup** (not yet reported in) —
        both add sections to the same three hosts'
        `configuration.nix`; complementary in effect but should be
        sequenced, not merged simultaneously.
      - **zfs backups plus spaceguard** (`worktree-zfs-backup-push`) —
        in progress, committed + build-clean on 3 hosts, not
        merged/deployed. Blocked on the user generating 2 sops
        secrets (SSH keypairs) before going live — a user step, not
        technical. New `modules/nixos/{backup-push,zfs-space-guard}.nix`;
        reshapes `hosts/homelab/disko.nix` zbackup dataset tree; new
        backup-recv user + zfs delegation on homelab.
        **Real overlap with zfs-pool-recovery-restore**: that branch
        also touches homelab's `disko.nix` (LUKS-wraps zdata/zbackup)
        and adds its own `modules/nixos/zfs-snapshots.nix` replacing
        homelab's inline sanoid/syncoid block — the two need to diff
        against each other before either merges. Lower urgency for
        now since zfs-pool-recovery-restore's pool-affecting bits are
        gated off (see below) and reinstall order puts homelab last.
      - **zfs pool recovery restore** (`worktree-fde-secureboot-plan`)
        — turned out to be a much larger secure-boot/LUKS/impermanence
        reinstall project, not a narrow pool-recovery fix. All commits
        already **pushed to origin**, build-verified per host. Adds
        `modules/nixos/{secure-boot,zfs-support,zfs-snapshots,
        zfs-root-impermanence,disko-luks-zfs,phase2-gate,
        luks-stage2-unlock}.nix`, a `scripts/reinstall-host.sh`
        orchestrator, lanzaboote flake input. Everything Phase-2
        (LUKS/secure-boot/impermanence) is gated behind
        `myPhase2.reinstalled`, defaulting false on all hosts — safe
        to merge without changing live behavior. Reinstall order:
        thinkpad → torrent → homelab (last), no reinstall has happened
        yet on any host. Will coordinate with backblaze-homelab-reset
        before any real pool-affecting action once homelab's turn
        comes, well after this backup episode.
      - **distributed nix builds setup, jellyfin gpu acceleration,
        add samba smb share, verify crawler rate limiting** — status
        not yet reported back as of this writing; nix-build-cache
        already flagged distributed-nix-builds as a likely
        `configuration.nix` sequencing conflict (same 3 hosts, same
        files, complementary features).

      **Working order once homelab is unblocked** (draft, pending the
      remaining 4 reports and final user go-ahead):
      1. backblaze-homelab-reset finishes/lands its held-back commit.
      2. minecraft-geyser merges any time (no dependency).
      3. wireguard-ipv6 rebases on master, deploys together with #1 in
         one switch.
      4. nix-build-cache and distributed-nix-builds-setup diff/rebase
         against each other and against backblaze-reset's
         `backblazeWeekly` OnCalendar change, then merge in an agreed
         sequence (not simultaneously).
      5. zfs-backups+spaceguard and zfs-pool-recovery-restore diff
         `hosts/homelab/disko.nix` + sanoid/syncoid areas against each
         other before either merges; zfs-pool-recovery-restore's
         Phase-2 bits stay inert (`myPhase2.reinstalled=false`)
         regardless of merge order.
      6. samba, jellyfin-gpu, crawler-rate-limiting — pending status,
         presumed independent unless they report otherwise.

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

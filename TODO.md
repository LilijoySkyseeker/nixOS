# TODO / plans & goals

Running log of plans and goals discussed for this repo, so they can be
referenced across sessions. Not a replacement for host-specific docs
(e.g. `hosts/*/README.md`) — this is for higher-level, cross-host
or longer-horizon items.

Convention: add a dated entry when a new plan/goal is agreed on; check
items off or move them to "Done" as they land; prune stale/abandoned
items rather than letting them rot.

## Active

- [ ] **2026-08-18: migrate torrent and thinkpad to impermanence.**
      Agreed as a prerequisite for eventually shrinking their zfs-backup
      scope (see the zfs-backups item below) — both hosts currently
      keep `zroot/local/root` as durable state, impermanence would wipe
      root on boot and move real state to an explicit persist dataset.
      Needs its own disko layout changes + persist-path audit per host,
      and should be VM-tested before real hardware per
      `feedback_test_remote_deploys_in_vm`. Not started.

- [ ] **2026-08-18: syncoid push backups, torrent + thinkpad → homelab
      (zfs snapshot based, over Tailscale).** Architected 2026-08-18:
      shared `myBackupPush` module (`modules/nixos/backup-push.nix`),
      used identically by both hosts, pushing `zroot/local/home` +
      `zroot/local/root` to a new dedicated `backup-recv` user on
      homelab via `zfs allow`-scoped delegation into
      `zbackup/backup/torrent/*` and `zbackup/backup/thinkpad/*` (the
      `backup/thinkpad` disko dataset already existed as an unused
      placeholder; `backup/torrent` is new). Uses syncoid
      `--create-bookmark` so long offline periods (esp. the thinkpad
      laptop) don't force a full resync once sanoid's short source-side
      retention (hourly=24/daily=1) prunes past the last pushed
      snapshot. Trigger: hourly systemd timer, `Persistent = true`,
      gated by a Tailscale-reachability `ExecCondition` so an
      asleep/offline laptop no-ops instead of alerting. Target-side
      retention on `zbackup` reuses the existing `template_backup`
      (hourly=168, daily=366) already governing `backup/thinkpad`/
      `backup/legion`. **Follow-up once impermanence (above) lands**:
      `zroot/local/root` will likely stop being the meaningful thing to
      back up — update `myBackupPush.datasets` on both hosts to point
      at whatever the new persist dataset ends up being called instead.
      Also gained (2026-08-18): source-side runs as a dedicated
      `backup-push` user (zfs-allow-scoped, not root — see
      `modules/nixos/backup-push.nix`), and a paired
      `modules/nixos/zfs-space-guard.nix` (`myZfsSpaceGuard`) on both
      hosts auto-prunes oldest local snapshots under free-space pressure
      (torrent/thinkpad's game libraries under `zroot/local/home` churn
      heavily) plus a `zfs-emergency-prune.service` manual escape hatch.
      torrent's `backupStaleness` threshold relaxed to 336h/2wk to match
      thinkpad's, since it's a desktop that can also go dark on
      vacation. Code committed on branch `worktree-zfs-backup-push`
      (commits b9954dd, 265000d); **not yet deployed to any real host.**

      Checklist to finish rollout:
      - [ ] Generate `torrent_backup_push_key` and
            `thinkpad_backup_push_key` ed25519 keypairs.
      - [ ] Add both private keys to `secrets/secrets.yaml` via `sops
            secrets/secrets.yaml` (never edit sops files directly).
      - [ ] Paste both public keys into
            `hosts/homelab/configuration.nix`'s
            `backup-recv.openssh.authorizedKeys.keys`, each prefixed
            with `restrict ` (two `# TODO` markers there now).
      - [ ] Re-run `nixos-rebuild build --flake .#{homelab,torrent,thinkpad}`
            to confirm all three build clean once secrets exist.
      - [ ] Deploy homelab first (creates `backup-recv` user + zfs
            delegation + `backup/torrent` dataset under `zbackup`).
      - [ ] Deploy torrent and thinkpad; watch
            `systemctl status backup-push-torrent.service` /
            `journalctl -u backup-push-torrent` for the first real push
            (first run is a full send — expect it to take longer and
            transfer more than subsequent hourly incrementals).
      - [ ] On homelab, confirm snapshots are actually landing:
            `zfs list -t snapshot -r zbackup/backup/torrent` and
            `.../thinkpad`.
      - [ ] Confirm the Tailscale-reachability `ExecCondition` behaves
            as intended: stop tailscaled (or disconnect) on thinkpad,
            confirm `backup-push-thinkpad.service` reports as skipped/
            inactive rather than failed, then reconnect and confirm the
            next timer fire (or a manual `systemctl start`) catches up
            immediately (`Persistent = true`).
      - [ ] Sanity-check `zfs-space-guard.timer` on both hosts: manually
            drop a test dataset's free space (or just review the script
            logic against `zpool list -Hpo capacity`) and confirm the
            15%-free trigger and `keepMin = 2` floor behave as expected
            before trusting it under real pressure.
      - [ ] Confirm `systemctl start zfs-emergency-prune.service` works
            as a manual break-glass action on both hosts (dry-run reading
            the script's `zfs destroy` targets first, since it's
            destructive by design).
      - [ ] Once real backups exist, wire
            `myHealthAlerts.backupStaleness` values (already set) into a
            live check — confirm a Discord alert actually fires if a
            target dataset goes stale past 336h, e.g. by temporarily
            lowering the threshold for a smoke test.

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

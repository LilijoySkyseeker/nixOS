# TODO / plans & goals

Running log of plans and goals discussed for this repo, so they can be
referenced across sessions. Not a replacement for host-specific docs
(e.g. `hosts/*/README.md`) — this is for higher-level, cross-host
or longer-horizon items.

Convention: add a dated entry when a new plan/goal is agreed on; check
items off or move them to "Done" as they land; prune stale/abandoned
items rather than letting them rot.

## Active

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
      - [ ] Still needed: connect from an actual Android SMB client
            (Material Files / Solid Explorer / CX File Explorer) to
            `homelab.<tailnet>.ts.net` or the Tailscale IP, port 445 —
            `smbclient` proves the server side works correctly, but the
            real app/UI on-device is still unverified.
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

- [ ] **2026-08-20: deploy the wg0 IPv4-endpoint fix to homelab, then
      verify it survives a real IPv6 address rotation.**
      `hosts/homelab/configuration.nix`'s wg0 peer now points at vps's
      stable IPv4 (`137.184.45.18:51820`) instead of vps's IPv6
      literal, fixing a bug where the tunnel died silently whenever
      homelab's RFC4941 privacy IPv6 address rotated (confirmed live:
      0% ping both directions despite `persistentKeepalive`). Merged to
      master, **not yet deployed** — the real homelab host is still
      running the old (broken) config until this switch happens.
      Deploy plan: `nixos-rebuild switch --flake .#homelab` (or via
      whatever push-deploy path is standard now), then confirm `wg show
      wg0` shows a fresh handshake and jellyfin/minecraft/factorio are
      reachable through it. Testing (do after deploy, not before): the
      fix itself is straightforward (IPv4 doesn't rotate), but hasn't
      been watched through an actual homelab IPv6 address rotation yet
      — confirm `wg show wg0` keeps a fresh handshake and
      jellyfin/minecraft/factorio stay reachable across the next one or
      two rotations (homelab's privacy addresses appear to rotate on
      the order of hours-to-a-day, based on the two different addresses
      already observed during this investigation).

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

- [ ] **2026-08-20: `docs/procedures/backup-restore.md` needs real
      content once the `zbackup` restructuring lands.** Currently a
      placeholder. `docs/architecture.md` now documents the two
      backup mechanisms that exist today (restic->Backblaze via
      rclone; sanoid/syncoid->`zbackup`), but restore steps were
      deliberately deferred — coordinated with the `zfs backups plus
      spaceguard` session, which is mid-restructure: renaming the
      `zbackup` dataset layout to a flat `zbackup/backup/<host>/<subdir>`
      convention and adding syncoid push-backups from `torrent`/
      `thinkpad` over Tailscale via a new scoped backup-recv/
      backup-push user pair. A separate `zfs-pool-recovery-restore`
      branch is also refactoring the inline `services.sanoid` block on
      homelab into a new `modules/nixos/zfs-snapshots.nix` module
      (same behavior, different file). Needs: once both land, write
      `docs/procedures/backup-restore.md` for real (restic restore via
      `restic-backblazeWeekly` wrapper; syncoid/zfs-receive restore
      from `zbackup`), and update `docs/architecture.md`'s Backups
      section to describe the final dataset layout instead of the
      current in-flux one.

- [ ] **2026-08-20: build+switch thinkpad and torrent after the
      dendritic migration** (see entry above) — only `vps`/`homelab`
      were fully built during the migration; `thinkpad`/`torrent` were
      evaluated only. Build (not switch) both before relying on them,
      then switch when ready.

- [ ] **2026-08-18: homelab's weekly restic-to-Backblaze backup has no
      safeguard against `myAutoUpdate`'s Thursday auto-switch killing
      a mid-run backup.** During a full-bucket reset/re-test of the
      backup (see this session), we found homelab runs
      `nixos-rebuild switch` every Thursday 03:00 via `myAutoUpdate`
      (`hosts/homelab/configuration.nix`), and `switch-to-configuration`
      restarts any systemd unit whose definition changed — including
      `restic-backups-backblazeWeekly.service` (Type=oneshot,
      `TimeoutStartSec=1w`) if the restic module, its overrides, or a
      shared dep like `pkgs-stable` changes. A run in progress (backups
      have taken multiple days for the ~2.9TiB dataset) would be killed
      with no resumption. Worked around this time by manually pausing
      the `nixos-upgrade` timer for the duration of the manual run.
      Needs a permanent fix: either make the backup service resilient
      to being interrupted/restarted (state/resume support, or a
      `ConditionXXX`/lock that defers an auto-switch while a backup is
      active), or have `myAutoUpdate` skip switching while
      `restic-backups-backblazeWeekly.service` is active.

- [ ] **2026-08-18: homelab backup/replication stack has several
      compounding risks if the box is powered off for an extended
      period (over a month), surfaced while reasoning through the full
      backup reset/re-test.** Grouped as one item since they share a
      root cause (everything below is `Persistent = true` and fires
      its one missed catch-up run right at boot, all at once):
      - **Boot-time contention pile-up**: sanoid (minutely), syncoid
        (hourly), the restic weekly timer, and both `myAutoUpdate`
        timers (fetch + switch) are all `Persistent = true` — after a
        long outage they all queue their catch-up run around the same
        time on boot, recreating (likely worse, since concentrated
        instead of spread out) the resource-contention throttling
        diagnosed live during this session (4 cores, load average
        12-14, multiple ZFS-heavy jobs + restic upload all competing).
      - **Compounds directly with the item above**: if the catch-up
        `nixos-rebuild switch` lands while the catch-up restic backup
        is still mid-run, the service gets killed and restarts from
        scratch — more likely right after a long outage than during
        normal weekly operation, since both are now racing on the same
        boot instead of being naturally staggered.
      - **Self-inflicted history loss from the `--keep-daily 2`
        retention** we set this session (disaster-recovery-only, not
        versioning, per explicit choice): once the first post-outage
        backup succeeds, its prune step drops straight to the 2 most
        recent backup-days, permanently discarding all pre-outage B2
        history at that point. Intentional given the retention
        philosophy, but worth having a documented awareness of before
        it surprises someone during an actual recovery.
      - **Syncoid resume-base pruning, same failure mode as before,
        longer fuse**: the widened retention from `fbf547f` (hourly
        168/7d, daily 14) gives a stuck syncoid target ~1-2 weeks of
        slack now instead of ~1 day, but a target stuck that long
        post-boot (plausible given the contention point above) would
        still hit the exact "resume base pruned, forced full reseed"
        failure that caused this whole reset project.
      - **Unverified**: whether the B2 application key
        (`homelab_backblaze_rclone_config` secret) has an expiration
        date set on Backblaze's side. Couldn't check without exposing
        the secret's contents; confirm on the B2 web console if this
        needs certainty.
      Needs: stagger/serialize the catch-up timers (e.g. `RandomizedDelaySec`
      spread, or explicit ordering) so they don't all fire at once on
      boot, and decide whether the auto-update-vs-backup conflict fix
      above should also gate against this boot-time race specifically.

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


## Done


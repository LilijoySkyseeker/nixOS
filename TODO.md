# TODO / plans & goals

Running log of plans and goals discussed for this repo, so they can be
referenced across sessions. Not a replacement for host-specific docs
(e.g. `hosts/*/README.md`) — this is for higher-level, cross-host
or longer-horizon items.

Convention: add a dated entry when a new plan/goal is agreed on; check
items off or move them to "Done" as they land; prune stale/abandoned
items rather than letting them rot.

## Active

- [ ] **2026-08-18: full-disk encryption + Secure Boot + TPM2 auto-unlock**
      **+ impermanence rollout** for homelab, thinkpad, torrent (vps
      excluded from FDE/SB — DO droplet is BIOS-only/no vTPM, and the
      provider already has raw disk access, so it has negligible
      security value there; vps is already impermanent). Threat model
      for the FDE/SB half: physical theft of a machine/drive, plus
      evil-maid/tamper resistance, on top of general best-practice
      hardening.

      Two independent phases, since they have very different retrofit
      costs:

      **Phase 1 — Secure Boot via lanzaboote (in-place, no reinstall).**
      All three hosts already install in UEFI mode with
      `boot.loader.systemd-boot.enable` (`profiles/default.nix:189`),
      so this is a bootloader swap: `boot.lanzaboote.enable = true`,
      `boot.loader.systemd-boot.enable = false`, `sbctl create-keys` +
      enroll (ideally in firmware Setup Mode), rebuild. No disko/disk
      changes. nix-community's lanzaboote is NLnet-funded and active,
      but the NixOS wiki still flags sharp edges on stable channels —
      treat as beta, test on thinkpad first (easiest to physically
      recover if boot breaks) before homelab/torrent.

      **Phase 2 — LUKS + TPM2 auto-unlock on zroot (requires
      reinstall/reprovision).** disko partitions the raw disk at
      install time; there's no supported in-place "encrypt zroot"
      path. Plan is: back up `/persist` + secrets + any zdata/zbackup
      contents (homelab), wipe, reprovision via disko/nixos-anywhere
      with a LUKS layer under zroot (`boot.initrd.luks.devices` +
      `systemd-cryptenroll ... tpm2-device=auto`), restore. ZFS native
      encryption was considered and rejected for the auto-unlock goal —
      it has no built-in TPM2 path; getting there means maintaining a
      bespoke initrd unit, vs. LUKS+systemd-cryptenroll being an
      upstream-supported NixOS module. LUKS sits transparently under
      ZFS/disko, so it doesn't complicate homelab's existing
      rollback-to-blank-snapshot impermanence setup.

      Since this reinstall is already mandatory, roll thinkpad and
      torrent onto impermanence in the same pass — root/base system
      config goes ephemeral (rolled back to a blank snapshot every
      boot), **home directories stay persistent, not wiped**. Both
      hosts already partition `local/home` as a separate ZFS dataset
      from `local/root` in their current `disko.nix`, so this is a
      clean retrofit of homelab's existing pattern rather than a new
      one: add a `local/state` dataset (mirroring homelab's
      `/nix/state`) for `environment.persistence` — `/etc/nixos`,
      `/var/log`, service state dirs (sanoid, tailscale, docker if
      used, etc.), `/etc/machine-id`, and the SSH host key/age identity
      files needed to avoid the sops chicken-and-egg problem on every
      boot, not just on reinstall — plus the initrd `zfs rollback -r
      zroot/local/root@blank` unit homelab already runs. homelab is
      already on impermanence, so no change needed there beyond
      whatever Phase 2 does to its layout. vps is already impermanent
      too (tmpfs root) and out of scope per Phase 1/2 above.

      Must do Phase 1 before Phase 2 on a given host: the TPM2 unseal
      policy should bind to PCR 7 (Secure Boot state) and the UKI/boot
      measurements, not just PCR sealing in isolation — otherwise an
      attacker can swap the boot chain and the TPM will still happily
      unseal the disk key (see oddlama's writeup on naive TPM2
      auto-unlock bypasses). Without Secure Boot first, "auto-unlock"
      only defends against a stolen drive read on another machine, not
      against a tampered bootloader on the machine itself.

      Decided with user: homelab's zdata/zbackup HDD pools get
      encrypted too, not just zroot — same theft threat model applies
      to bulk storage. Phase 2 reinstall order is by disruption level:
      thinkpad (secondary laptop) → torrent (primary desktop) →
      homelab (server, most disruptive/highest stakes, most disks/
      pools to redo) last, once the LUKS+TPM2 disko recipe is proven
      on the other two.

      **Phase 3 — recovery plan (sketch only, needs full
      architecting before Phase 2 ships on any host).** The bullets
      below are the researched shape of the plan — mechanisms,
      ordering, what to escrow — not yet a runbook someone could follow
      under stress. Still needed: an actual step-by-step per-host
      recovery doc (likely `hosts/<host>/RECOVERY.md`, mirroring the
      README convention already used for setup docs) with exact
      commands, not prose; a decision on where the escrowed LUKS
      recovery keyfile and sbctl PKI backups physically live (this
      session only named the categories — paper backup, password
      manager, offline media — not which one, or where); and a dry run
      of the full bare-metal sequence against a spare/test disk (or a
      VM, per this repo's existing "test remote deploys in a VM first"
      convention) before it's trusted as the real plan for a live host.
      Do this architecting pass before Phase 2 reinstalls anything, not
      after — the recovery path needs to exist and be verified before
      the failure modes it's covering for become possible.

      FDE+TPM2 can end up *less*
      recoverable than plaintext ZFS if the failure modes aren't
      planned for up front (locked LUKS → can't reach the pool → can't
      reach sops secrets → can't even rebuild the flake for that host).
      Assumes thinkpad/torrent get syncoid backups landing on homelab's
      backup drives (`zbackup/backup/thinkpad`, `zbackup/backup/legion`
      — dataset stubs already exist in `hosts/homelab/disko.nix`, wiring
      is being architected separately) before Phase 2 lands on them —
      Phase 2 shouldn't ship on a host with no backup destination yet.
      Note this makes their recovery path dependent on homelab's own
      zbackup pool surviving, not offsite-independent like homelab's
      restic-to-B2 job — worth revisiting whether thinkpad/torrent
      should eventually get their own offsite leg too, separate from
      this FDE effort.

      - *Software failure (bad rebuild, corrupted root, ransomware-ish
        scenario)*: unaffected by encryption. homelab already rolls
        zroot back to a blank snapshot every boot (impermanence); once
        the Phase 2 reinstall lands impermanence on thinkpad/torrent
        too, all three hosts get the same blank-snapshot rollback,
        plus NixOS generation rollback via the (post-Phase-1) signed
        boot entries. Home directories are never touched by the
        rollback on any host. No new recovery step needed here beyond
        re-signing/re-sealing if a rollback changes measured boot state
        (see PCR note below).

      - *TPM2 unseal failure* (motherboard swap, TPM cleared, BIOS
        update shifts PCR values, TPM dies): never enroll a TPM2-only
        LUKS slot — always keep a second passphrase/keyfile slot
        (`systemd-cryptenroll` supports multiple slots per device) so
        failure just falls back to a manual prompt instead of a
        lockout. That recovery secret must NOT be sops-encrypted with
        the host's own key (chicken-and-egg — it's the disk you can't
        get into yet); escrow it instead as a printed/paper copy plus a
        password-manager entry, or a keyfile on separate offline
        encrypted media. Bind TPM2 sealing to a minimal PCR set (0, 2,
        7, 11/12) — fewer PCRs means fewer false-positive lockouts from
        routine firmware/kernel churn — and proactively
        `systemd-cryptenroll --wipe-slot=tpm2` + re-enroll after any
        change expected to shift PCRs (kernel bump, lanzaboote update,
        firmware update), rather than discovering it at boot.

      - *Secure Boot key loss*: recoverable, not a lockout — regenerate
        with `sbctl create-keys`, re-enroll in firmware, re-sign the
        current boot chain, then re-run `systemd-cryptenroll` to reseal
        TPM2 against the new PCR7 values (one boot needs the passphrase
        fallback in between). Add sbctl's key directory
        (`/var/lib/sbctl` or `/etc/secureboot`, whichever this repo's
        module resolves to) to each host's restic/persistence paths so
        it isn't a single point of loss.

      - *Hardware failure / full reinstall*: boot the existing rescue
        ISO (`hosts/isoimage`, already carries disko/zfs/restic/rclone)
        → disko re-provision from the flake with the LUKS layer set to
        a **static passphrase/keyfile** at provision time (disko's LUKS
        `content.settings` supports this) — no TPM dependency yet →
        boot once, confirm `sbctl status`/lanzaboote enrolled clean on
        the (repaired or replacement) hardware → only then
        `systemd-cryptenroll --tpm2-device=auto` to add the TPM2 slot,
        sealing against a confirmed-good state → `zfs receive` to
        repopulate data: from homelab's own zbackup/restic-to-B2 for
        homelab itself, or from homelab's `zbackup/backup/thinkpad`
        and `zbackup/backup/legion` datasets for those two hosts (their
        only backup destination — see the offsite-gap note above). The
        rescue ISO can't
        `zpool import` a pool sitting inside a still-locked LUKS
        container, so LUKS must be unlocked manually (passphrase) as
        the first step of any bare-metal recovery — the ISO should
        carry or document access to the escrowed recovery keyfile
        itself (encrypted to an offline/paper key, never to sops) so
        the rescue flow never depends on secrets that live only inside
        the volume it's trying to open.

      - *sops/age chicken-and-egg on rebuild*: sops-nix decrypts using
        an age identity derived from `/etc/ssh/ssh_host_ed25519_key`
        (or the PC profile's generated key), which is regenerated fresh
        on every reinstall unless explicitly preserved — a freshly
        reprovisioned host cannot decrypt its own existing secrets.
        Same pattern already documented for vps (`hosts/vps/README.md`
        step 1): back up the actual host key material (not just note
        that a key exists) so it can be restored to the new install
        before the first `nixos-rebuild switch` that references
        secrets; if the old key is truly gone, fall back to enrolling a
        recovery/admin age key in `.sops.yaml` and re-encrypting from a
        machine that still holds decryptable copies, then rotate.
        Should extend the existing per-host key backup practice to
        thinkpad/torrent/homelab explicitly once Phase 2 is scheduled,
        not assume it's already covered.

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

# Done

Completed items moved out of `TODO.md`'s Active section once landed, kept
for historical record rather than deleted outright. Entries are otherwise
unedited from their original `TODO.md` text — only a closing note is
appended once something lands, dated separately from the original entry.

Newest first.

- [x] **2026-08-25: reorganize `modules/home-manager/tooling.nix` — it's
      wholesale-applied to every server host's root profile via
      `modules/profiles/server.nix`, but mixes universal CLI tools (fzf,
      zoxide, git, helix, bat, eza, fish) in with desktop-only GUI apps:
      `services.kdeconnect` (phone-sync daemon), `programs.obs-studio`
      (screen recording), `programs.obsidian` (notes app), and
      `programs.firefox` (a whole browser) — all pulled onto headless
      servers for no reason. Noticed live via `nix why-depends` while
      sanity-checking vps's actual built closure during its reinstall
      (traced kdeconnect-kde/qtspeech/ktextwidgets to exactly this path);
      confirmed with the user this is a real problem worth fixing, not
      just a decision point — applies identically to homelab, predates
      this session's changes. Fix direction: split `tooling.nix` into a
      CLI-only piece (safe for `server.nix` to keep using) and a
      desktop-GUI piece (kdeconnect/obs-studio/obsidian/firefox, kept
      only in `modules/profiles/PC.nix`'s home-manager import list).
      Not done as part of the vps reinstall itself — real refactor
      across the fleet, needs its own branch and a rebuild-check on
      every affected host (server.nix hosts *and* PC.nix hosts) before
      merging.

      **2026-08-26: landed.** `modules/home-manager/tooling.nix` kept the
      CLI-only pieces (helix, git, fzf, zoxide, btop, fish, bat, eza) and
      dropped the four GUI ones; a new `modules/home-manager/
      tooling-desktop.nix` (registers as `flake.modules.homeManager.
      "tooling-desktop"`) holds `services.kdeconnect`/`programs.
      obs-studio`/`programs.obsidian`/`programs.firefox`, wired only into
      `modules/profiles/PC.nix`'s `home-manager.users.lilijoy.imports`
      list. `modules/profiles/server.nix` needed no change — it already
      only imported `homeManagerModules.tooling`, so server hosts
      automatically stop getting the GUI apps once `tooling.nix` itself
      no longer defines them. `nixos-rebuild build` succeeded on all four
      affected hosts (vps, homelab, thinkpad, torrent); confirmed with
      `nix path-info -r` against vps's and thinkpad's real built
      `system.build.toplevel` that obsidian/obs-studio/firefox/kdeconnect
      are now absent from vps's closure while still present in
      thinkpad's (a PC host) — the actual bug this item was about is
      fixed, not just the wiring. Not yet deployed to any host.

- [x] **2026-08-25: full vps reinstall via nixos-anywhere, automated and
      documented** (branch `worktree-vps-reinstall`, PR #13). Follow-up
      to the vps-bricked entry below — declared unrecoverable rather
      than chasing the boot race further. Added `scripts/bootstrap-
      host.sh <host> <target-ip|--vm-test>`, generalizing the sops/
      tailscale chicken-and-egg (pre-generate host SSH key outside the
      repo, enroll its age key in `.sops.yaml`, `sops updatekeys`)
      followed by the `nixos-anywhere` invocation itself — see
      `hosts/vps/README.md`'s "Reinstall" section for the worked
      example, including the `--persist-root /persist` flag
      impermanence hosts need (a key written to plain `/etc/ssh`
      vanishes on the first real boot on a tmpfs-root host) and why the
      new tailscale key has to be set *before* the install runs, not
      after (the fresh box needs a working key the moment it boots).
      Tried `--vm-test` before touching the real droplet; hit two hard
      nixos-anywhere limits documented in `docs/procedures/
      vm-testing.md` (hardcoded test-disk size too small for vps's
      fixed 18G `nix` partition, and it rejects `--extra-files`
      outright) — user's call was to proceed to the real install given
      this exact disko layout's track record plus a clean local build
      and `system.build.vm` boot, rather than build a bespoke rehearsal
      harness. Droplet recreated 2026-08-25 (user, DO dashboard — no
      `doctl`/API token in this repo to automate it) — a reserved
      IPv4+IPv6 pair carried over unchanged, so the octodns.nix/
      homelab-wireguard IP references needed no update after all. New
      tailscale key set. First two real `nixos-anywhere` attempts hit
      script bugs (a stray `--` separator token passed straight through
      to `nixos-anywhere`, since fixed) and then `kexec` getting
      OOM-killed on the stock 1GB droplet — twice, once with no swap
      and again with a 1G swapfile added, the second time almost
      instantly (`anon-rss:0kB`), consistent with `kexec_load` needing
      genuinely free kernel-pinned physical RAM that swap can't supply.
      Dropped the swap workaround from the script; the real fix (user's
      call) is a temporary RAM-tier resize before installing, resized
      back down after — documented in `hosts/vps/README.md` and
      `docs/procedures/new-host.md` as a real, recurring step for this
      host, not a one-off. Left before calling this done: user resizes
      the droplet up, retry the install, confirm crowdsec/bouncer/
      tailscaled-autoconnect/caddy/fail2ban are healthy, resize back
      down, and exercise a real reboot to confirm the boot-race fixes
      actually hold against DigitalOcean's real network-arming delay.

      **Landed 2026-08-26:** droplet DO-dashboard-Reset once more, and
      `nixos-anywhere` completed cleanly again — but the box still
      never came up on the network. Root-caused via a rescue-ISO
      journal read to a second, unrelated bug: DigitalOcean's public
      NIC needs the static IP cloud-init reads from its ConfigDrive
      datasource, but NixOS's default scripted `dhcpcd` (from
      `networking.useDHCP = true`) ran its own blind DHCP instead, got
      no lease, and fell back to a self-assigned link-local address —
      cloud-init's own rendered systemd-networkd config was never
      consumed because `services.cloud-init.network.enable` was never
      set. Fixed: `networking.useNetworkd = true` +
      `networking.useDHCP = false` +
      `services.cloud-init.network.enable = true`; confirmed live via
      `networkctl status ens3` showing
      `/etc/systemd/network/10-cloud-init-ens3.network` bound and the
      real public IP routable. Also found and fixed in the same pass:
      cloud-init's own package ships a `05_logging.cfg` default
      (console at WARNING, full DEBUG to the log file) that NixOS's
      cloud-init module doesn't install, so every DEBUG line — hundreds
      per boot — was hitting `StandardOutput=journal+console` on all
      four cloud-init units and flooding the DO recovery console;
      installed the upstream default declaratively. Also confirmed:
      `nixos-anywhere` cannot target DigitalOcean's recovery/rescue
      ISO itself (tested, documented in `hosts/vps/README.md`) — it
      needs the droplet booted to a normal OS. Resized back down to
      `DO-Regular`/1GB, exercised a real reboot: zero failed units, all
      core services active, tailscale reconnected as the same device —
      the boot-race fixes from PR #12 (see the fail2ban entry below)
      confirmed holding on this fresh install too. PR #13 merged.

- [x] **2026-08-25: add fail2ban to vps, defaulting to an immediate ban
      for any connection attempt against a non-present/non-listening
      service.** Requested by the user alongside the CrowdSec bouncer
      credential fix (landed 2026-08-25, see `docs/DONE.md`) — a
      complementary, simpler layer: rather than CrowdSec's
      scenario-based detection, fail2ban here should treat any probe of
      a port/service vps doesn't actually offer as inherently hostile
      and ban on first sight rather than after a threshold.

      **2026-08-25: scoped down after live review of vps** (see
      `worktree-vps-probe-visibility`/branch
      `worktree-vps-probe-visibility`, prerequisite logging fixes
      already landed there — closed-port TCP-scan logging
      (`networking.firewall.logRefusedConnections`, was off, is TCP-SYN
      only — closed *UDP* ports remain unlogged, no cheap fix found),
      a Caddy `:80` catch-all vhost for unmatched-Host probes, and
      reusing CrowdSec's own `crowdsec-blacklists-0` ipset to protect
      the DNAT'd game ports from *already-banned* IPs — see
      `docs/DONE.md` once that lands):
      - **fail2ban should own**: (1) the closed-TCP-port-scan jail on
        `logRefusedConnections`'s kernel log (`journalctl -k`,
        `refused connection: ` prefix, TCP SYN only) — CrowdSec has
        zero visibility here, its acquisitions only read
        `sshd.service`/`caddy.service` journal units, never kernel
        logs; (2) a jail on the game-port hashlimit DROP rules once
        those are logged (not done yet — the raw-table hashlimit rules
        in `hosts/vps/configuration.nix` don't log at all currently,
        and logging every dropped packet at flood volume — up to
        ~2000pps for the factorio rules — would flood the journal on a
        1GB box; needs a coarse/sampled LOG rule design, not a
        naive one, before fail2ban has anything to jail on). Both are
        "nothing legitimate lives here" cases — zero-threshold
        (`maxretry=1`) ban carries no real false-positive risk.
      - **fail2ban should NOT duplicate the `:80` catch-all.** CrowdSec's
        Caddy acquisition filters on `_SYSTEMD_UNIT=caddy.service` (the
        whole unit's journal, not a per-vhost path), so the catch-all's
        access-log lines already flow through the existing
        `crowdsecurity/caddy` scenarios for free, no new wiring needed.
        That's signature-based, not zero-threshold, but a stray
        unmatched-Host hit isn't inherently hostile the way a
        closed-port probe or game-port drop is — a zero-threshold jail
        there would risk banning innocent traffic CrowdSec correctly
        leaves alone.
      - **Ban-mechanism choice still open**: fail2ban's own iptables
        rules (independent of CrowdSec, standard default action) vs.
        having fail2ban's ban action run `cscli decisions add` so
        there's one unified ban list instead of two independent
        mechanisms on the box. Not decided yet.
      Not started (the prerequisite logging/ipset-reuse work above is
      build-tested but not yet deployed as of this note).

      **2026-08-25/26: closed-TCP-port-scan jail implemented** (branch
      `worktree-fail2ban-vps`, `hosts/vps/configuration.nix`,
      build-tested via `nixos-rebuild build`, not yet deployed):
      - **Ban mechanism decided: `cscli decisions add`/`decisions delete`**
        (user's call) — a custom `environment.etc."fail2ban/action.d/
        cscli.conf"` action, so bans land in CrowdSec's own decision
        list/ipset (`crowdsec-blacklists-0`) instead of a second
        independent mechanism. `<ip>`/`<bantime>`/`<name>` are standard
        fail2ban action tags, no `[Init]` boilerplate needed; verified
        `cscli decisions add --duration` accepts Go-duration strings
        (`<bantime>s` is valid — Go's `ParseDuration` accepts a bare `s`
        unit) via `cscli decisions add --help`/`delete --help` against
        the pinned nixpkgs crowdsec build.
      - **`jails.sshd.enabled = false;`** — the NixOS fail2ban module
        auto-adds a default `sshd` jail (plain iptables action) the
        moment `services.openssh.enable = true`, independent of anything
        else configured. Left alone, that's a second, uncoordinated ban
        mechanism for exactly what `crowdsecurity/sshd` already covers.
        Caught by reading `nixos/modules/services/security/fail2ban.nix`
        directly, not assumed.
      - **Filter**: `journalmatch = "_TRANSPORT=kernel"`,
        `failregex = ^refused connection: .*\sSRC=<HOST>\s` — matches
        the exact `--log-prefix` string in `firewall-iptables.nix`
        (vps uses the iptables backend; `networking.nftables.enable`
        defaults false and isn't set here). Verified against a synthetic
        log line with `fail2ban-regex`: 1/1 matched.
      - **Progressive/escalating bans, capped not permanent** (user's
        call, after confirming with CrowdSec no-longer-guessing): base
        `4h`, roughly quadrupling per repeat offense, capped at `90d`
        (`4h, 16h, 64h, 256h, 1024h, then 2160h`) — deliberately capped,
        not literal-forever, since a shared/dynamic IP (residential ISP
        reassignment, CGNAT, VPN exit) can later belong to someone
        unrelated to the original scanner. Two independent mechanisms,
        tuned to produce the *same* curve:
        - **fail2ban**: `bantime-increment.multipliers =
          "1 4 16 64 256 1024"` against a `4h` jail `bantime`, capped by
          `bantime-increment.maxtime = "90d"`. Confirmed in fail2ban's
          own `server/jail.py` that `multipliers` indexes a fixed table
          against the jail's *static* configured bantime
          (`ban.Time * banFactor * multipliers[ban.Count]`), not
          compounding on the previous ban — needed to get the curve to
          line up with CrowdSec's below rather than guessing.
        - **CrowdSec**: `services.crowdsec.localConfig.profiles`
          overridden (the option has no merge semantics — both of the
          module's default profiles, `default_ip_remediation` and
          `default_range_remediation`, had to be reproduced verbatim,
          confirmed via the module's own `default =` in
          `crowdsec.nix`) adding
          `duration_expr = "Sprintf('%dh', int(min(4 **
          (GetDecisionsCount(Alert.GetValue()) + 1), 2160)))"`.
          **Only applies to CrowdSec's own scenario-generated alerts**
          — traced in CrowdSec's `pkg/apiserver/controllers/v1/
          alerts.go`: alerts arriving with a decision already attached
          (which is what `cscli decisions add` sends, confirmed in
          `cmd/crowdsec-cli/clidecision/decisions.go`) run through
          profile matching for notification purposes only, and the
          handler explicitly discards the profile-computed decision,
          keeping the manually-specified duration untouched. So this
          governs CrowdSec's own sshd/caddy scenario bans; it does
          *not* retroactively escalate fail2ban's cscli-triggered bans
          — that's what the fail2ban-side `bantime-increment` above is
          for. Verified `min`/`int`/`**` are real expr-lang builtins
          (`expr-lang/expr`'s `builtin.go`/`parser/operator/
          operator.go`) and `GetDecisionsCount(value)` counts all
          historical decisions for that IP regardless of expiry
          (`pkg/exprhelpers/helpers.go`) — cumulative repeat-offender
          memory, not just currently-active bans. Config-tested clean
          with the real `crowdsec -t` binary against a sandboxed config
          (`duration_expr` compiles at profile-load time, would have
          failed loudly here if malformed).
      - **`/var/lib/fail2ban` added to vps's impermanence persistence
        list** — without it, fail2ban's ban-history sqlite db (which
        `bantime-increment` reads to know each IP's prior ban count)
        resets to zero every reboot, since vps's root is tmpfs. Runs as
        root (no `DynamicUser`), so a bare string entry, no user/group/
        mode needed.
      - **Still not done**: the game-port hashlimit jail (blocked on the
        same sampled-logging-design gap noted above — unchanged by this
        session).

      **2026-08-25/26: VM-tested** (`nixos-rebuild build-vm --flake .#vps`,
      per `docs/procedures/vm-testing.md` — booted twice, non-interactively,
      via a scripted stdin feed since driving a live console isn't
      practical in this tool environment; a `virtualisation.vmVariant`
      autologin override was used locally to get a shell at all, since the
      real host is SSH-pubkey-only with no console password — never
      committed, reverted after):
      - fail2ban's own log output **confirms the intended config actually
        takes effect at runtime**, not just that it renders correctly:
        `maxRetry: 1`, `findtime: 86400`, `banTime: 14400` (4h),
        `Set banTime.increment = True`,
        `Set banTime.multipliers = 1 4 16 64 256 1024`,
        `Set banTime.maxtime = 90d`, and
        `[vps-closed-port-scan] Jail is in operation now (process new
        journal entries)`. No `[FAILED]` units across two separate boots;
        `crowdsec`, `crowdsec-firewall-bouncer`, and
        `crowdsec-firewall-bouncer-register` all reached active/running
        (crowdsec's first-boot hub bootstrap — `cscli collections install`
        — genuinely downloads from `hub-data.crowdsec.net` over the VM's
        NAT and takes real wall-clock time, ~30–90s+ under this sandbox's
        TCG emulation with no KVM available).
      - **Found a real footgun for anyone testing this by hand**: bare
        `cscli` on `PATH` is not the raw crowdsec binary — the NixOS
        module wraps it (`pkgs.writeShellScriptBin "cscli"` in
        `environment.systemPackages`, confirmed in nixpkgs'
        `crowdsec.nix`) with a check that aborts
        (`Aborting, cscli must be run as user \`crowdsec\`!`) unless
        invoked as the `crowdsec` user, or re-execs via `sudo -u crowdsec`
        if `security.sudo.enable`. Hit this firsthand typing bare `cscli
        decisions list` as root at the VM console. **Does not affect
        fail2ban's action** — `environment.etc."fail2ban/action.d/
        cscli.conf"` calls the raw unwrapped binary by absolute store
        path (`${config.services.crowdsec.package}/bin/cscli`), bypassing
        this wrapper and `PATH` lookup entirely — but worth remembering
        when checking this by hand on vps: use the absolute path (or
        `sudo -u crowdsec cscli ...` if sudo's enabled), not bare `cscli`
        as root.
      - **Not independently confirmed in the VM**: that the raw-binary
        `cscli decisions add`/`delete` call actually succeeds end-to-end
        against the live local API when run as root (vs. the wrapper's
        `crowdsec` user) — was mid-way through testing this exact
        command when VM testing was stopped in favor of testing live on
        vps instead. Worth checking directly as a first step after
        deploying (or by hand first, at the user's discretion):
        `/nix/store/.../crowdsec-*/bin/cscli decisions add --ip
        203.0.113.99 --duration 14400s --type ban` as root, then
        `cscli decisions list` (as the `crowdsec` user, or same raw path)
        to confirm it landed.
      - **Self-test methodology gap, not a config bug**: connecting from
        the VM to its own IP (not `127.0.0.1`) does not trigger the
        closed-port-scan log line — Linux locally-routes same-host
        traffic over `lo`, bypassing the external-interface REJECT/LOG
        chain entirely. Verifying the actual `refused connection:` log
        line needs a genuinely external-looking connection (a real
        outside host hitting the real vps, or a second VM), not doable
        in a single-VM scratch setup — another reason to confirm this on
        the real box rather than chase it further here.

      **2026-08-26: deployed live to vps, hit a real incident, root-caused,
      two more fixes folded into this same branch/PR as a result.** Deploy
      itself (closure built locally on `torrent`, copied via `nix copy`,
      activated with `switch-to-configuration switch` over root SSH — no
      `nixos-rebuild --target-host`, same net effect) went cleanly:
      `fail2ban.service`'s own startup log confirmed the exact intended
      settings live (`banTime: 14400`, `multipliers = 1 4 16 64 256 1024`,
      `maxtime: 90d`), zero failed units, `cscli decisions add`/`list`
      verified working end-to-end as root against the live local API
      (the thing VM-testing couldn't finish confirming).
      - **Incident: lost SSH access to vps entirely, ~15-20 minutes into
        testing.** Root cause, found by mounting vps's real `/persist`
        from a DigitalOcean rescue ISO and reading CrowdSec's own decision
        database directly (`/var/lib/crowdsec/state/crowdsec.db`, sqlite):
        **CrowdSec's own pre-existing `crowdsecurity/sshd` collection
        banned the admin's own tailscale IP** (`crowdsecurity/ssh-slow-bf`
        scenario) because troubleshooting fired off roughly a dozen
        separate `ssh root@vps '...'` calls in quick succession — a
        pattern indistinguishable, to that scenario, from a slow
        bruteforce attempt. Nothing to do with fail2ban or this PR's
        config; CrowdSec's sshd scenario predates all of it. Explains
        every symptom: SSH died while public :80 kept responding (ban is
        IP-scoped), `tailscale ping` still worked (that check rode an
        IPv6 DERP relay, a different path than the banned IPv4 address),
        and the ban would have survived the next reboot regardless (it
        lives in the persisted decision DB, re-applied by the bouncer on
        every boot) — cleared by deleting the row directly from the
        mounted db before rebooting back to the real system.
      - **Separate, pre-existing bug surfaced by the reboots that
        followed**: two consecutive real reboots both failed to bring up
        tailscale or CrowdSec, confirmed via the persisted journal
        (`journalctl --directory=<mounted-persist>/var/log/journal -b -1`
        etc. from the rescue ISO) — identical failure, down to the
        second, both times: DigitalOcean's hypervisor takes longer to
        actually pass traffic for `ens3` than `network-online.target`
        reports ready (matches the existing `externalInterface` comment
        in `hosts/vps/configuration.nix` about cloud-init network
        arming), so `crowdsec.service`'s `ExecStartPre` (`cscli hub
        update`) and `tailscaled-autoconnect.service` both lose a DNS/
        network race around the ~90s mark and neither ever retries.
        `crowdsec.service` sets `RestartSec=60` upstream in nixpkgs'
        own `crowdsec.nix` but never sets `Restart=` — an incomplete
        no-op, not something we introduced, just never previously
        surfaced since this droplet hadn't been cold-rebooted in 5+
        days. Fixed in this same branch: `Restart=on-failure` on both
        `crowdsec.service` and `crowdsec-firewall-bouncer.service` (the
        latter had no restart policy at all — its failure was a pure
        cascade from crowdsec not being ready), and
        `TimeoutStartSec=300s` on `tailscaled-autoconnect.service`
        (systemd's bare default is 90s). VM-tested only so far (a real
        network-arming delay can't be reproduced in a local VM); the
        real fix confirmation is whichever future vps reboot needs it.
      - **Self-ban prevention added**: a `crowdsec-allowlist-tailnet`
        oneshot unit (`After=`/`Requires=crowdsec.service`,
        `wantedBy = [ "multi-user.target" ]`) runs `cscli allowlists
        create`/`add` to exempt `100.64.0.0/10` (the full tailscale
        CGNAT range) from every CrowdSec decision, not just
        `ssh-slow-bf` — extends the same trust boundary
        `networking.firewall.trustedInterfaces = [ "tailscale0" ]`
        already draws at the packet-filter level to CrowdSec's decision
        engine too, rather than loosening the scenario's own detection
        threshold (which would weaken it against real attackers from the
        actual internet). VM-verified both fresh (`allowlist ... created
        successfully`, `added 1 values`, `cscli allowlists inspect`
        showing `100.64.0.0/10` with `never` expiration) and idempotent
        on a forced restart (`already exists`/`already in allowlist`,
        unit still exits success) — matters since this runs on every
        boot, not just once. `cscli allowlists create` errors on an
        existing name (confirmed in crowdsec's own
        `cliallowlists/allowlists.go`) unlike `add`, which just warns and
        skips known values — hence `|| true` only on the `create` step.
      - Considered and rejected: allowlisting only specific known-good
        IPs (torrent, homelab) instead of the whole tailnet range —
        tighter blast radius but needs upkeep as tailnet membership
        changes; the whole-range choice leans on tailscale's own device
        authorization (ACLs/key approval) as the real access gate, plus
        `sshd`'s existing publickey-only auth meaning there's no password
        to brute-force from inside the mesh regardless.
      - Status as of this note: vps was rebooted (then resized down to
        original specs after a temporary bump) after the incident;
        connectivity (`tailscale ping`, public `:80`) had not yet come
        back at last check. The boot-race and allowlist fixes above are
        build- and VM-tested but **this exact combination has not yet
        been confirmed on a real vps boot**.
      - **2026-08-25: vps declared bricked, unrecoverable as-is.**
        Public `:80`, ICMP, and tailscale SSH all stayed unreachable
        (connection timeouts, not refusals) across several checks over
        an hour with no change — a genuine boot failure, not a repeat of
        the earlier self-ban (that incident left `:80` serving fine).
        User's call: stop chasing this boot and do a full reinstall via
        `nixos-anywhere` instead of another rescue-ISO recovery. PR #12
        merged as-is on the user's explicit instruction rather than
        waiting for live confirmation on the old instance — its fixes
        (this jail, the boot-race retries, the tailnet allowlist) still
        apply to the reinstalled box and get validated by that install
        instead. Follow-up reinstall work tracked in a new branch/
        worktree (see `docs/DONE.md` once landed, or `git branch -a` for
        the in-progress one if not yet landed).

      **Landed 2026-08-26:** confirmed on a real vps boot, via the full
      reinstall tracked in the entry above. One minute after a real
      `reboot` over SSH: zero failed units,
      `crowdsec`/`crowdsec-firewall-bouncer`/`crowdsec-allowlist-tailnet`/
      `fail2ban`/`caddy`/`tailscaled`/`sshd` all active, tailscale
      reconnected as the same device with no duplicate registration.
      The boot-race retry fixes (`Restart=on-failure` on crowdsec and
      the bouncer, `TimeoutStartSec=300s` on `tailscaled-autoconnect`)
      and the tailnet self-ban allowlist both hold.

- [x] **2026-08-25: vps's CrowdSec firewall bouncer has been failing since
      at least 2026-08-20 — pre-existing, found live while deploying the
      auto-updater rearchitect, unrelated to it.** Both
      `crowdsec-firewall-bouncer.service` (`Failed to set up credentials:
      No such file or directory`, step CREDENTIALS) and
      `crowdsec-firewall-bouncer-register.service` (`Bouncer registered
      but API key is not present`) fail on every boot/restart —
      confirmed identical failure text in the journal from 2026-08-20,
      five days before it was noticed. Looks like the bouncer's API key
      credential was never actually provisioned (or was lost/rotated
      out from under it), so `crowdsec-firewall-bouncer-config`'s
      `LoadCredential=`/systemd-creds step has nothing to load. Needs:
      figure out where this bouncer's API key is supposed to come from
      (`crowdsec-firewall-bouncer-register.service`'s own job, a sops
      secret, or a one-time `cscli bouncers add` step) and re-provision
      it. Not currently blocking anything else (the firewall itself
      still runs via `hosts/vps/configuration.nix`'s own iptables rules,
      independent of CrowdSec) but the bouncer's dynamic IP-ban
      enforcement has effectively been off this whole time.
      **Confirmed still failing, unchanged, live-checked 2026-08-25**:
      both services still fail identically (`step CREDENTIALS`/`API key
      is not present`) on vps's current boot.

      **Landed 2026-08-25 (PR #7, plus a live follow-up fix on top):**
      root cause was a persistence split-brain, not a missing/rotated
      key. `crowdsec-firewall-bouncer-register.service`'s state dir
      (`/var/lib/crowdsec-firewall-bouncer-register`, holding
      `api-key.cred`) was never in vps's impermanence persistence list,
      while CrowdSec's own bouncer-registration DB (`/var/lib/crowdsec`)
      was — so every reboot wiped the credential file but left CrowdSec
      still remembering the bouncer as registered, hitting the register
      script's "already registered, but key missing" failure branch
      every time. Fix: add the directory to
      `environment.persistence."/persist".directories`, same
      owner/group/mode pattern as the existing `/var/lib/crowdsec`
      entry. That alone wasn't sufficient, though — the register
      service still declares `StateDirectory =
      "crowdsec-firewall-bouncer-register"`, and systemd's
      `StateDirectory=` mechanism creates `/var/lib/<name>` as a symlink
      into `/var/lib/private/<name>`, which collides with a real bind
      mount at that same path (`mount: not canonical, contains a
      symlink`). Second fix, mirroring the existing workaround already
      in place for `/var/lib/crowdsec`: drop the dir from
      `StateDirectory` entirely and grant write access via
      `ReadWritePaths` instead, so impermanence owns the path outright.

      Verified live end-to-end on vps, not just build-tested: cleared
      the stale `/var/lib/crowdsec-firewall-bouncer-register` symlink +
      its `/var/lib/private` backing dir, cleared the now-orphaned
      bouncer registration from CrowdSec's DB (`cscli bouncers delete`),
      redeployed, and confirmed both
      `crowdsec-firewall-bouncer-register.service` and
      `crowdsec-firewall-bouncer.service` succeed (`systemctl --failed`
      empty), with `api-key.cred` landing in the real `/persist` backing
      store (`/persist/var/lib/crowdsec-firewall-bouncer-register/`,
      confirmed present) — survives the next reboot rather than only
      working until it.

- [x] **2026-08-24: agent error destroyed all source-side snapshots on
      homelab during legacy-snapshot cleanup — recovered via the
      surviving replication cursor bookmark, no full resend needed.**
      While destroying the sanoid-era `autosnap_*` snapshots on
      `zdata/storage/storage`, `zdata/storage/storage-bulk`, and
      `zroot/local/state`, a script computed the oldest/newest
      `autosnap_` snapshot to build a `zfs destroy -r
      dataset@first%last` range, but didn't check that `first`/`last`
      came back empty — the automatic prune ceiling had already
      destroyed them itself moments earlier, once
      `preserveLegacySnapshots=false` deployed. The resulting
      `dataset@%` (empty on both sides) destroyed **every** snapshot on
      all three datasets, not just the legacy ones.

      **No data was actually lost.** The live filesystems were untouched
      (only snapshots were targeted), `zbackup`'s already-replicated
      copies were untouched (destination-side, not in scope), and
      crucially the `#zrepl_CURSOR_*` replication cursor bookmarks
      survived (bookmarks don't depend on their originating snapshot
      still existing). Once the next periodic snap-job cycle produced a
      fresh snapshot, `local-pull` used the surviving bookmarks to send
      small incrementals (tens of MiB) rather than a ~2.6TiB full resend.
      Verified via `zrepl status --mode dump` showing `DONE` with no
      errors on all three filesystems.

      **Lesson:** never build a `zfs destroy` snapshot range from
      shell-variable interpolation without checking both ends are
      non-empty first — `dataset@%` is apparently accepted as "all
      snapshots" rather than erroring.

- [x] **2026-08-24: `zbackup` was never imported at boot — backups had
      been silently dead for ~23h. Fixed declaratively.** Found while
      running the zrepl migration's pre-deploy check. homelab rebooted
      Sun 2026-08-23 10:45 (for this file's USB cable change entry);
      `zbackup`
      did not come back, and every replication job since failed with
      `dataset does not exist`. The pool itself was fine the whole time
      — ONLINE, importable, no data errors.

      **Cause:** nothing in the NixOS config ever imported it. nixpkgs
      only emits a `zfs-import-<pool>.service` for a pool something
      references — a `fileSystems` entry, or `boot.zfs.extraPools`.
      `zdata` gets one implicitly because `/storage` and `/storage-bulk`
      are mountpoints on it. Every `zbackup` dataset is
      `mountpoint = "none"` by design (it is a receive-only target that
      should mount nothing), so nothing referenced the pool and no unit
      was ever generated. Confirmed against the built system, not
      guessed: `ls result/etc/systemd/system/ | grep zfs-import` listed
      only `zdata`. disko is not a fallback here — it emits no import
      units at all (no `extraPools` anywhere in the pinned tree), and
      only creates datasets at *format* time.

      It survived earlier reboots only because someone had imported it
      by hand. That is why this went unnoticed for so long.

      **Fix:** `boot.zfs.extraPools = [ "zbackup" ];` in
      `hosts/homelab/configuration.nix`, on the zrepl migration branch.
      Verified: the rebuilt system now contains
      `zfs-import-zbackup.service`, and the pool imports on a real
      reboot.

      **Worth noting as a class of bug:** a receive-only ZFS pool with
      no mountpoints is invisible to every implicit import mechanism.
      Any future backup-target pool needs `boot.zfs.extraPools`
      explicitly. Also worth asking separately why ~23h of failed
      replication units did not produce an alert that got acted on —
      `myHealthAlerts` does cover failed units, so the gap is likely in
      noticing, not in detecting.

- [x] **2026-08-24: `zrepl.service` could silently stay down after a
      reboot due to a `local-fs.target` race — fixed by relaxing the
      dependency.** Found while rebooting homelab to verify the
      `boot.zfs.extraPools` fix above (the pool import itself worked
      correctly). `storage.mount` failed its first attempt at boot
      (`status=2/INVALIDARGUMENT`, a known ZFS mount-before-ready race
      unrelated to the zbackup fix), which failed `local-fs.target`,
      which `zrepl.service` hard-`Requires=` — that comes from
      **upstream** nixpkgs (`nixos/modules/services/backup/zrepl.nix`),
      not this repo; `modules/nixos/zrepl.nix` had no systemd override at
      all before this fix. The mount self-healed a second later and
      `/storage` was fine, but systemd does not retry a unit whose start
      failed due to a dependency failure — `zrepl.service` sat
      `inactive (dead)` until manually started
      (`systemctl start zrepl.service`). Backups were down ~8 minutes
      this time (16:07-16:15 PDT), same failure class as the entry above
      but much smaller blast radius since it was caught immediately by
      the reboot test rather than discovered ~23h later.

      **Fix:** `modules/nixos/zrepl.nix` now overrides
      `systemd.services.zrepl` with `requires = lib.mkForce [ ];`,
      `wants = [ "local-fs.target" ]; after = [ "local-fs.target" ];`.
      Same ordering in the normal case (zrepl still starts after
      local-fs.target's start job finishes), but a transient dependency
      failure no longer permanently downs the daemon — an unmounted
      dataset just makes that job's own next cycle fail and retry instead
      of the whole daemon never starting. Verified the rendered drop-in
      (`systemd.services.zrepl` override unit) shows `Wants=local-fs.target`
      with no `Requires=` and `After=zfs.target local-fs.target` intact.
      **Reboot-verified, with a caveat.** `nixos-rebuild switch` deployed
      to homelab, then rebooted three times in a row (16:49, 16:52, 16:55
      PDT). All three came up clean: `zrepl.service` active every time,
      `storage.mount`/`storage-bulk.mount` both mounted on the first
      attempt, zero failed units, and `zrepl status` showed
      `local-source`/`local-pull`/`snapshots` all cycling normally with
      snapshots continuing to land right through the reboots. **The
      `storage.mount` race itself did not reproduce in any of the three
      attempts** — it remains a single data point from the previous
      session. So this verifies the fix causes no regression on a clean
      boot, and confirms by construction (inspected the live unit via
      `systemctl show zrepl.service`: `Wants=local-fs.target`,
      `After=local-fs.target`, `local-fs.target` no longer in
      `Requires=`) that a dependency failure can no longer abort zrepl's
      start job — but does not directly observe zrepl surviving a live
      `storage.mount` failure, since none occurred to survive.

      **Still open, deliberately not fixed:** why `storage.mount` races
      at all (still only one data point total, now with three
      non-reproductions alongside it — looks more intermittent than
      reliably reproducible; does `storage-bulk.mount` share the root
      cause?). This fix removes the silent-outage symptom without
      touching that underlying race. If it recurs, check
      `systemctl is-active zrepl.service` — it should now come up on its
      own without manual intervention.

      **Moved here 2026-08-25** — these three were already marked `[x]`
      and fully resolved but had been left sitting in `TODO.md`'s Active
      section instead of moved, against this file's own convention.

- [x] **2026-08-19: `octodns-sync.service` failing on homelab —
      transient DNS resolution error.** Found during a log trawl. Job
      failed with `NameResolutionError` trying to reach
      `api.cloudflare.com`. Timer retries hourly so this may self-heal;
      worth confirming it isn't recurring.

      **Confirmed self-healed, 2026-08-25.** Checked the last several
      hours of `octodns-sync.service` runs live: every recent run
      completes cleanly (`INFO Manager sync: 0 total changes`,
      `Deactivated successfully`), no `NameResolutionError` recurrence.
      Whatever the transient resolver hiccup was, it hasn't recurred.

- [x] **2026-08-20: `docs/procedures/backup-restore.md` needs real
      content once the `zbackup` restructuring lands.** Was a placeholder
      — restore steps were deliberately deferred pending the in-flight
      `zbackup` restructuring and a separate `zfs-pool-recovery-restore`
      sanoid-module refactor.

      **Landed.** `docs/procedures/backup-restore.md` is now 140 lines of
      real zrepl-restore content (dataset-path mechanics, clone-based
      file recovery, rollback, full-dataset restore), confirmed live
      2026-08-25. It already self-documents its own remaining gap ("
      written from the mechanics, not yet exercised... tracked in
      `TODO.md`"), which is exactly what `TODO.md`'s still-open "build
      and test a full restore suite" entry covers — no separate action
      needed here.

- [x] **2026-08-20: build+switch thinkpad and torrent after the
      dendritic migration** — only `vps`/`homelab` were fully built
      during the migration; `thinkpad`/`torrent` were evaluated only.

      **Landed.** Confirmed live 2026-08-25: both hosts are running
      freshly-built generations (`nixos-system-torrent-...`, same build
      date/generation as the other hosts) — built and switched multiple
      times since via the zrepl migration and other deploys.

- [x] **2026-08-25: `zfs-space-guard` (`myZfsSpaceGuard`) reviewed,
      tested, and simplified down to what the actual use case needs.**
      Split out of the (now-superseded, see below) `myBackupPush` item's
      checklist since this module is still live and unrelated to that
      item's fate.

      **Reviewed and tested, both automated and manual.** Found and
      fixed a real bug while reviewing: `cap=$(zpool list -Hpo capacity
      $pool)` on a failed/garbage read (bad pool name, exported pool,
      transient hiccup) made the numeric threshold test error out, and
      bash treats a failed `[ ]` as the `if` being false — so the old
      script fell through to the *unconditional prune* branch instead of
      skipping. Reproduced directly: `bash -c 'cap=""; if [ "$cap" -lt
      85 ]; then echo skip; else echo PRUNE; fi'` prints PRUNE. Now
      validates `$cap` is non-empty/numeric first and exits 1 instead of
      falling through. Added `tests/zfs-space-guard.nix`
      (`checks.zfs-space-guard`, `nix build
      .#checks.x86_64-linux.zfs-space-guard`), a permanent runNixOSTest
      covering healthy/pressure/keepMin-floor/zrepl-style-hold-tolerance/
      emergency-prune/this-bug's-regression — all green. Manually
      verified live on torrent (thinkpad skipped — identical setup,
      torrent's testing translates): timer active, journal showed no
      evidence the bug had ever fired for real (real capacity has been
      sitting at 79%, close to the 85% trigger); confirmed the real
      no-op path, then temporarily raised `freeThresholdPercent` to 25 to
      force a real trigger at that capacity, `build`+`switch`+ran it for
      real — pruned `zroot/local/{home,root}` from 30 snapshots down to
      exactly `keepMin`=2 each, then reverted the threshold and switched
      back (clean, byte-identical store path to before). Also ran
      `zfs-emergency-prune.service` for real, down to the single newest
      snapshot per dataset. Confirmed the safety net held throughout:
      homelab's zrepl pull for torrent stayed incremental with no forced
      full-send, replicating the very snapshots taken during/after the
      test.

      **Same day, follow-up: re-examined the actual use case and removed
      the auto-prune half entirely.** The real need is "I downloaded a
      game, disk is nearly full, I delete something to install a
      different one and need that space back *right then*" — not a
      background timer. Capacity-threshold auto-pruning down to a
      keep-newest floor doesn't solve that: ZFS doesn't free a deleted
      file's blocks until every snapshot referencing them is gone, and
      whatever snapshot is newest at delete time was almost always taken
      *before* the delete (zrepl snapshots on its own 5m clock, unrelated
      to when you delete something) — proved this empirically in the VM
      test before removing anything: writing a file, snapshotting it,
      deleting it, then running the old "keep newest 1" emergency-prune
      left real pool space unreclaimed, because the one surviving
      snapshot still held the file.
      Removed `zfs-space-guard.timer`/`.service` and the
      `pool`/`freeThresholdPercent`/`keepMin`/`checkInterval` options
      entirely — dead weight that never solved the actual problem. Kept
      and repointed `zfs-emergency-prune.service`: now destroys every
      local snapshot except one named exactly `@blank` (the impermanence
      rollback point disko creates once at install), instead of "keep
      the newest one" — since every host is expected to end up on
      impermanence, `@blank` is the one snapshot that must never go, and
      destroying everything else guarantees full reclaim regardless of
      snapshot timing. On a host without `@blank` yet (torrent — see the
      impermanence migration item), this destroys everything, which is
      the documented fallback, not a bug. `tests/zfs-space-guard.nix`
      rewritten to match (blank-preservation + real space-reclaim +
      no-blank-fallback + hold-tolerance); host configs on torrent and
      thinkpad updated to drop the removed options; both hosts build
      clean.

- [x] **2026-08-21: torrent's initial full backup send to homelab is
      throughput-limited to ~20-40MB/s — root-caused while it was
      in progress. RESOLVED 2026-08-23 in hardware.**

      **Resolution: the enclosure's USB cable was replaced.** All four
      drives now enumerate at **5000 Mbps (USB 3.0 SuperSpeed)** on bus
      2 behind the ASMedia ASM107x hub, up from 480 Mbps — confirmed
      2026-08-24 via `/sys/bus/usb/devices/*/speed` showing `5000` for
      all four `TerraMaster TDAS` entries. Cause #2's fault class is
      gone with it: **zero** `uas_eh_*` / `stat urb: status -71` events
      across the 23h since, versus the recurring multi-drive faults
      documented below, and `zpool status -x` reports all pools
      healthy. That single change addresses causes #1, #2 and #4 —
      exactly as the "if/when revisited" note below predicted. Cause #3
      (sanoid's minutely recursive walk) is moot: the zrepl migration
      removes sanoid entirely.

      **Measured 2026-08-24 13:45 under real load** (homelab's first
      zrepl local replication, ~1.62T transferred): `zpool iostat -v
      zbackup` shows ~245-261MB/s aggregate device bandwidth, i.e.
      **~122-130MB/s of actual data** — each mirror disk writes the full
      copy, so the pool row sums the two. Confirmed independently by
      dataset growth: 1.62T in ~3h45m ≈ 124MB/s. Against the old
      ~20MB/s-per-disk / ~40MB/s aggregate, that is **roughly 6x**.

      Consequence: **the old ~40h estimate for torrent's ~3.13TB is badly
      out of date.** At ~125MB/s it is on the order of 7-8h. Still
      unproven for a *remote* SSH-transported pull as opposed to this
      local one — torrent's first pull remains the honest datapoint for
      that.

      Not re-tuned: the 15m replication interval and tiered `archive`
      grid were chosen under the old ceiling and are now conservative
      rather than forced. Left as-is deliberately.

      Original diagnosis, kept for the record: Investigated live during
      torrent's first-ever `myBackupPush` run (3.13TB initial `zfs
      send`). Ruled out: network (confirmed direct LAN peer connection
      via `tailscale status --json`'s `CurAddr: 192.168.1.154:41641` —
      not relayed through DERP), CPU (modest usage on both ends), and
      raw disk bandwidth (`zpool iostat -v zbackup` showed each mirror
      disk only doing ~20MB/s, well under HDD capability). Actual
      causes, roughly by impact:
      1. **`zbackup`'s 2 disks (and `zdata`'s other 2) are all USB
         2.0 High-Speed (480 Mbps, confirmed via `lsblk -o TRAN` =
         `usb` and `/sys/bus/usb/devices/*/speed` = `480`), sharing
         one hub on a single upstream link** (`1-6.1`-`1-6.4`). That's
         a hard ~40-60MB/s ceiling across *all four* drives combined —
         not per-drive — which lines up almost exactly with the
         measured aggregate write rate. This is very likely the same
         physical enclosure/hub/cabling behind the pre-existing
         `hosts/homelab/README.md` "zdata pool: recurring I/O
         suspensions" known issue — same drives, same USB link, same
         symptom class (command timeouts/resets), not necessarily two
         separate problems.
      2. **Real USB-level faults recurring on the same link**:
         `dmesg` shows `uas_eh_abort_handler`/`uas_eh_device_reset_handler`
         and `stat urb: status -71` across multiple drives (`sdb`,
         `sdc`, `sdd`, `sde`) at multiple points in time (including
         within the hour, and again from 5+ days ago) — not a one-off.
         Worth a physical inspection of the enclosure/hub/cable at
         some point, separate from any software fix.
      3. **`services.sanoid.interval = "minutely"` recursively walking
         all of `zbackup`** (`"zbackup" = { use_template = "backup";
         recursive = "yes"; }`, `hosts/homelab/configuration.nix`)
         adds real seek contention on top of an already
         bandwidth-starved USB link — confirmed via `zpool iostat -w
         zbackup`'s latency histogram showing a real tail of read/write
         ops taking 2-8 *seconds*, not just milliseconds, consistent
         with interleaved random (sanoid's metadata enumeration) and
         sequential (the receive stream) I/O thrashing the same two
         physical disks. Even with `autosnap = "no"` on the backup
         template, sanoid still enumerates every existing snapshot
         every 60s to evaluate `autoprune` — real work against a tree
         that includes 168+ historical snapshots on `storage-bulk`
         alone.
      4. **Root cause of the hour-to-hour rate fluctuation, confirmed
         2026-08-21 ~21:00 via a temporary non-invasive correlation
         trace** (2-min samples of `zpool iostat`, cross-referenced
         with `systemctl status` on the local syncoid units — removed
         after the transfer, not left running): homelab's own three
         local `syncoid` jobs (`syncoid-zdata-storage-storage[-bulk]`,
         `syncoid-zroot-local-state`, all hourly) were confirmed
         **`active (running)` continuously for ~2 hours** (since
         19:01:26, still running at the 21:00 check) — competing with
         torrent's transfer for the same USB-bandwidth-capped pool the
         entire time. These are normally-fast incremental syncs that
         finish in seconds, but with the USB link already saturated by
         torrent's initial full send, they get starved too, run long
         enough to blow past their next hourly trigger, and end up
         running back-to-back instead of going idle between runs — a
         compounding effect where torrent's big transfer slows the
         local jobs, and the local jobs competing for bandwidth slows
         torrent right back. The aggregate pool write rate itself
         (~33-48MB/s, near the #1 USB ceiling) stayed fairly
         consistent throughout — what fluctuates is how that fixed
         bandwidth splits between torrent's stream and these 3
         concurrent local jobs.
      Not fixed — diagnosis only, explicitly requested not to change
      anything mid-transfer. If/when revisited: consider a real
      USB 3.0 (SuperSpeed) link or SATA/HBA passthrough for this
      enclosure (addresses #1, #2, and #4 all at once — the local-job
      contention only compounds because #1's ceiling is so low), and/or
      loosening `zbackup`'s sanoid cadence off the global `minutely`
      interval since it's a receive-only target that never autosnaps
      anyway (addresses #3) — but both are real infra/config changes
      that need their own separate decision, not bundled into this.

      **Moved here 2026-08-25** — was already marked `[x]` and fully
      resolved but had been left sitting in `TODO.md`'s Active section
      instead of moved, against this file's own convention.

- [x] **2026-08-19: syncoid push backups, torrent + thinkpad → homelab
      (zfs snapshot based, over Tailscale).** Shared `myBackupPush`
      module (`modules/nixos/backup-push.nix`), used identically by both
      hosts, pushing `zroot/local/home` + `zroot/local/root` to a
      dedicated `backup-recv` user on homelab via `zfs allow`-scoped
      delegation. Uses syncoid `--create-bookmark` so long offline
      periods (esp. the thinkpad laptop, but torrent can also go dark on
      vacation) don't force a full resync once sanoid's short
      source-side retention (hourly=24/daily=1) prunes past the last
      pushed snapshot. Trigger: hourly systemd timer, `Persistent =
      true`, gated by a Tailscale-reachability `ExecCondition` so an
      offline host no-ops instead of alerting. `backupStaleness`
      thresholds set generously (336h/2wk) for both, for the same
      reason. Source-side runs as a dedicated `backup-push` user
      (zfs-allow-scoped, not root), and a paired
      `modules/nixos/zfs-space-guard.nix` (`myZfsSpaceGuard`) on both
      hosts auto-prunes oldest local snapshots under free-space pressure
      (torrent/thinkpad's game libraries under `zroot/local/home` churn
      heavily) plus a `zfs-emergency-prune.service` manual escape hatch
      (`zfs-space-guard`'s own testing/fate is its own entry above).
      **Follow-up once impermanence lands**: `zroot/local/root` will
      likely stop being the meaningful thing to back up — update
      `myBackupPush.datasets` on both hosts to point at whatever the new
      persist dataset ends up being called instead.

      **Final zbackup layout (simplified 2026-08-19)**: one flat
      `zbackup/backup/<host>/<subdir>` convention for everything — no
      more backup-vs-backup-bulk split. That split existed to keep
      large/churny data out of any future offsite job, but restic's
      offsite `backblazeWeekly` job reads an explicit hardcoded dataset
      list (`zroot/local/state zdata/storage/storage
      zdata/storage/storage-bulk`) and never touches `zbackup` at all —
      confirmed by reading the actual `backupPrepareCommand` — so the
      split wasn't doing anything functional. Current tree:
      ```
      zbackup/backup/homelab/{storage,storage-bulk,state}   (local syncoid pulls)
      zbackup/backup/thinkpad/{home,root}                    (remote syncoid push)
      zbackup/backup/torrent/{home,root}                     (remote syncoid push)
      ```
      `backup/legion`, `backup-bulk/legion`, `backup/other`,
      `backup-bulk/other` (all confirmed unreferenced placeholders) were
      dropped entirely. Sanoid's `"zbackup" = { use_template = "backup";
      recursive = "yes"; }` already covers the whole tree recursively —
      no per-dataset sanoid config needed for any of this.
      Code committed on branch `worktree-zfs-backup-push`; **not yet
      deployed to any real host.**

      **Merged onto master 2026-08-21** (commit `dff4450`, branch not
      yet pushed to origin): rebased this whole feature onto the
      dendritic flake-parts restructuring that landed on master in the
      meantime (`flake.nix` rewrite, `profiles/`/`services/` moved into
      `modules/`, host `imports` replaced by named-module wiring in
      `modules/flake/hosts.nix`). `backup-push.nix` and
      `zfs-space-guard.nix` converted to the
      `flake.modules.nixos."<name>"` wrapper format and wired into
      torrent's/thinkpad's module lists there. `hosts/homelab/disko.nix`
      and `hosts/homelab/configuration.nix` merged with **zero
      conflicts** — confirmed non-overlapping with the dendritic changes
      and with `zfs-pool-recovery-restore`'s LUKS work via an earlier
      dry-run merge test. Verified post-merge: `nixos-rebuild build`
      (not switch) succeeds for all three hosts, and `nix flake check`
      passes for the whole flake (all 5 nixosConfigurations).

      **New hard blocker from the merge**: `secrets/secrets.yaml` had a
      real conflict — both this branch (torrent/thinkpad backup-push
      keys) and master (a samba password from another branch) added new
      secrets in the same spot. The per-key encrypted values merged
      safely as a plain union (each is an independent ciphertext), but
      the file's `sops:` metadata (`lastmodified`/`mac` — a MAC over the
      *entire file's* contents) could not be hand-merged; master's copy
      was kept as a placeholder and was stale until `sops --ignore-mac
      --rotate --in-place` fixed it during the homelab deploy below.

      **Live pool note**: the storage-bulk rename
      (`zbackup/backup-bulk/homelab/storage-bulk` →
      `zbackup/backup/homelab/storage-bulk`) needed to land atomically
      with homelab's `nixos-rebuild switch` for this branch — done as
      part of the deploy below, confirmed intact (2.26T + full snapshot
      history) afterward. The `legion`/`other`/superseded-bulk-split
      placeholder datasets were confirmed unused and cleaned up
      alongside.

      Rollout: pushed and fast-forward merged into `master`
      (`7706eca..a03ce7c`, 2026-08-21). Both `torrent_backup_push_key`/
      `thinkpad_backup_push_key` ed25519 keypairs generated, added to
      `secrets/secrets.yaml`, and their public halves wired into
      homelab's `backup-recv.openssh.authorizedKeys.keys`. Deployed to
      homelab 2026-08-21: live deploy surfaced and fixed two real bugs
      build-only testing couldn't catch (`backup-recv-zfs-allow.service`
      needed a `zfs create -p` pre-step since `zfs allow` requires its
      target dataset to already exist; `health-check.service`'s
      `backupStaleness` loop needed `|| true` to tolerate a genuinely
      nonexistent dataset under `set -e -o pipefail`). Also found/fixed,
      separately: homelab's `/etc/nixos` checkout stuck on an orphaned
      `auto-update` branch from a crashed `flake-update-test` run
      (cleaned up live with explicit go-ahead — see this file's
      `flake-update-test.service`/git-identity entry), and the stale
      sops mac from the merge
      conflict (fixed via `sops --ignore-mac --rotate --in-place`,
      verified via a direct `sops-install-secrets` run against the built
      manifest before trusting it live).

      **Superseded 2026-08-25, before the rest of the rollout checklist
      (deploying torrent/thinkpad's push, confirming the
      Tailscale-`ExecCondition` behavior, wiring `backupStaleness` into a
      live alert) ever ran.** The zrepl migration (this file's "replace
      sanoid+syncoid with zrepl repo-wide" entry) deleted
      `backup-push.nix` and this entire syncoid-push mechanism,
      replacing it repo-wide with zrepl's pull-based topology — homelab
      now dials out to torrent/thinkpad instead of either pushing to it.
      Everything above (the `backup-recv`/`backup-push` user pair, the
      per-host push keys, the Tailscale-reachability gating, the flat
      `zbackup/backup/<host>/<subdir>` layout convention) either no
      longer exists or was carried forward and re-described fresh in the
      zrepl entry rather than incrementally amended here. Moved here as
      a completed record of what shipped and later got replaced, not
      because the rollout finished on its own terms.

- [x] **2026-08-23: replace sanoid+syncoid with zrepl repo-wide.** Code
      complete on branch `worktree-zrepl-migration-plan`; all three hosts
      build and pass `zrepl configcheck`. **homelab deployed 2026-08-24
      10:02 PDT (local replication complete, boot race fixed and
      reboot-verified); torrent deployed 2026-08-24 ~17:16 PDT (initial
      full send to homelab in progress, ~301 GiB/3.3 TiB as of 18:45 PDT,
      ETA roughly 05:00-07:00 PDT 2026-08-25); thinkpad not yet deployed.**

      **2026-08-24 ~18:20 PDT: fixed a recurring `local-pull` prune
      `ExecErr` on homelab** (`destroys failed ... it's being held`,
      firing on `zdata/storage/storage`, `storage-bulk`, and
      `zroot/local/state` on every ~15min cycle). Root cause, found by
      reading zrepl's own pruning source
      (`internal/pruning/retentiongrid/retentiongrid.go`,
      `internal/pruning/keep_grid.go`, `internal/pruning/pruning.go` in
      the pinned nixpkgs `zrepl.src`, nixpkgs rev `e4bae1bd`): a grid
      bucket without `keep=all` sorts its occupants youngest-first and
      removes the leading `removeCount` of them
      (`RemoveYoungerSnapsExceedingKeepCount`), i.e. it targets the
      *newest* snapshot in an over-full bucket for destruction, not the
      oldest. `Grid.FitEntries` also redefines "now" every prune run as
      the youngest matching snapshot's own timestamp. `retention.archive`
      (`"168x1h | 30x1d | 12x30d"`, no leading full-granularity bucket)
      combined with `local-pull`'s 15m interval against snapshots landing
      every 5m meant the just-received snapshot landed in an over-full
      bucket almost every cycle — and that snapshot is exactly the one
      zrepl's own endpoint had just placed its
      `zrepl_last_received_J_<job>` hold on, to guarantee a valid
      incremental base. The destroy failed loudly every cycle. Harmless
      (checked: receiver-side snapshot counts stayed bounded, older
      entries in the bucket pruned fine) but permanent log noise, and a
      sign the rule set was fighting zrepl's own bookkeeping — not a
      config mistake specific to homelab, since every receiving job
      shares this default.

      **Fix:** `retention.archive` gets a leading `1x15m(keep=all)`
      bucket (commit `6f6e4f3`), sized to the pull interval — `keep=all`
      short-circuits the grid's destroy-list logic for that bucket
      entirely (`if b.keepCount == RetentionGridKeepCountAll { return nil
      }`), so the newest snapshot can never collide with its own hold.
      Deployed to homelab (switch) and torrent (`run0`-wrapped local
      switch); verified via a clean `local-pull` cycle post-deploy
      (`Pruning Receiver: Status: Done`, actually destroying old
      snapshots, no `ExecErr`). Documented in `docs/backups.md` Gotchas.

      **Side effect, not a bug:** restarting `zrepl.service` on homelab
      (as any switch does) killed torrent's in-flight `home` full send
      mid-transfer at ~257 GiB. `SavePartialRecvState:true` meant a
      `receive_resume_token` survived on the receiver, so the next pull
      cycle resumed from ~257 GiB rather than restarting the 3.3 TiB send
      — confirmed via `zfs get receive_resume_token` before the resume
      and the dataset's `USED` growing steadily after. Worth remembering
      before any future homelab config change while a host's initial
      sync is still running: expect a pause-and-resume, not data loss.

      The capacity blocker below (`zbackup` had no room for both layouts)
      was resolved earlier this session by destroying the old syncoid-era
      datasets once the new layout's local copies were verified complete
      — see "Capacity fully resolved" in the prior handoff. One
      side-effect of that cleanup only surfaced deploying torrent today:
      the destroy took `backup/torrent` itself, not just
      `backup/torrent/home` underneath it (unlike `backup/thinkpad`,
      which survived as an empty container) — so torrent's first pull
      failed with zrepl's `root_fs does not exist` (`root_fs` is required
      to pre-exist; zrepl only auto-creates the placeholders *under* it,
      never `root_fs` itself —
      confirmed against `internal/endpoint/endpoint.go:658` in zrepl
      0.7.0). Fixed by recreating it to match `disko.nix`'s declared
      properties exactly (`mountpoint=none`,
      `com.sun:auto-snapshot=false`; `canmount` doesn't inherit in ZFS —
      it's dataset-local and defaults to `on`, so leaving it unset
      reproduces the siblings' actual `on` regardless of the pool root's
      `off` — confirmed by comparing property sources against
      `backup/homelab`/`backup/thinkpad` before recreating). User ran the
      `zfs create` directly since the auto-mode permission classifier
      blocked it when attempted via SSH, same friction the handoff
      predicted for homelab root actions.

      Also fixed as part of today's torrent deploy: `zrepl`'s
      `ssh+stdinserver` client has no TTY to TOFU-prompt on an
      unrecognized host key, so the very first pull attempt after
      torrent's `sshd` came up failed with "Host key verification
      failed" rather than connection-refused. Pinned torrent's actual
      host key declaratively via `programs.ssh.knownHosts.torrent` in
      `hosts/homelab/configuration.nix` rather than weakening to
      `StrictHostKeyChecking=accept-new` — thinkpad will need the same
      treatment once its host key is known.

      Design, retention, and the non-obvious zrepl behaviours are
      documented in `docs/backups.md` — read that rather than
      re-deriving. Restore steps in
      `docs/procedures/backup-restore.md`. Session handoff with the
      remaining steps in `HANDOFF.md`.

      Status in brief: one shared module (`modules/nixos/zrepl.nix`,
      `myZrepl`) replaced sanoid, syncoid and `backup-push.nix`. Topology
      is pull (homelab dials out; sources passive). Every host runs a
      local `snap` job so snapshotting and a prune ceiling never depend
      on a peer. `zbackup`'s layout changed to
      `zbackup/backup/<host>/<full source dataset path>`.

      VM-tested (2026-08-24): all three hosts boot with `zrepl.service`
      started, and a new two-node NixOS VM test
      (`nix build .#checks.x86_64-linux.zrepl-replication`) exercises a
      real pull over the forced-command SSH transport. That test found
      and fixed a bug `zrepl configcheck` cannot catch: receiving jobs
      were missing `recv.placeholder.encryption`, which would have failed
      every remote pull on first receive with no syncoid left to fall
      back on.

      Remaining: deploy homelab → torrent → thinkpad. Before switching
      homelab, confirm `zbackup/backup/{homelab,thinkpad,torrent}` exist
      — zrepl does not create `root_fs`, and disko only creates datasets
      when formatting a disk. torrent's first pull doubles as the fresh full send that
      resolves the stuck-backup incident below. thinkpad's existing copy
      sits at old paths and needs a fresh send or a manual `zfs rename`.
      Once burnt in, turn off `myZrepl.preserveLegacySnapshots` and clear
      the leftover `autosnap_*` snapshots by hand — nothing ages them out
      while it is on.

      **2026-08-25: all three hosts deployed; thinkpad's first sync
      completed clean.** thinkpad built+switched locally (`run0
      nixos-rebuild switch`, no `--target-host`, per the user's request
      for this host), its SSH host key pinned on homelab
      (`programs.ssh.knownHosts.thinkpad`, commit `5eb7858`). torrent's
      first-ever full send finished sometime before 2026-08-25 06:50 PDT
      (was ~1.8 TiB/3.1 TiB at 00:05, done and down to tiny incrementals
      by 06:50).

      Traced a recurring `dial_timeout of 10s exceeded` on thinkpad's pull
      job (self-healing every 15m retry, but frequent — correlated against
      every failure timestamp checked) to Tailscale's magicsock
      continuously flapping between candidate endpoints for the
      homelab↔thinkpad path, confirmed via `tailscaled` logs, even though
      both hosts share a LAN with a stable 1ms direct path available.
      Verified against zrepl v0.7.0's actual source
      (`internal/config/config.go`, fetched from the exact tagged commit
      the nix build uses) rather than the docs site, which undersold the
      mid-transfer failure mode: `dial_timeout` is a real per-connect-type
      field (`SSHStdinserverConnect`/`TCPConnect`/`TLSConnect`), default
      10s. Bumped to 60s universally in the shared `mkConnect` helper
      (commit `6bd1638`) rather than patching thinkpad alone, since this
      class of network flakiness is inherent to whatever LAN a host sits
      on. Deployed to homelab (the only dialer).

      `myZrepl.preserveLegacySnapshots` turned off for thinkpad and
      torrent (commit `a9bfed7`), matching homelab. thinkpad verified to
      already have zero legacy `autosnap_*` snapshots on
      `zroot/local/{root,home}` — deployed and confirmed live, a pure
      hygiene no-op there. **torrent's change is staged but NOT deployed**
      — the session doing this work ran on thinkpad, which has no
      shell/deploy access to torrent at all (not even via homelab, whose
      own `root@torrent` key is rejected at the publickey stage). Needs
      `nixos-rebuild switch --target-host root@torrent` (or run locally on
      torrent) from a session with real access. This is the one loose end
      left after `HANDOFF.md` was deleted and the branch merged to
      `master` — check `zfs list -t snapshot` on torrent for lingering
      `autosnap_*` entries once that switch lands.

      **Landed 2026-08-25 (confirmed via live triage session).** The one
      loose end above is resolved: torrent's live config has
      `preserveLegacySnapshots = false`, its `current-system` is a fresh
      build (`nixos-system-torrent-26.11.20260813.0e251e2`, same
      generation date as the other hosts), and `zfs list -t snapshot -r
      zroot/local` shows **zero** `autosnap_*` entries — the switch
      landed and the legacy cleanup is confirmed clean. All three hosts
      are on zrepl with nothing further outstanding from this migration.

- [x] **2026-08-23: torrent's `backup-push-torrent.service` (`home`
      dataset) is now stuck — needs a decision, not further automated
      action.** The initial full send finished transferring all ~3.13TB
      successfully, but the same syncoid invocation then tried to also
      send a trailing incremental to catch up to the latest snapshot, and
      that failed: the base snapshot it needed had already been pruned by
      torrent's own local sanoid retention during the ~38-40h transfer.
      Needed a decision on whether to force a full resend or leave the
      stale backup as-is, plus a structural fix so a future large
      transfer can't hit the same trap (widen source retention, or split
      the full-send/incremental-catchup syncoid invocations so a bookmark
      always lands after a successful full send).

      **Superseded 2026-08-25, not actually resolved on its own terms.**
      The zrepl migration (above) deleted `backup-push.nix` and the
      syncoid-based push mechanism entirely, replacing it with zrepl's
      pull-based topology repo-wide — the stuck `home` dataset, the
      pruned-bookmark trap, and the retention-window fix this item called
      for all describe a mechanism that no longer exists. Moved here
      rather than left open since there's nothing left to act on; the
      underlying lesson (a long-running transfer can outlast source-side
      snapshot retention, breaking the incremental base) is still valid
      and worth remembering for any future large `zfs send`, but the
      specific fix no longer applies to this repo's current backup
      architecture.

- [x] **2026-08-18: homelab's weekly restic-to-Backblaze backup has no
      safeguard against `myAutoUpdate`'s Thursday auto-switch killing
      a mid-run backup.** During a full-bucket reset/re-test of the
      backup, we found homelab runs `nixos-rebuild switch` every
      Thursday 03:00 via `myAutoUpdate` (`hosts/homelab/configuration.nix`),
      and `switch-to-configuration` restarts any systemd unit whose
      definition changed — including `restic-backups-backblazeWeekly.service`
      (Type=oneshot, `TimeoutStartSec=1w`) if the restic module, its
      overrides, or a shared dep like `pkgs-stable` changes. A run in
      progress (backups have taken multiple days for the ~2.9TiB
      dataset) would be killed with no resumption. Worked around this
      time by manually pausing the `nixos-upgrade` timer for the
      duration of the manual run. Needs a permanent fix: either make
      the backup service resilient to being interrupted/restarted
      (state/resume support, or a `ConditionXXX`/lock that defers an
      auto-switch while a backup is active), or have `myAutoUpdate`
      skip switching while `restic-backups-backblazeWeekly.service` is
      active.

      **Landed 2026-08-25** as part of the auto-updater rearchitect
      (`modules/flake/deploy-guards.nix`'s `check_protected_units_inactive`,
      wired via `myAutoUpdate.protectedUnits` on homelab). A scheduled
      `auto-switch` run now skips (and retries next cycle) rather than
      switching while any configured protected unit is active, instead
      of a manual-pause workaround. Deployed and live on homelab.

- [x] **2026-08-19: `flake-update-test.service` failing on homelab —
      root has no git identity configured.** Found during a log trawl.
      The update-branch step fails with `fatal: unable to auto-detect
      email address (got 'root@homelab.(none)')` right after the flake
      inputs are bumped, because `git config --global user.email`/
      `user.name` were never set for root on homelab. Needs: set a git
      identity for root declaratively (e.g. via
      `home-manager.users.root.programs.git` in `profiles/server.nix`,
      alongside the existing root home-manager block) so
      `myAutoUpdate`'s commit step succeeds.

      **Confirmed live 2026-08-21** while deploying zfs-backup-push:
      the crash (2026-08-19 03:01) left homelab's `/etc/nixos` checkout
      on an orphaned `auto-update` branch with an uncommitted
      `flake.lock` bump — `nixos-rebuild switch` was blocked on this
      stale state until manually cleaned up (`git checkout master &&
      git reset --hard origin/master && git branch -D auto-update &&
      git clean -fd`, done live with the user's explicit go-ahead).

      **Landed 2026-08-25.** Root cause was `modules/home-manager/tooling.nix`
      hardcoding its git-identity include path to `/home/lilijoy`
      regardless of which user's home-manager profile imported it —
      root's `homeDirectory` is `/root`, so the include never resolved
      to anything on server hosts. Fixed by making the include path
      relative to `config.home.homeDirectory`, plus a matching
      sops-templated `git-identity` render for root in
      `profiles/server.nix` (reuses the `git_username`/`git_email`
      secrets already decryptable by every host's age key — no secret
      editing needed). Verified live on homelab: `git config user.name`/
      `user.email` now resolve correctly for root.
      **Still open**: whether the self-heal path (an orphaned
      `auto-update` branch getting reset-and-recreated cleanly by the
      next scheduled run) actually holds is unverified in practice —
      the next real `flake-update-test` run (Wed 03:00) is the first
      chance to observe it with the identity fix in place.

- [x] **2026-08-18: caddy hits a permission-denied race against the
      anubis unix socket right after vps reboots.** Found trawling
      vps's logs: from 03:18–03:47 (right after a 23:47 reboot), every
      request to `jellyfin.skyseekerlabs.net` 502'd with `dial unix
      /run/anubis/anubis-jellyfin/anubis.sock: connect: permission
      denied` (36 requests total), then self-resolved and hasn't
      recurred since. `caddy`'s `id` showed it *is* in the `anubis`
      group (`users.users.caddy.extraGroups = [ "anubis" ]`), so this
      looked like a boot-order race, not a missing-permission bug.
      Re-checked live 2026-08-25 (no reboot since 2026-08-20, so no
      fresh data on the race itself at that point) — socket perms and
      group membership both correct, journal history showed the
      "permission denied" signature confined to the single Aug 18
      window, consistent with a self-resolved boot-order race.

      **Root cause identified and landed 2026-08-26**
      (`hosts/vps/configuration.nix`, branch
      `worktree-caddy-anubis-boot-order`): confirmed against the pinned
      nixpkgs source (`nixos/modules/services/networking/anubis.nix`)
      that the anubis module sets `DynamicUser = true` with `Type =
      simple` and no `systemd.sockets.*` unit — the unix socket is
      created by the anubis process itself, and its `anubis` group is
      a *transient* dynamic group that exists only while
      `anubis-jellyfin.service` is active, not a static system group.
      If caddy's process is spawned before that unit has started, its
      one-time supplementary-group resolution (`extraGroups = [
      "anubis" ]`) simply finds no such group — exactly matching the
      observed "permission denied" signature confined to a narrow
      post-boot window. Fix: added
      `systemd.services.caddy.after`/`wants = [ "anubis-jellyfin.service"
      ]`, which guarantees systemd allocates the dynamic group (part
      of *starting* that unit, before `Type = simple`'s immediate
      "started" transition) before caddy is even dispatched.

      Build-tested (`nixos-rebuild build --flake .#vps`), deployed
      live (`nixos-rebuild switch --flake .#vps --target-host
      root@vps`), and confirmed across a real reboot (the vps droplet
      had also just been recreated the same day — host key change
      verified as legitimate via journal/auth-log inspection and a
      matching already-trusted Tailscale-IP known_hosts entry before
      proceeding). Post-reboot journal shows `anubis-jellyfin.service`
      starting before `caddy.service` as intended, zero "permission
      denied" occurrences, `getent group anubis` includes `caddy`, and
      `jellyfin.skyseekerlabs.net` serves `HTTP 302` normally. A
      separate, unrelated transient 502 was observed for a few seconds
      immediately post-boot (wg0's WireGuard handshake to homelab
      re-establishing after the reboot) — self-healed within ~10s, not
      connected to the anubis socket race this item was about.

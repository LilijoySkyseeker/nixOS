---
slug: add-fail2ban-to-vps-defaulting-to-an-immediate-ban
created: 2026-08-25
status: done
frozen: true
---

# add fail2ban to vps, defaulting to an immediate ban for any connection attempt against a non-present/non-listening service

## Original plan

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

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

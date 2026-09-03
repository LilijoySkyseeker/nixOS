# Security hardening

Apply these by default when adding new hosts or custom systemd services —
not just when asked. Established during a hardening pass referencing
https://xeiaso.net/blog/paranoid-nixos-2021-07-18/.

## Standing rules

Ten rules harvested from the 2026-08-26 fleet audit
([`docs/audits/2026-08-26/`](audits/2026-08-26/)). They are the classes
of mistake that audit found **more than once** — mostly *because* this
document did not say them. They are deliberately short and imperative;
the analysis, the `file:line` evidence and the severity reasoning stay
in the audit and are linked rather than restated, so this file stays
readable. Where a rule and its evidence ever disagree, the evidence
wins — fix the rule here.

Numbering matches [`findings.md`](audits/2026-08-26/findings.md) §4.
Its rule 10 (`AllowTcpForwarding` defaults to `yes`) is not repeated
here; it is already applied in the SSH bullet below.

### Secrets

1. **Recipient rotation is not value rotation.** This repo is public,
   so every revision of `secrets/secrets.yaml` is permanently
   downloadable and removing an age recipient protects nothing already
   committed. Rotating a *key* means rotating the *values* at each
   provider. Assume any value that was ever encrypted to a retired
   recipient is disclosed until the provider says otherwise.
   (`findings.md` C1, `F-P8-02`; procedure in
   [`docs/procedures/secrets.md`](procedures/secrets.md))
2. **Give each host only the secrets it consumes.** Write per-path
   `creation_rules` in `.sops.yaml`. A single blanket rule naming every
   recipient makes every host a full-fleet decryption oracle, so one
   compromised laptop discloses the whole fleet. (`findings.md` C1)
3. **Never generate key material on a snapshotted or replicated
   filesystem.** `mktemp -d` is not safe on a host whose root dataset
   snapshots every five minutes and ships those snapshots offsite.
   Generate into a tmpfs, and scrub on failure rather than preserving
   for debugging. (`F-P7-08`)

### Network exposure

4. **Docker-published ports bypass the NixOS firewall entirely.** A
   `-p` mapping DNATs in the `nat` table and the packet never traverses
   `nixos-fw`, so an interface-scoped `networking.firewall` rule in
   front of a published port is decorative. Bind the publish to a
   specific address (`-p 10.100.0.2:25565:25565`), or add a
   `DOCKER-USER` allowlist. This applies fleet-wide, not just where it
   is currently commented — see
   `hosts/homelab/configuration.nix`. (`findings.md` H3, `F-P4-02`,
   `F-P3-04`)
5. **Scope every firewall rule to an interface.** Host-wide openings
   are for deliberately public ports only. A rule justified by a belief
   about the network ("we are behind CGNAT", "this NIC is LAN-only") is
   a rule that will silently become wrong: homelab's LAN NIC already
   carries a globally-routable RA-delegated IPv6 address, which is what
   started this audit. (`findings.md` H4;
   [threat model](threat-model.md) §2.1, §7.1)

### Privilege

6. **Put privilege on the unit, not the user.** Use
   `serviceConfig.SupplementaryGroups` and per-unit capabilities, never
   `users.users.*.extraGroups`, to give a service the access it needs —
   a user-level grant applies to *everything* that user ever runs, for
   as long as the account exists. Gate the grant on the same condition
   as the feature that needs it, so turning the feature off removes the
   privilege too. (`findings.md` H2, `F-P3-02`)
7. **Never point a root service at a user-writable path.** A git
   repository is executable configuration — hooks, `.gitattributes`
   filters, submodule URLs — so a root unit operating on a checkout the
   desktop user can write is a root shell for that user.
   `safe.directory` suppresses precisely the warning that exists to
   tell you this. (`findings.md` C2)

### Data

8. **Keep one backup copy outside the authority of any single root.**
   Append-only credentials, Object Lock, `zfs allow` delegation, or
   offline media — pick one. Otherwise the backups share a failure
   domain with the thing they protect, and one root deletes both the
   data and its history. (`findings.md` C3;
   [`docs/backups.md`](backups.md))

### Verification

9. **Verify that config actually takes effect — rendering is not
   applying.** NixOS modules emit their own defaults into the generated
   file first, and many config formats are first-directive-wins, so an
   option set in an `extraConfig`-shaped escape hatch can render, look
   right in a diff, and do nothing. Prefer the module's structured
   `settings`, and confirm with the daemon's own dump (`sshd -T`,
   `caddy adapt`, `zrepl configcheck`) or with
   `nix eval .#nixosConfigurations.<host>.config....` — not by reading
   the file you just wrote. This is why `PermitRootLogin` sat inert in
   `extraConfig` on two hosts. ([threat model](threat-model.md) §7.2, `F-P3-18`)

### OCI containers

10. **Containers get their own rules, because the systemd sandboxing
    rule does not reach them.** An `oci-containers` unit is a `docker
    run` wrapper — its `serviceConfig` is `ExecStart`/`ExecStop` and
    nothing else, and the isolation lives in the container instead. So
    for every container:

    - **Publish to an address, never `0.0.0.0`** — see rule 4.
    - **Pin the image by digest**, not by a floating tag. A `stable` or
      `2.1.14` tag is mutable and can be re-pointed upstream.
      (`F-P4-03`, `F-P4-13`) The game servers are a **deliberate,
      documented exception** — they auto-update on purpose; see
      [`accepted-risks.md`](accepted-risks.md) AR-7. Departing from this
      rule is allowed; departing from it silently is not.
    - **`--cap-drop=ALL`** with an explicit, justified add-back list.
    - **`--security-opt=no-new-privileges:true`**, unless a specific
      documented feature needs otherwise — record the reason at the
      setting.
    - **`--read-only`**, or a written reason why not. (`F-P4-09`)
    - **`--pids-limit` and a `--memory` ceiling** on anything parsing
      untrusted input. Without a cgroup ceiling, container OOM pressure
      is *host* OOM pressure and the kernel picks its own victim among
      whatever else the host runs. Set `--memory` from measured RSS
      with headroom, not from the app's own heap setting — a ceiling
      below what the runtime needs becomes an OOM-kill loop that looks
      like an application crash.
    - **Secrets reaching a container through a bind-mounted file land
      in every snapshot and every offsite backup of that dataset**, and
      leave sops's control the moment they do. (`F-P4-04`)

    Container uid 0 is host uid 0 on bind mounts unless `userns-remap`
    is configured in `virtualisation.docker.daemon.settings`.
    `modules/nixos/docker-userns-remap.nix` (`myDockerUserns`) does
    this declaratively, including migrating pre-existing bind-mount
    ownership (Docker never adjusts that itself), VM-verified in
    `tests/docker-userns-remap.nix`. Wired into homelab, build-verified,
    **not deployed** — enabling it is disruptive, not a quiet flip:
    it forces a full `dockerd` restart (not live-reloadable) and both
    game containers re-pull their images on first activation, since
    Docker's storage path changes per remap user. (`F-P4-07`)

### Observability

11. **A guard that declines to act must be watched by something that
    measures the outcome, not the attempt.** Every guard in
    `deploy-guards.nix` ends in `exit 0` — correctly, since a deferred
    deploy is not an error — so systemd records a skip as success and
    it never enters `systemctl --failed`. A check that only watches
    units therefore cannot distinguish "deployed weekly for a year"
    from "skipped every week for a year". Two consequences, both of
    which bit this fleet:

    - **Watch the result the guard exists to produce.** For deploys
      that is `/nix/var/nix/profiles/system`, whose mtime is the last
      real activation by any route, so it stays honest when a host is
      updated by hand. Prefer an existing artefact like this over a
      bespoke marker the guarded unit writes about itself — the
      bespoke one records that the *unit* ran, and will alarm on a host
      that is perfectly current because a human deployed it.
      (Non-obvious: `stat` that path **without** `-L`. Store paths all
      have mtime 1, so dereferencing reports every host as permanently
      stale.)
    - **Never hang `OnSuccess=` off a unit that can skip.** systemd
      cannot tell a skip from a real run, and `SuccessExitStatus=` does
      not help — it makes the exit *count* as success, so `OnSuccess=`
      still fires. Gate the follow-on on evidence the work actually
      happened. homelab's `auto-switch` chained a full closure build and
      push to vps off a switch its own guard had just deferred, in the
      same second. (`F-P7-09`)

## Conventions in detail

- **Shared server baseline lives in `modules/profiles/server.nix`**,
  imported by every server-class host (currently `homelab`, `vps`):
  `nix.settings.allowed-users = [ "root" ]`, `security.sudo.enable =
  false`, `security.auditd.enable`/`security.audit.enable` with an
  execve audit rule. Host-specific hardware tweaks (e.g. an
  `ethtool`/`networkd-dispatcher` rule tied to a specific NIC name)
  must NOT live here — they silently break on hosts without that
  interface. Put those in the host's own `configuration.nix` instead.
  Any new persist-capable host that gets `security.auditd`/
  `security.audit` needs `/var/log` in its impermanence persistence
  list, or the audit trail is wiped every boot.
- **Persisting a `DynamicUser=true` service's `StateDirectory=`.**
  systemd creates `/var/lib/<name>` as a symlink into
  `/var/lib/private/<name>` for `StateDirectory=`-managed paths under
  `DynamicUser=true` — a real impermanence bind mount can't land on a
  path that's actually a symlink (`mount: not canonical, contains a
  symlink`). If a `DynamicUser` service's state needs to survive
  reboots, drop the directory from that service's `StateDirectory=`
  (`lib.mkForce` an override without it) and grant write access via
  `ReadWritePaths` instead, so impermanence owns the path outright —
  see `hosts/vps/configuration.nix`'s
  `crowdsec-firewall-bouncer-register` override for both directories it
  needs this for. Missing this can produce a subtler failure than an
  outright mount error: if a service's on-disk state (e.g. CrowdSec's
  own bouncer-registration DB) persists via one mechanism while a
  *different* directory the same subsystem depends on (e.g. the
  bouncer's API key file) isn't persisted at all, the two can silently
  diverge across a reboot into a split-brain state that only surfaces
  as an application-level error, not a systemd/mount failure.
- **No real `sudo`.** All hosts alias `sudo` to `run0`
  (`security.run0.enableSudoAlias` in `modules/profiles/default.nix`);
  `server.nix`'s `security.sudo.enable = false` confirms the real
  package is intentionally absent. Never install or invoke the real
  `sudo` binary. When a command needs root and the target user's shell
  won't cooperate with `sudo -u <user>` (e.g. a `nologin`-shelled
  system user like `crowdsec`, where run0-aliased sudo silently no-ops
  with exit 200), use `runuser -u <user> --` instead.
  - **`security.sudo.enable = false` also changes third-party tools'
    own wrapper behavior, not just this repo's code.** CrowdSec's own
    `cscli` binary on `PATH` isn't the raw one — the NixOS module wraps
    it (`pkgs.writeShellScriptBin "cscli"`, `environment.systemPackages`)
    with a check that re-execs via `sudo -u <cfg.user>` when invoked as
    the wrong user, but **hard-aborts** (`Aborting, cscli must be run as
    user \`crowdsec\`!`) instead when `security.sudo.enable` is false —
    which it always is here. Confirmed live on vps's own VM test: bare
    `cscli` as root aborts every time, with no privilege-drop fallback.
    A caller that needs `cscli` from a *different* unit's context (e.g.
    `hosts/vps/configuration.nix`'s fail2ban `cscli.conf` ban action)
    should call the package's raw binary by absolute store path
    (`${config.services.crowdsec.package}/bin/cscli`) instead of the
    wrapped name on `PATH`, bypassing this check entirely — and should
    generally run as root rather than `runuser -u crowdsec --`-ing into
    it, unless the calling unit's own `CapabilityBoundingSet` actually
    includes `CAP_SETUID`/`CAP_SETGID` (`runuser` needs them to switch
    UID, and `CapabilityBoundingSet` restricts every child process
    regardless of nominal UID 0 — fail2ban's own systemd unit doesn't
    grant these, so `runuser` from its action would fail; root already
    has the file access this needs via `CAP_DAC_READ_SEARCH`, and
    CrowdSec's local API only cares about the credentials file's
    contents, not OS-level caller identity).
- **SSH**: deny everything not explicitly needed —
  `passwordAuthentication no`, `PermitRootLogin prohibit-password`,
  `AuthenticationMethods publickey`, `X11Forwarding no`,
  `AllowAgentForwarding no`, `AllowStreamLocalForwarding no`,
  `PermitTunnel no`, `ClientAliveInterval 60`/`ClientAliveCountMax 5`,
  `allowSFTP = false` unless actually used, and `AllowTcpForwarding no`.

  Two things about that list are easy to get wrong, and both were got
  wrong in this repo before the 2026-08-26 audit caught them:

  - **`AllowTcpForwarding` defaults to `yes`, not `no`.** This bullet
    used to say the opposite. It is wrong: the pinned NixOS `sshd.nix`
    declares no default for it, so nothing renders it, and OpenSSH's own
    `sshd_config.5` says "`yes` (the default)". The same is true of
    `AllowAgentForwarding` and `AllowStreamLocalForwarding`. Anything not
    written out explicitly is **on**, so write them out. (`PermitTunnel`
    really does default to `no`.)
  - **Write these as structured `settings`, never `extraConfig`.**
    `sshd_config` is first-directive-wins, and the module emits
    `settings` into the `configFile` half that sshd reads *before*
    `extraConfig`. A directive placed in `extraConfig` that the module
    also emits is therefore silently inert — it renders, it looks right
    in a diff, and it does nothing. Verified with `sshd -T`, not by
    reading the generated file.
- **Dedicated service users.** Any new `systemd.services.<name>` should
  run under its own dedicated, purpose-specific `users.users.<name>`
  (system user, no login shell) rather than `root`, unless root is
  strictly required for that service to function — grant only the
  specific group memberships/capabilities/`zfs allow` delegations
  actually needed. If root genuinely can't be avoided, note why in the
  commit message — `zrepl` is the standing example: its daemon runs as
  root for ZFS admin ioctls, and its `ssh+stdinserver` transport requires
  the *SSH* user to be root too, because the stdinserver socket sits in a
  0700 runtime directory with no chmod applied. The boundary there is a
  forced command in `authorized_keys` pinning the key to exactly
  `zrepl stdinserver <identity>`, with the identity fixed server-side
  rather than asserted by the client (see `docs/backups.md`).
- **Custom `systemd.services` sandboxing**: add `NoNewPrivileges = true`
  plus, when the unit's actual job allows it, the full stack —
  `ProtectSystem = "strict"` (with `ReadWritePaths` for whatever it
  legitimately writes), `ProtectHome`, `ProtectKernelModules`,
  `ProtectKernelTunables`, `ProtectKernelLogs`, `ProtectControlGroups`,
  `RestrictNamespaces`, `PrivateTmp`. Don't over-sandbox units that
  perform real system activation (anything running `nixos-rebuild
  switch`/`boot`, e.g. `system.autoUpgrade`'s `nixos-upgrade` service,
  `myPullDeploy`'s `pull-deploy` service) — those need broad
  filesystem/kernel access for bootloader and activation-script writes,
  so only `NoNewPrivileges` is safe there. A build-only job (no switch
  step) can get the full sandboxing stack, since the build itself
  happens inside nix-daemon's own sandbox. Don't sandbox around a
  documented functional need either — e.g. a restic backup service
  mounting ZFS snapshots into a shared `/tmp` needs `PrivateTmp = false`
  and can't take `ProtectSystem`/namespace restrictions without
  breaking the mount; check for an existing override's reason before
  adding hardening that would conflict with it.
- **Secrets + swap**: prefer `zramSwap.enable = true` over a disk swap
  partition on any host where sops decrypts live secrets (done on
  `vps`) — disk-backed swap risks paging secret material to persistent
  unencrypted storage.
- **Tailscale forwarding sysctls**: check what
  `services.tailscale.useRoutingFeatures` actually forces via sysctl
  overrides before assuming a plain `boot.kernel.sysctl` assignment
  will stick — the tailscale module sets
  `net.ipv{4,6}.conf.all.forwarding` at a priority that beats a plain
  override when `useRoutingFeatures = "both"`. Narrow it to `"client"`
  (`lib.mkForce`) on hosts that aren't actually an exit node/subnet
  router.
- **Forwarded/DNAT'd ports get zero protection** from CrowdSec/
  Anubis/Caddy (those only see traffic that reaches userspace
  HTTP/SSH) — add per-source-IP rate limiting (iptables `raw` table
  PREROUTING + `hashlimit`, evaluated before conntrack/NAT) as the
  floor for anything forwarded straight through to another host.

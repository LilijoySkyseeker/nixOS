# Security hardening

Apply these by default when adding new hosts or custom systemd services —
not just when asked. Established during a hardening pass referencing
https://xeiaso.net/blog/paranoid-nixos-2021-07-18/.

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
- **SSH**: deny everything not explicitly needed —
  `passwordAuthentication no`, `PermitRootLogin prohibit-password`,
  `AuthenticationMethods publickey`, `X11Forwarding no`,
  `AllowAgentForwarding no`, `AllowStreamLocalForwarding no`,
  `PermitTunnel no`, `ClientAliveInterval 60`/`ClientAliveCountMax 5`,
  `allowSFTP = false` unless actually used. `AllowTcpForwarding`
  defaults to `no` — only flip to `yes` for a specific confirmed need.
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

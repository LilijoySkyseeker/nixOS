# Style guide

Conventions actually in use in this repo, not aspirational ones. See
`docs/architecture.md` for the dendritic module-organization boundary.

## Formatting

`nixfmt <file>` is the formatter of record — 2-space indent, trailing
commas, `with pkgs; [ ... ]` package lists. Run it before committing;
`statix check .` and `deadnix .` catch lint issues nixfmt doesn't.

## Module registration: `flake.modules.<class>.<name>`

Every `.nix` file under `modules/` self-registers into
`flake.modules.nixos.<name>` or `flake.modules.homeManager.<name>` —
see `docs/architecture.md` for the mechanics. Two separate conventions
live inside that one registration pattern:

### Custom options modules: the `my<Name>` convention

A handful of `modules/nixos/` files (`auto-update.nix`,
`health-alerts.nix`, `iso-autobuild.nix`, `pull-deploy.nix`,
`push-deploy.nix`) define a real NixOS options surface, not just plain
config. These follow one consistent shape:

```nix
{
  flake.modules.nixos."push-deploy" =
    { config, lib, ... }:
    let
      cfg = config.myPushDeploy;
    in
    {
      options.myPushDeploy = {
        enable = lib.mkEnableOption "...";
        # ...other options via lib.mkOption
      };

      config = lib.mkIf cfg.enable {
        # ...
      };
    };
}
```

- Option namespace is `my<CamelCaseModuleName>` (e.g. `myPushDeploy`,
  `myAutoUpdate`) — deliberately prefixed so it can't collide with an
  upstream NixOS/home-manager option of the same shape. This is
  unrelated to the `flake.modules.nixos.<name>` registration key —
  the registration key is how the module gets pulled into a host; the
  `my<Name>` option namespace is how that module exposes its own
  settings once included.
- Always gated behind `enable` via `lib.mkIf cfg.enable`, even when a
  host is the module's only consumer — keeps the module inert by
  default and the enable/disable surface explicit at the host/profile
  level instead of buried in the module.

Reach for this pattern only when the config is genuinely parameterized
(multiple hosts want it with different settings, or it needs an
enable/disable toggle). If a host is the config's only consumer and
there's nothing to parameterize, a plain `modules/services/*.nix` file
is simpler — see `docs/architecture.md`'s module-organization section.

Everything else — `modules/services/*.nix`, `modules/profiles/*.nix`,
`modules/home-manager/*.nix`, and most of `modules/nixos/` (`kde.nix`,
`wooting.nix`, etc.) — registers into `flake.modules.*` but is a plain
config attrset inside that registration, no custom options surface.
That's the default; don't add an options layer without a reason.

### Registration key vs. filename

The `flake.modules.nixos.<name>`/`flake.modules.homeManager.<name>`
key is what other files and `modules/flake/hosts.nix` actually
reference — it does not have to match the filename, and several don't:
`modules/profiles/PC.nix` registers as `"profile-pc"`,
`modules/profiles/default.nix` as `"profile-default"`,
`modules/profiles/server.nix` as `"profile-server"`,
`modules/nixos/nfs-homelab-mounts.nix` as `"nfs-homelab-mounts"`. When
a new module's registration key would diverge from its filename in a
non-obvious way, say so directly, in the file or in the owning
folder's README — a reader who greps by filename and finds nothing
shouldn't have to reverse-engineer the key from the file's contents.
See `AGENTS.md`'s "Navigating: what does host X actually run?" for how
this is used in practice.

## Inline "why" comments

Non-obvious only — a workaround, a surprising constraint, a tradeoff,
an incident the config is defending against. Skip comments that restate
what the code already says. Real examples from this repo:

- `modules/profiles/default.nix`, on `services.tailscale`: explains
  *why* `--ssh` is deliberately left disabled, with an incident
  reference — not just "disable ssh."
- `modules/profiles/PC.nix`, on `users.groups.flatpak.gid = 998`:
  cross-references `modules/nixos/nfs-homelab-mounts.nix` to explain a
  gid collision that forced a specific pinned value.
- `modules/profiles/PC.nix`, on `sops.age.sshKeyPaths` /
  `generateKey`: explains the boot-time identity resolution problem
  the specific config shape works around.
- `modules/nixos/push-deploy.nix`, on the `elevate` option: documents
  `nixos-rebuild-ng`'s actual `--sudo` behavior, including a note that
  a prior assumption about it was wrong.
- `AGENTS.md`'s dendritic Gotchas section, on `config` shadowing in
  `modules/services/jellyfin.nix` and
  `modules/nixos/nfs-homelab-mounts.nix`: documents a real mistake made
  during the migration (reusing `config` for both the outer
  flake-parts scope and the inner NixOS module scope silently read the
  wrong object) so it isn't repeated.

The pattern worth copying across all of these: when a comment exists
because an earlier assumption turned out to be false, say so — it
stops the same wrong assumption from being made again.

## Security hardening

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
  actually needed (see `services.syncoid`'s `zfs allow`/`zfs unallow`
  wrapper-script pattern for ZFS-touching services). If root genuinely
  can't be avoided (e.g. raw `/dev/zfs` admin ioctls with no delegation
  path), note why in a comment.
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

## Naming

- Host names are the literal hostname (`thinkpad`, `torrent`, `homelab`,
  `vps`, `isoimage`), matching `flake.nixosConfigurations.<name>` in
  `modules/flake/hosts.nix`.
- `modules/services/*.nix` files are named after the service they
  configure (`jellyfin.nix`, `factorio.nix`), not the host that runs
  it.
- Custom module option namespaces use `my<CamelCase>` as above — this
  is separate from the `flake.modules.<class>.<name>` registration key,
  which may or may not match the filename (see above).

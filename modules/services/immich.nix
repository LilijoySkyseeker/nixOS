{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.immich =
    { config, lib, ... }:
    {
      # immich: self-hosted photo/video backup, tailnet-only.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md
      services.immich = {
        enable = true;
        # bind broad, restrict at the firewall below -- same shape as
        # jellyfin. openFirewall would open every interface, including
        # homelab's ISP-delegated public IPv6 LAN address.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G3
        host = "0.0.0.0";
        # reuses jellyfin's existing zdata/storage/storage dataset rather
        # than a new one -- already zrepl+restic backed up.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#D1
        mediaLocation = "/storage/immich";
      };

      # the upstream module's own tmpfiles rule for mediaLocation is type
      # `e` (adjust mode if it already exists) -- a no-op for anything but
      # its own default /var/lib/immich, which systemd's StateDirectory=
      # creates for free. Since mediaLocation is overridden above, nothing
      # ever creates it without this `d` rule (merged into the same
      # "immich" settings group the upstream module already declares).
      # Caught live on first deploy: immich-server crash-looped on EACCES
      # trying to mkdir under a mediaLocation that didn't exist.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G4
      systemd.tmpfiles.settings.immich.${config.services.immich.mediaLocation}.d = {
        user = config.services.immich.user;
        group = config.services.immich.group;
        mode = "0700";
      };

      # /storage is drwxrws--- root:multimedia (hosts/homelab/configuration.nix)
      # -- immich is in neither, so it can't traverse into its own
      # mediaLocation without this, even once the directory above exists.
      # Non-recursive and additive (a+, not the existing recursive-replace
      # `A /storage ... group:multimedia:rwx` rule) and execute-only: this
      # only lets immich reach the one subpath it already fully owns, not
      # read/list jellyfin's actual media. Must come after that existing
      # rule (same generated file, mkAfter) or the next boot's recursive
      # replace-pass wipes this entry back out.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G4
      systemd.tmpfiles.rules = lib.mkAfter [
        "a+ /storage - - - - user:immich:--x"
      ];

      # no wg0 rule here, unlike jellyfin -- this is the whole point:
      # never reachable through vps's public Caddy+Anubis proxy.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        config.services.immich.port
      ];

      # database/redis: both default to local unix sockets, no secrets
      # needed. plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G2
      environment.persistence.${vars.persistRoot}.directories = [
        # postgres holds the actual photo/album/face metadata + embeddings
        # -- unlike mediaLocation (a real ZFS mount that already survives
        # reboots), this sits under root and gets wiped by the
        # impermanence rollback every boot without this. Explicit
        # user/group (not a bare string) to match jellyfin.nix's
        # convention rather than impermanence's root:root/0755 default.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#F4
        {
          directory = "/var/lib/postgresql";
          user = "postgres";
          group = "postgres";
        }
      ];
    };
}

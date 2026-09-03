{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.immich =
    { config, ... }:
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

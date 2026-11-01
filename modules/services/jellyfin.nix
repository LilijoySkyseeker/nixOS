{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.jellyfin =
    {
      config,
      ...
    }:
    {
      # jellyfin
      services.jellyfin = {
        enable = true;
        group = "multimedia";
        configDir = "/srv/jellyfin/config";
        cacheDir = "/srv/jellyfin/cache";
        dataDir = "/srv/jellyfin/data";
        logDir = "/srv/jellyfin/log";
      };

      # pinned gid: NFS clients (modules/nixos/nfs-homelab-mounts.nix) authorize
      # by numeric gid, so drift silently breaks /storage access
      users.groups.multimedia = {
        gid = vars.gids.multimedia;
        members = [ "jellyfin" ];
      };
      # no tmpfiles rules for jellyfin's dirs: upstream creates them at 0700
      # (jellyfinDirs.conf); raw rules here land in 00-nixos.conf, sort first
      # and would loosen that

      # tailnet only: homelab's LAN NIC has a public IPv6 address, so no host-wide rule
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8096 ];

      # persistence
      environment.persistence.${vars.persistRoot}.directories = with config.services.jellyfin; [
        {
          directory = configDir;
          inherit user group;
        }
        {
          directory = cacheDir;
          inherit user group;
        }
        {
          directory = dataDir;
          inherit user group;
        }
        {
          directory = logDir;
          inherit user group;
        }
      ];
    };
}

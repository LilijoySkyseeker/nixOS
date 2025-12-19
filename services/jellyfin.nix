{ config, ... }:
{
  # jellyfin
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    group = "multimedia";
    configDir = "/srv/jellyfin/config";
    cacheDir = "/srv/jellyfin/cache";
    dataDir = "/srv/jellyfin/data";
    logDir = "/srv/jellyfin/log";
  };
  users.groups.multimedia.members = [ "jellyfin" ];
  systemd.tmpfiles.rules = [
    "d ${config.services.jellyfin.configDir} 0770 jellyfin - - -"
    "d ${config.services.jellyfin.cacheDir} 0770 jellyfin - - -"
    "d ${config.services.jellyfin.dataDir} 0770 jellyfin - - -"
    "d ${config.services.jellyfin.logDir} 0770 jellyfin - - -"
  ];

  # networking
  networking.firewall.allowedTCPPorts = [ 8096 ];
  networking.firewall.allowedUDPPorts = [ 8096 ];

  # persistence
  environment.persistence."/nix/state".directories = with config.services.jellyfin; [
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
}

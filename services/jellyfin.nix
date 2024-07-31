{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  # jellyfin
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user = "jellyfin";
    group = "multimedia";
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin/config 0770 jellyfin - - -"
  ];

  # caddy
  services.caddy.virtualHosts."jellyfin.skyseekerhomelab.duckdns.org".extraConfig = ''
    reverse_proxy localhost:8096
  '';
  networking.firewall.allowedTCPPorts = [
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443
  ];

  # persistence
  environment.persistence."/nix/state".directories = with config.services.jellyfin; [
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

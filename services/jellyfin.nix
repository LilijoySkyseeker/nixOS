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
    configDir = "/etc/jellyfin/config";
    dataDir = "/etc/jellyfin/data";
    logDir = "/etc/jellyfin/log";
    openFirewall = true;
  };
  networking.firewall.allowedTCPPorts = [
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443
  ];

  # caddy
  services.caddy.virtualHosts."jellyfin.skyseekerhomelab.duckdns.org".extraConfig = ''
    reverse_proxy localhost:8096
  '';

  # persistence
  environment.persistence."/nix/state" = {
    directories = [
      "${services.jellyfin.configDir}"
      "${services.jellyfin.dataDir}"
      "${services.jellyfin.logDir}"
    ];
    files = [
    ];
  };
}

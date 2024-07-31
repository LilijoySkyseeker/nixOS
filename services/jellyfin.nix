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

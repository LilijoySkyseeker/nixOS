{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {

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
      directory = configDir;
      inherit user group;
    }
  ];
}

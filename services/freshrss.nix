{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  # fseshrss
  services.freshrss = {
    enable = true;
    baseUrl = "";
    dataDir = "/srv/freshrss";
    defaultUser = "admin";
    passwordFile = config.sops.secrets.freshrss_admin_pass.path;
  };

  # directory permissions
  systemd.tmpfiles.rules = [
    "d ${config.services.freshrss.dataDir} 0770 freshrss - - -"
  ];

  # admin password
  sops.secrets.freshrss_admin_pass = {
    owner = "freshrss";
    group = "freshrss";
  };

  # caddy
  services.caddy.virtualHosts."freshrss.skyseekerlabs.duckdns.org".extraConfig = ''
    reverse_proxy localhost:8081
  '';

  # nginx virtual host
  services.nginx.virtualHosts.freshrss.listen = [
    {
      addr = "localhost";
      port = 8081;
    }
  ];

  # firewall
  networking.firewall.allowedTCPPorts = [
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443
  ];

  # persistence
  environment.persistence."/nix/state".directories = with config.services.freshrss; [
    {
      directory = dataDir;
      inherit user;
    }
  ];
}

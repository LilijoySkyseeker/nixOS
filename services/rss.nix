{
  config,
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  ...
}: {
  disabledModules = ["nixos/modules/services/web-apps/freshrss.nix"];
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/web-apps/freshrss.nix"
  ];

  # fseshrss
  services.freshrss = {
    enable = true;
    baseUrl = "";
    dataDir = "/srv/freshrss";
    defaultUser = "admin";
    passwordFile = config.sops.secrets.freshrss_admin_pass.path;
    extensions = with pkgs-unstable.freshrss-extensions; [
      reddit-image
    ];
  };

  # rss-bridge
  services.rss-bridge = {
    enable = true;
    #   user = "rss-bridge";
    #   group = "rss-bridge";
    dataDir = "/srv/rss-bridge";
    config = {
      system.enabled_bridges = ["*"];
      error = {
        output = "http";
        report_limit = 5;
      };
    };
  };

  # directory permissions
  systemd.tmpfiles.rules = [
    "d ${config.services.freshrss.dataDir} 0770 freshrss - - -"
    "d ${config.services.rss-bridge.dataDir} 0770 rss-bridge - - -"
  ];

  # passwords
  sops.secrets.freshrss_admin_pass = {
    owner = "freshrss";
    group = "freshrss";
  };

  # caddy
  services.caddy.virtualHosts."freshrss.skyseekerlabs.duckdns.org".extraConfig = ''
    reverse_proxy localhost:8081
  '';
  services.caddy.virtualHosts."rss-bridge.skyseekerlabs.duckdns.org".extraConfig = ''
    reverse_proxy localhost:8082
  '';

  # nginx virtual host
  services.nginx.virtualHosts.freshrss.listen = [
    {
      addr = "localhost";
      port = 8081;
    }
  ];
  services.nginx.virtualHosts.rss-bridge.listen = [
    {
      addr = "localhost";
      port = 8082;
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
  environment.persistence."/nix/state".directories = [
    {
      directory = config.services.freshrss.dataDir;
      user = "freshrss";
      group = "freshrss";
    }
    {
      directory = config.services.rss-bridge.dataDir;
      user = "rss-bridge";
      group = "rss-bridge";
    }
  ];
}

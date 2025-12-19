{
  config,
  ...
}:
{
  # fseshrss
  services.freshrss = {
    enable = true;
    baseUrl = "";
    dataDir = "/srv/freshrss";
    defaultUser = "admin";
    passwordFile = config.sops.secrets.freshrss_admin_pass.path;
  };

  # rss-bridge
  services.rss-bridge = {
    enable = true;
    #   user = "rss-bridge";
    #   group = "rss-bridge";
    dataDir = "/srv/rss-bridge";
    config = {
      system.enabled_bridges = [ "*" ];
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

  # networking
  networking.firewall.allowedTCPPorts = [
    8081
    8082
  ];
  networking.firewall.allowedUDPPorts = [
    8081
    8082
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

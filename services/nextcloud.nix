{
  config,
  pkgs,
  ...
}: {
  services.nextcloud = {
    enable = true;
    database.createLocally = true;
    package = pkgs.nextcloud29;
    home = "/srv/nextcloud";
    hostName = "nextcloud";
    config = {
      adminpassFile = config.sops.secrets.nextcloud_admin_pass.path;
    };
    settings = {
      default_phone_region = "US";
      trusted_domains = ["nextcloud.skyseekerlabs.duckdns.org"];
      trusted_proxies = ["127.0.0.1"];
      #     log_type = "file";
      #     loglevel = 3;
    };
  };

  # services.nextcloud = {
  #   enable = true;
  #   package = pkgs.nextcloud29; # Required to specify
  #   configureRedis = true;
  #   home = "/srv/nextcloud";
  #   database.createLocally = true;
  #   #   https = true;
  #   hostName = "localhost";
  #   maxUploadSize = "128G";
  #   config = {
  #     adminuser = "admin";
  #     adminpassFile = config.sops.secrets.nextcloud_admin_pass.path;
  #     dbtype = "pgsql";
  #   };
  #   settings = {
  #     default_phone_region = "US";
  #     # Allow access when hitting either of these hosts or IPs
  #     #     trusted_proxies = ["127.0.0.1"];
  #     log_type = "file";
  #     loglevel = 1; # Include all actions in the log
  #   };
  #   autoUpdateApps.enable = true;
  #   extraAppsEnable = true;
  #   #   extraApps = with config.services.nextcloud.package.packages.apps; {
  #   #     # List of apps we want to install and are already packaged in
  #   #     # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/nextcloud/packages/nextcloud-apps.json
  #   #     inherit calendar contacts;
  #   #   };
  #   settings = {
  #     #     overwriteprotocol = "https";
  #   };
  # };

  # caddy
  services.caddy.virtualHosts."nextcloud.skyseekerlabs.duckdns.org".extraConfig = ''
    redir /.well-known/carddav /remote.php/dav/ 301
    redir /.well-known/caldav /remote.php/dav/ 301
    reverse_proxy localhost:8080
  '';

  # nginx
  services.nginx.virtualHosts.${config.services.nextcloud.hostName}.listen = [
    {
      addr = "localhost";
      port = 8080;
    }
  ];

  # permissions
  systemd.tmpfiles.rules = [
    "d ${config.services.nextcloud.home} 0770 nextcloud nextcloud - -"
    "f ${config.services.nextcloud.home}/config/config.php  0770 nextcloud nextcloud - -"
    "f ${config.services.nextcloud.home}/config/override.config.php  0770 nextcloud nextcloud - -"
  ];

  sops.secrets.nextcloud_admin_pass = {
    owner = "nextcloud";
    group = "nextcloud";
  };

  networking.firewall.allowedTCPPorts = [
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443
  ];

  # persistence
  environment.persistence."/nix/state".directories = [
    {
      directory = config.services.nextcloud.home;
      user = "nextcloud";
      group = "nextcloud";
    }
  ];
}

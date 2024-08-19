{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  services = {
    nextcloud = {
      enable = true;
      home = "/srv/nextcloud";

      hostName = config.networking.hostName;

      # Need to manually increment with every major upgrade.
      package = pkgs.nextcloud28;

      # Let NixOS install and configure the database automatically.
      database.createLocally = true;

      # Let NixOS install and configure Redis caching automatically.
      configureRedis = true;

      # Increase the maximum file upload size to avoid problems uploading videos.
      maxUploadSize = "1024G";
      https = true;

      autoUpdateApps.enable = true;
      extraAppsEnable = true;
      extraApps = with config.services.nextcloud.package.packages.apps; {
        # List of apps we want to install and are already packaged in
        # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/nextcloud/packages/nextcloud-apps.json
        inherit calendar contacts;
      };
      settings = {
        overwriteprotocol = "https";
      };
      config = {
        dbtype = "pgsql";
        dbuser = "nextcloud";
        dbhost = "/run/postgresql"; # nextcloud will add /.s.PGSQL.5432 by itself
        dbname = "nextcloud";
        adminuser = "admin";
        adminpassFile = config.sops.secrets.nextcloud_admin_pass.path;
      };
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = ["nextcloud"];
    ensureUsers = [
      {
        name = "nextcloud";
        ensurePermissions."DATABASE nextcloud" = "ALL PRIVILEGES";
      }
    ];
  };

  systemd.services."nextcloud-setup" = {
    requires = ["postgresql.service"];
    after = ["postgresql.service"];
  };

  services.nginx.virtualHosts."nix-nextcloud".listen = [
    {
      addr = "127.0.0.1";
      port = 8009;
    }
  ];

  systemd.tmpfiles.rules = [
    "d ${config.services.nextcloud.home} 0770 nextcloud nextcloud - -"
  ];

  sops.secrets = {
    nextcloud_admin_pass = {
      owner = "nextcloud";
      group = "nextcloud";
    };
  };

  services.caddy = {
    virtualHosts = {
      "nextcloud.skyseekerhomelab.duckdns.org" = {
        useACMEHost = "nextcloud.skyseekerhomelab.duckdns.org";
        extraConfig = ''
          redir /.well-known/carddav /remote.php/dav 301
          redir /.well-known/caldav /remote.php/dav 301
          redir /.well-known/webfinger /index.php/.well-known/webfinger 301
          redir /.well-known/nodeinfo /index.php/.well-known/nodeinfo 301

          encode gzip
          reverse_proxy localhost:8009
        '';
      };
    };
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
      #       inherit user group;
    }
  ];
}

{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud29; # Required to specify
    configureRedis = true;
    datadir = "/srv/nextcloud";
    database.createLocally = true;
    https = true;
    hostName = "localhost";
    maxUploadSize = "128G";
    config = {
      adminpassFile = config.sops.secrets.nextcloud_admin_pass.path;
      dbtype = "pgsql";
    };
    settings = {
      default_phone_region = "US";
      # Allow access when hitting either of these hosts or IPs
      trusted_domains = [config.hostnames.content];
      trusted_proxies = ["127.0.0.1"];
      log_type = "file";
      loglevel = 1; # Include all actions in the log
    };
    autoUpdateApps.enable = true;
    extraAppsEnable = true;
    extraApps = with config.services.nextcloud.package.packages.apps; {
      # List of apps we want to install and are already packaged in
      # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/nextcloud/packages/nextcloud-apps.json
      inherit calendar contacts;
    };
    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
      "output_buffering" = "0";
    };
    settings = {
      overwriteprotocol = "https";
    };
  };

  services.nginx.enable = false;

  services.phpfpm.pools.nextcloud.settings = {
    "listen.owner" = config.services.caddy.user;
    "listen.group" = config.services.caddy.group;
  };
  users.users.caddy.extraGroups = ["nextcloud"];

  systemd.tmpfiles.rules = [
    "d ${config.services.nextcloud.datadir} 0770 nextcloud nextcloud - -"
  ];

  sops.secrets = {
    nextcloud_admin_pass = {
      owner = "nextcloud";
      group = "nextcloud";
    };
  };

  options.caddy.routes = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    description = "Caddy JSON routes for http servers";
    default = [];
  };

  caddy.routes = [
    {
      match = [{host = ["nextcloud.skyseekerhomelab.duckdns.org"];}];
      handle = [
        {
          handler = "subroute";
          routes = [
            # Sets variables and headers
            {
              handle = [
                {
                  handler = "vars";
                  # Grab the webroot out of the written config
                  # The webroot is a symlinked combined Nextcloud directory
                  root = config.services.nginx.virtualHosts.${config.services.nextcloud.hostName}.root;
                }
                {
                  handler = "headers";
                  response.set.Strict-Transport-Security = ["max-age=31536000;"];
                }
              ];
            }
            # Reroute carddav and caldav traffic
            {
              match = [
                {
                  path = [
                    "/.well-known/carddav"
                    "/.well-known/caldav"
                  ];
                }
              ];
              handle = [
                {
                  handler = "static_response";
                  headers = {
                    Location = ["/remote.php/dav"];
                  };
                  status_code = 301;
                }
              ];
            }
            # Block traffic to sensitive files
            {
              match = [
                {
                  path = [
                    "/.htaccess"
                    "/data/*"
                    "/config/*"
                    "/db_structure"
                    "/.xml"
                    "/README"
                    "/3rdparty/*"
                    "/lib/*"
                    "/templates/*"
                    "/occ"
                    "/console.php"
                  ];
                }
              ];
              handle = [
                {
                  handler = "static_response";
                  status_code = 404;
                }
              ];
            }
            # Redirect index.php to the homepage
            {
              match = [
                {
                  file = {
                    try_files = ["{http.request.uri.path}/index.php"];
                  };
                  not = [{path = ["*/"];}];
                }
              ];
              handle = [
                {
                  handler = "static_response";
                  headers = {
                    Location = ["{http.request.orig_uri.path}/"];
                  };
                  status_code = 308;
                }
              ];
            }
            # Rewrite paths to be relative
            {
              match = [
                {
                  file = {
                    split_path = [".php"];
                    try_files = [
                      "{http.request.uri.path}"
                      "{http.request.uri.path}/index.php"
                      "index.php"
                    ];
                  };
                }
              ];
              handle = [
                {
                  handler = "rewrite";
                  uri = "{http.matchers.file.relative}";
                }
              ];
            }
            # Send all PHP traffic to Nextcloud PHP service
            {
              match = [{path = ["*.php"];}];
              handle = [
                {
                  handler = "reverse_proxy";
                  transport = {
                    protocol = "fastcgi";
                    split_path = [".php"];
                  };
                  upstreams = [{dial = "unix//run/phpfpm/nextcloud.sock";}];
                }
              ];
            }
            # Finally, send the rest to the file server
            {handle = [{handler = "file_server";}];}
          ];
        }
      ];
      terminal = true;
    }
  ];

  networking.firewall.allowedTCPPorts = [
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443
  ];

  # persistence
  environment.persistence."/nix/state".directories = [
    {
      directory = config.services.nextcloud.datadir;
      #       inherit user group;
    }
  ];
}

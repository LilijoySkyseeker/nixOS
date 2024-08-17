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

      hostName = "nextcloud.skyseekerhomelab.duckdns.org";

      # Need to manually increment with every major upgrade.
      package = pkgs.nextcloud29;

      # Let NixOS install and configure the database automatically.
      database.createLocally = true;

      # Let NixOS install and configure Redis caching automatically.
      configureRedis = true;

      # Increase the maximum file upload size to avoid problems uploading videos.
      maxUploadSize = "1024G";
      https = true;
      enableBrokenCiphersForSSE = false;

      autoUpdateApps.enable = true;
      extraAppsEnable = true;
      extraApps = with config.services.nextcloud.package.packages.apps; {
        # List of apps we want to install and are already packaged in
        # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/nextcloud/packages/nextcloud-apps.json
        inherit calendar contacts;
      };

      config = {
        overwriteProtocol = "https";
        dbtype = "pgsql";
        adminuser = "admin";
        adminpassFile = "/path/to/nextcloud-admin-pass";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${config.services.nextcloud.home} 0770 nextcloud - - -"
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
      directory = config.services.nextcloud.home;
      inherit user group;
    }
  ];
}

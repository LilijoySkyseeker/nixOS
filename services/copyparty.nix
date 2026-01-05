{
  inputs,
  pkgs,
  config,
  ...
}:
{
  nixpkgs.overlays = [ inputs.copyparty.overlays.default ];
  imports = [ inputs.copyparty.nixosModules.default ];
  environment.systemPackages = [ pkgs.copyparty ];

  # copyparty
  services.copyparty = {
    enable = true;
    settings = {
      no-robots = true;
      e2dsa = true;
      e2ts = true;
      shr = "/share";
      re-maxage = 60;
      #     hist = "/srv/copyparty"; # temp disabled cuz read only weirdness for /srv
      z = true;
    };
    accounts = {
      lilijoy.passwordFile = config.sops.secrets.copyparty_lilijoy.path;
    };
    volumes = {
      "/" = {
        path = "/storage";
        access = {
          A = [ "*" ];
        };
      };
      "/Bulk" = {
        path = "/storage-bulk";
        access = {
          A = [ "*" ];
        };
      };
    };
  };

  # permissions
  users.users.copyparty.extraGroups = [ "multimedia" ];

  # networking
  networking.firewall.allowedTCPPorts = [
    69 # tftp
    1900 # ssdp
    3921 # ftp
    3923 # http/https
    3945 # smb
    3969 # tftp
    3990 # ftps
    5353 # mdns
    12000 # passive-ftp
  ];
  networking.firewall.allowedUDPPorts = [
    69 # tftp
    1900 # ssdp
    3921 # ftp
    3923 # http/https
    3945 # smb
    3969 # tftp
    3990 # ftps
    5353 # mdns
    12000 # passive-ftp
  ];

  # passwords
  sops.secrets.copyparty_lilijoy = {
    owner = "copyparty";
    group = "copyparty";
  };

  # directory permissions
  systemd.tmpfiles.rules = [ "d /srv/copyparty 0770 copyparty - - -" ];

  # persistence
  environment.persistence."/nix/state".directories = [
    {
      directory = "/srv/copyparty";
      user = "copyparty";
      group = "copyparty";
    }
  ];
}

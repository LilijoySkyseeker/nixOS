{
  inputs,
  pkgs,
  config,
  ...
}:
{
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
    };
    accounts = {
      lilijoy.passwordFile = config.sops.secrets.copyparty_lilijoy.path;
    };
    volumes = {
      "/" = {
        path = "/storage";
        access = {
          A = [ "lilijoy" ];
        };
      };
      "/bulk" = {
        path = "/storage-bulk";
        access = {
          A = [ "lilijoy" ];
        };
      };
    };
  };

  # permissions
  users.users.copyparty.extraGroups = [ "multimedia" ];

  # caddy
  services.caddy.virtualHosts."copyparty.skyseekerlabs.xyz".extraConfig = ''
    reverse_proxy localhost:3923
  '';

  # firewall
  networking.firewall.allowedTCPPorts = [ 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ];

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

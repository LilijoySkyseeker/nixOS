{
  inputs,
  pkgs,
  config,
  ...
}: {
  imports = [
    inputs.copyparty.nixosModules.default
  ];
  environment.systemPackages = [pkgs.copyparty];

  # copyparty
  services.copyparty = {
    enable = true;
    settings = {
      no-robots = true;
      e2dsa = true;
      e2ts = true;
      shr = "/share";
    };
    accounts = {
      lilijoy.passwordFile = config.sops.secrets.copyparty_lilijoy.path;
    };
    volumes = {
      "/" = {
        path = "/storage";
        access = {
          r = ["lilijoy"];
        };
      };
      "/bulk" = {
        path = "/storage-bulk";
        access = {
          r = ["lilijoy"];
        };
      };
    };
  };

  # permissions
  users.users.copyparty.extraGroups = ["multimedia"];

  # caddy
  services.caddy.virtualHosts."copyparty.skyseekerlabs.duckdns.org".extraConfig = ''
    reverse_proxy localhost:3923
  '';

  # firewall
  networking.firewall.allowedTCPPorts = [
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443
  ];

  # passwords
  sops.secrets.copyparty_lilijoy = {
    owner = "copyparty";
    group = "copyparty";
  };
}

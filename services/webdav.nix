{ config, ... }:
{
  # webdav
  services.webdav = {
    enable = true;
    settings = {
      address = "0.0.0.0";
      port = 8083;
      directory = "/";
      permisions = "none";
      users = [
        {
          username = "lilijoy";
          password = "$cat ${config.sops.secrets.webdav_lilijoy.path})";
          permissions = "CRUD";
        }
      ];
    };
  };

  # passwords
  sops.secrets.webdav_lilijoy = {
    owner = "webdav";
    group = "webdav";
  };

  # caddy
  services.caddy.virtualHosts."webdav.skyseekerlabs.xyz".extraConfig = ''
    reverse_proxy localhost:8083
  '';
}

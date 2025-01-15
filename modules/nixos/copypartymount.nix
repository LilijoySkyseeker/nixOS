{ pkgs, config, ... }:
let
  pass = "$(cat ${config.sops.secrets.copyparty_lilijoy.path})";
in
{
  environment.systemPackages = with pkgs; [ rclone ];

  environment.etc."rclone-mnt.conf".text = ''
    [cpp-rw]
        type = webdav
        vendor = owncloud
        url = https://copyparty.skyseekerlabs.duckdns.org
        headers = Cookie,cppwd=${pass}
        pacer_min_sleep = 0.01m
  '';

  # fileSystems."/home/lilijoy/Storage" = {
  #   device = "cpp-rw";
  #   fsType = "rclone";
  #   options = [
  #     "vfs-cache-mode = writes"
  #     "vfs-cache-max-age = 5s"
  #     "attr-timeout = 5s"
  #     "dir-cache-time = 5s"
  #   ];
  # };

  # passwords
  sops.secrets.copyparty_lilijoy = {
  };
}

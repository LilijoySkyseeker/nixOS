{
  pkgs,
  config,
  ...
}: {
  environment.systemPackages = with pkgs; [rclone];

  environment.etc."rclone-mnt.conf".text = ''
    [homelab-dav]
        type = webdav
        url = https://copyparty.skyseekerlabs.duckdns.org
        vendor = owncloud
        headers = Cookie,cppwd=hunter2
        pacer_min_sleep = 0.01ms
        user = k
        pass = "($cat ${config.sops.secrets.copyparty_lilijoy.path})"
  '';

  fileSystems."/home/lilijoy/homelab" = {
    device = "homelab-dav:";
    fsType = "rclone";
    options = [
      "nodev"
      "nofail"
      "allow_other"
      "args2env"
      "config=/etc/rclone-mnt.conf"
    ];
  };

  # passwords
  sops.secrets.copyparty_lilijoy = {
    owner = "copyparty";
    group = "copyparty";
  };
}

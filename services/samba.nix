{
  config,
  #  inputs,
  pkgs,
  ...
}: {
  # disabledModules = ["services/network-filesystems/samba.nix"];
  # imports = [
  #   "${inputs.nixpkgs-unstable}/nixos/modules/services/network-filesystems/samba.nix"
  # ];
  users = {
    groups.samba-guest = {};
    users.samba-guest = {
      isSystemUser = true;
      description = "Residence of our Samba guest users";
      group = "multimedia";
      home = "/var/empty";
      createHome = false;
      shell = pkgs.shadow;
    };
  };

  services.samba = {
    enable = true;
    openFirewall = true;
    extraConfig = ''
      server string = ${config.networking.hostName}
      netbios name = ${config.networking.hostName}
      workgroup = WORKGROUP
      security = user

      create mask = 0664
      force create mode = 0664
      directory mask = 0775
      force directory mode = 0775
      follow symlinks = yes

      # :NOTE| localhost is the ipv6 localhost ::1
      #hosts allow = 192.168.0.0/16 localhost
      #hosts deny = 0.0.0.0/0
      guest account = nobody
      map to guest = bad user
    '';
    # :NOTE| set sudo smbpasswd -a samba-guest -n
    shares = {
      Storage = {
        path = "/storage";
        browseable = "yes";
        "read only" = "no";
        "writable" = "yes";
        "guest ok" = "yes";
        "force user" = "samba-guest";
        "force group" = "multimedia";
        "write list" = "samba-guest";
      };
    };
  };
}

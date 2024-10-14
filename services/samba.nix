{inputs, ...}: {
  disabledModules = ["services/network-filesystems/samba.nix"];
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/network-filesystems/samba.nix"
  ];

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "invalid users" = [
          "root"
        ];
        "passwd program" = "/run/wrappers/bin/passwd %u";
        security = "user";
      };
      public = {
        browseable = "yes";
        comment = "Public samba share.";
        "guest ok" = "yes";
        path = "/storage";
      };
    };
  };
}

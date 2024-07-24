{
  config,
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  vars,
  ...
}: {
  imports = [
#   ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos/shared.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [
      # STABLE installed packages
    ])
    ++ (with pkgs-unstable; [
      # UNSTABLE installed packages
    ]);

  # Define your hostname.
  networking.hostName = "homelab";

  # lock down nix
  nix.allowedUsers = ["root"];

  # ssh server
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";

      X11Forwarding = false;
      extraConfig = ''
        AllowAgentForwarding no
        AuthenticationMethods publickey
        AllowStreamLocalForwarding no
      '';
    };

    # zfs support
    boot.supportedFilesystems = ["zfs"];
    environment.systemPackages = with pkgs; [zfs];
    services.zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };

    # persistence config, specifics are added by the specifc services
    fileSystems."/nix/state".neededForBoot = true;
    fileSystems."/nix".neededForBoot = true;

    # impermanance
    boot.initrd = {
      # to avoid problems with `boot.initrd.postDeviceCommands
      enable = true;
      supportedFilesystems = ["zfs"];

      systemd.services.restore-root = {
        description = "Rollback zfs zroot";
        wantedBy = ["initrd.target"];
        requires = [
          "/dev/disk/by-id/ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512"
        ];
        after = [
          "/dev/disk/by-id/ata-SAMSUNG_MZNLN256HMHQ-00000_S2SVNX0J403512"
        ];
        before = ["sysroot.mount"];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          zfs rollback -r zroot/local/root@blank && echo "rollback complete"
        '';
      };
    };
    #   boot.initrd.postDeviceCommands = lib.mkAfter '' # maybe legacy, will keep to check
    #     zfs rollback -r zroot/local/root@blank
    #   '';
    environment.persistence."/nix/state" = {
      # https://github.com/nix-community/impermanence?tab=readme-ov-file#module-usage
      enable = true;
      hideMounts = true;
      directories = [
        "/etc/nixos"
      ];
      files = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ];
    };
  };
}

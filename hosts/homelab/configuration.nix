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
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos/shared.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [
      # STABLE installed packages
      zfs
    ])
    ++ (with pkgs-unstable; [
      # UNSTABLE installed packages
    ]);

# lock down users
  users.mutableUsers = false;
  users.users.root.hashedPassword = "!";

  # Define your hostname.
  networking.hostName = "homelab";

  #security
  # lock down nix
  nix.settings.allowed-users = ["root"];
  # disable sudo
  security.sudo.enable = false;

  # ssh server
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    allowSFTP = true;
    enable = true;
    settings.KbdInteractiveAuthentication = false;
    extraConfig = ''
      passwordAuthentication = no
      PermitRootLogin = prohibit-password
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding no
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
      PermitTunnel no
    '';
  };

  # zfs support
  boot.supportedFilesystems = ["zfs"];
  ##   environment.systemPackages = with pkgs; [zfs];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "e0019fd8";

  # impermanance
  fileSystems."/nix/state".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;
  boot.initrd = {
      availableKernelModules = [ "xhci_pci" "ahci" "nvme" "sd_mod" ];
      systemd = {
        enable = true;
        services.rollback = {
          description = "Rollback root filesystem to a pristine state on boot";
          wantedBy = [ "initrd.target" ];
          after = [ "zfs-import-zroot.service" ];
          before = [ "sysroot.mount" ];
          path = with pkgs; [ zfs ];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = ''
            zfs rollback -r zroot/local/root@blank && echo "  >> >> ROLLBACK COMPLETE << <<"
          '';
        };
      };
    };

  # persistence
  environment.persistence."/nix/state" = {
    # https://github.com/nix-community/impermanence?tab=readme-ov-file#module-usage
    enable = true;
    hideMounts = true;
    directories = [
      "/var/log"
      "/etc/nixos"
      "/var/lib/systemd/timers" # for systemd persistant timers during off time
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}

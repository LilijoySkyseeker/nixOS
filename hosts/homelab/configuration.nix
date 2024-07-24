{
  config,
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
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
    environment.persistence."/nix/state" = {
      # https://github.com/nix-community/impermanence?tab=readme-ov-file#module-usage
      enable = true;
      hideMounts = true;
      directories = [
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

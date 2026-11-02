{ config, ... }:
let
  homeManagerModules = config.flake.modules.homeManager;
in
{
  flake.modules.nixos."desktop-user" = { config, ... }: {
    home-manager.users.lilijoy = {
      imports = [
        homeManagerModules.tooling
        homeManagerModules."tooling-desktop"
        homeManagerModules."virt-manager"
        homeManagerModules."claude-code"
        homeManagerModules."paseo-desktop"
      ];
      home = {
        stateVersion = "23.11";
        username = "lilijoy";
        homeDirectory = "/home/lilijoy";
      };
      programs.home-manager.enable = true;
    };
    nix.settings.allowed-users = [ "@wheel" ];

    # host age identity on the root fs (/home isn't mounted at early activation);
    # generateKey creates it on first boot, then add its pubkey to .sops.yaml
    # no sshKeyPaths to ~/.ssh: unreadable at boot (sops-nix#167); `sops` CLI ignores it
    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
    sops.age.generateKey = true;

    # git identity, rendered to avoid storing name/email in the nix store
    sops.secrets.git_username = { };
    sops.secrets.git_email = { };
    sops.templates."git-identity" = {
      path = "/home/lilijoy/.config/git/identity";
      owner = "lilijoy";
      content = ''
        [user]
            name = ${config.sops.placeholder.git_username}
            email = ${config.sops.placeholder.git_email}
      '';
    };

    environment.variables = {
      NH_FLAKE = "/home/lilijoy/dotfiles";
    };
    users.users.lilijoy = {
      isNormalUser = true;
      # no initialPassword: the repo is public, so any value is published;
      # if needed, use hashedPasswordFile from a sops secret, never a literal
      description = "Lilijoy";
      # never add `input`: read of every evdev device lets any user process
      # keylog run0/polkit, bitwarden and yubikey pin, bypassing wayland
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
    };
  };
}

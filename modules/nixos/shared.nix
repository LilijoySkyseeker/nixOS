{
  config,
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  ...
}: {
  environment.systemPackages =
    (with pkgs; [
      # STABLE installed packages
      wget
      eza
      tldr
      bat
      zoxide
      git
      neovim
      alejandra
    ])
    ++ (with pkgs-unstable; []); # UNSTABLE installed packages

  # overwrite all manually made users
  users.mutableUsers = false;

  # fix for buggy fish command not found
  programs.command-not-found.enable = false;

  # remove all defualt packages
  environment.defaultPackages = lib.mkForce [];

  # firewall
  networking.firewall.enable = true;

  # installed packages lits in /etc/current-system-packages.text
  environment.etc."current-system-packages".text = let
    packages = builtins.map (p: "${p.name}") config.environment.systemPackages;
    sortedUnique = builtins.sort builtins.lessThan (pkgs.lib.lists.unique packages);
    formatted = builtins.concatStringsSep "\n" sortedUnique;
  in
    formatted;

  # Enable Flake Support
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "colemak_dh";
  };

  # direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable networking
  networking.networkmanager.enable = true;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # State Version for first install, don't touch
  system.stateVersion = "23.11";
}

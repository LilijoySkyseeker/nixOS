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
      rsync
      sops # secrets management
      flac
    ])
    ++ (with pkgs-unstable; []); # UNSTABLE installed packages

  # tweaks, credit: https://github.com/headblockhead/dotfiles/blob/61cf195ab5a2f81d0844108b6f242938191622cc/systems/edward-desktop-01/config.nix
  # set each flake input as registry to make nix3 commands consistent with flake
  nix.registry = (lib.mapAttrs (_: flake: {inherit flake;})) ((lib.filterAttrs (_: lib.isType "flake")) inputs);
  # add inupts to legacy channels to make legacy commands consistant with flake
  nix.nixPath = ["/etc/nix/path"];
  environment.etc =
    lib.mapAttrs'
    (name: value: {
      name = "nix/path/${name}";
      value.source = value.flake;
    })
    config.nix.registry;

  # sops-nix support, secret managment
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
  };

  # NVIM
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  # auto gc with nh
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "daily";
      extraArgs = "--keep-since 7d --keep 2";
    };
  };

  # file system trip for ssd
  services.fstrim.enable = true;

  # fix for buggy fish command not found
  programs.command-not-found.enable = false;

  # remove all defualt packages
  environment.defaultPackages = lib.mkForce [];

  # firewall
  networking.firewall.enable = true;

  # installed packages lits in /etc/current-system-packages.text
  # environment.etc."current-packages".text = let
  #   packages = builtins.map (p: "${p.name}") config.environment.systemPackages;
  #   sortedUnique = builtins.sort builtins.lessThan (pkgs.lib.lists.unique packages);
  #   formatted = builtins.concatStringsSep "\n" sortedUnique;
  # in
  #   formatted;

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

  # x86_64
  nixpkgs.hostPlatform = "x86_64-linux";

  # State Version for first install, don't touch
  system.stateVersion = "23.11";
}

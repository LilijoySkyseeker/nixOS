{
  pkgs-unstable,
  pkgs-stable,
  inputs,
  lib,
  vars,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.nix-index-database.nixosModules.nix-index
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    inputs.nix-flatpak.nixosModules.nix-flatpak
    inputs.stylix.nixosModules.stylix
    inputs.nvf.nixosModules.default
  ];
  environment.systemPackages = with pkgs-unstable; [
    wget
    eza
    tldr
    bat
    zoxide
    git
    lazygit
    neovim
    nixfmt-rfc-style
    rsync
    sops # secrets management
    smartmontools
    helix
    trippy # ping+traceroute tool
  ];

  # firmware updates
  services.fwupd.enable = true;

  # SMART disk health tool
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications = {
      systembus-notify.enable = true;
      wall.enable = true;
      x11.enable = true;
    };
  };

  # allow cross compilation
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
  ];

  # allow unfree
  nixpkgs.config.allowUnfree = true;

  # enable a firmware regardless of licence
  hardware.enableAllFirmware = true;

  # make sure <nixpkgs> sources from the flake
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs-unstable}" ];

  # home-manager
  home-manager = {
    # also pass inputs to home-manager modules
    extraSpecialArgs = {
      inherit
        inputs
        pkgs-unstable
        pkgs-stable
        vars
        ;
    };
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup"; # Force backup conflicted files
  };

  # comma and cache
  programs.nix-index-database.comma.enable = true;

  # neovim
  programs.neovim = {
    enable = true;
    defaultEditor = lib.mkForce true;
  };

  # sops-nix support, secret managment
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
  };

  # auto gc with nh
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "daily";
      extraArgs = "--keep-since 7d --keep 7";
    };
  };

  # file system trim for ssd
  services.fstrim.enable = true;

  # fix for buggy fish command not found
  programs.command-not-found.enable = false;

  # remove all defualt packages
  environment.defaultPackages = lib.mkForce [ ];

  # firewall
  networking.firewall.enable = true;

  # Enable Flake Support
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

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
  i18n.defaultLocale = "es_US.UTF-8";
  i18n.supportedLocales = [
    "all"
  ];
  i18n.extraLocaleSettings = {
    LC_ALL = "es_US.UTF-8";
  };

  # x86_64
  nixpkgs.hostPlatform = "x86_64-linux";

  # State Version for first install, don't touch
  system.stateVersion = "23.11";
}

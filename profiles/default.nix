{
  config,
  pkgs-unstable,
  pkgs-stable,
  inputs,
  lib,
  vars,
  options,
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
  ];
  environment.systemPackages = with pkgs-unstable; [
    btop
    wget
    eza
    tldr
    bat
    zoxide
    git
    lazygit
    neovim
    nixfmt
    rsync
    sops # secrets management
    smartmontools
    helix
    trippy # ping+traceroute tool
    psmisc # fuser, killall, pstree
    ffmpeg
    flac
    bitwarden-cli
    topgrade

    zfs-prune-snapshots # TEMP, zfs needs module

  ];

  security = lib.mkMerge [
    # sudo for run0 alias (only present on nixpkgs versions that ship the run0 module;
    # newer run0 modules dropped the `enable` toggle since run0 itself is always available)
    (lib.optionalAttrs (options.security ? run0) {
      run0 =
        { enableSudoAlias = true; }
        // lib.optionalAttrs (options.security.run0 ? enable) { enable = true; };
    })
    {
      sudo = {
        enable = false;
        execWheelOnly = true;
        package = pkgs-unstable.sudo.override { withInsults = true; };
      };
    }
  ];

  # 26.11 change for zfs security
  boot.zfs.forceImportRoot = false;

  # tailscale
  # declarative login: authKeyFile logs the host into the tailnet on boot,
  # no manual `tailscale up` needed. Each host uses its own non-reusable
  # pre-authorized key (tailscale_authkey_<hostname>) already tagged with
  # tag:<hostname> at generation time, so a leaked key only ever grants
  # that one host's identity/tag rather than a shared credential.
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    authKeyFile = config.sops.secrets."tailscale_authkey_${config.networking.hostName}".path;
    # --ssh (Tailscale's own SSH server/auth implementation) is
    # deliberately NOT enabled: once on, it intercepts ALL SSH
    # connections to that host and gates them via the tailnet ACL's
    # "ssh" block, entirely bypassing real sshd — including any
    # authorized_keys ForceCommand restriction (confirmed live: this
    # broke vps's dedicated push-deploy user's command allowlist, and
    # when no ACL "ssh" rule matched, connections were hard-rejected
    # rather than falling through to real sshd — no partial/fallback
    # mode exists). SSH still only ever travels over the tailnet either
    # way (trustedInterfaces=tailscale0 + closed public port 22 on
    # every host that matters); this only decides whether real sshd or
    # tailscale's own proxy handles the authentication, and every host
    # here relies on real sshd being the one in control of that.
    extraUpFlags = [
      "--advertise-tags=tag:${config.networking.hostName}"
    ];
  };
  sops.secrets."tailscale_authkey_${config.networking.hostName}" = { };

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
    overwriteBackup = true;
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
  boot.loader.systemd-boot = {
    enable = true;
    editor = false;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable networking
  networking.networkmanager.enable = true;
  networking.nameservers = [
    "8.8.8.8"
    "1.1.1.1"
  ];
  services.resolved.enable = true;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.supportedLocales = [
    "all"
  ];
  i18n.extraLocaleSettings = {
    LC_MEASUREMENT = "en_GB.UTF-8"; # metric units
  };

  # x86_64
  nixpkgs.hostPlatform = "x86_64-linux";

  # State Version for first install, don't touch
  system.stateVersion = "23.11";
}

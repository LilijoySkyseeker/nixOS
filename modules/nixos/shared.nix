{config, pkgs, pkgs-unstable, inputs, lib, ... }:
{

  imports = [
    ../../modules/nixos/virtual-machines.nix #(also needs home manager config

  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [ # STABLE installed packages

    wget
    grc
    nvtop
    eza 
    vlc
    tldr

    xclip # for nvim clipboard

    qpwgraph

    zoxide

    bat
    ripgrep
    gitFull
    jdk
    python3

    distrobox

    easyeffects
    youtube-music

    qalculate-gtk
    libreoffice

    vial

    gnome-extension-manager
    baobab # gnome disk usage utilty
    gnome.gnome-tweaks
    discord
    bitwarden
    thunderbird
    vscode-fhs
    nicotine-plus
    cider
    prismlauncher
    kdenlive
    qbittorrent
    jellyfin-media-player

    ])
    ++
    (with pkgs-unstable; [ # UNSTABLE installed packages

    obsidian
    nh
    r2modman

    ]);

  # Enable Flake Support
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Enable X11 and Gnome
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "colemak_dh";
  };

  # Docker
  virtualisation.docker = {
    enable = true;
  };

  # Intel CPU freq stuck fix
  boot.kernelParams = [ "intel_pstate=active" ];

  # LD fix
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # add any missing dynamic libraries for unpackaged programs here
  ];

  # sudo insults
  security.sudo.package = pkgs.sudo.override { withInsults = true; };

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

  # Enable bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

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

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.lilijoy = {
    isNormalUser = true;
    description = "Lilijoy";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [

    ];
  };

  # Git
  programs.git = {
    enable = true;
  };

  # NVIM
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  # fish
  programs.fish = {
    enable = true;
    vendor.completions.enable = true;
  };
    programs.bash = { # switch to fish in interactive shell
    interactiveShellInit = ''
    if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
    then
      shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
      exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
    fi
  '';
  };

  # steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    package = with pkgs; steam.override { extraPkgs = pkgs: [
    # for FAF, https://discord.com/channels/197033481883222026/1228471001633914950/1228506126900006982
    jq
    cabextract
    wget 
    ]; };
  };

  # feral gamemode
  programs.gamemode ={
    enable = true;
    settings = {
      cpu = {
        park_cores = "no";
        pin_cores = "yes";
      };
    };
  };

  # flatpak
  services.flatpak.enable = true;

  # fonts
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "Meslo" ]; })
  ]; 

  # Mullvad vpn
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };
}

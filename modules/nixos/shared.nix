{config, pkgs, pkgs-unstable, inputs, lib, ... }:
{

  imports = [
    ../../modules/nixos/virtual-machines.nix #(also needs home manager config)

  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [ # STABLE installed packages

    wget
    grc
    eza 
    tldr
    bat
    ripgrep
    gitFull
    zoxide
    nvtopPackages.full
    xclip # for nvim clipboard
    gjs # for kdeconnect
    sops # secrets management
    restic # backups

    distrobox

    gnome-extension-manager
    baobab # gnome disk usage utilty
    gnome.gnome-tweaks
    bitwarden
    thunderbird
    vscode-fhs
    nicotine-plus
    cider
    prismlauncher
    kdenlive
    qbittorrent
    jellyfin-media-player
    easyeffects
    qpwgraph
    youtube-music
    qalculate-gtk
    libreoffice
    vial
    vlc
    r2modman

    discord
    obsidian
    spotify
    ])
    ++
    (with pkgs-unstable; [ # UNSTABLE installed packages


    ]);

  # nix helper
  programs.nh = {
    enable = true;
    flake = "/home/lilijoy/dotfiles";
    clean = {
      enable = true;
      dates = "daily";
      extraArgs = "--keep-since 7d --keep 2";
    };
  };

  # Stylix
  stylix = {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = /home/lilijoy/dotfiles/files/gruvbox-dark-rainbow.png;
    polarity = "dark";
    cursor.package = pkgs.capitaine-cursors-themed;
    cursor.name = "Capitaine Cursors";
    };

  # installed packages lits in /etc/current-system-packages.text
  environment.etc."current-system-packages".text =
    let
      packages = builtins.map (p: "${p.name}") config.environment.systemPackages;
      sortedUnique = builtins.sort builtins.lessThan (pkgs.lib.lists.unique packages);
      formatted = builtins.concatStringsSep "\n" sortedUnique;
    in
      formatted;

  # Enable Flake Support
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Disable uneeded GNOME apps
  environment.gnome.excludePackages = with pkgs.gnome; [
    totem # video player
    geary # mail
    gnome-calculator gnome-calendar gnome-characters 
    gnome-font-viewer gnome-logs gnome-screenshot
    gnome-weather pkgs.gnome-connections
  ];
  
  # Kde Connect
  programs.kdeconnect = {
    enable = true;
    package = pkgs.gnomeExtensions.gsconnect;
  };

  # Enable X11 and Gnome
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "colemak_dh";
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
  environment.shellAliases = lib.mkForce {}; # clear all shell aliases, using fish functions instead

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

  # Theme KDE apps like gnome
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };
}

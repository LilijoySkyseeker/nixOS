{ config, pkgs, pkgs-unstable, inputs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
       inputs.home-manager.nixosModules.default

       ../../modules/nixos/DE/gnome.nix
       ../../modules/nixos/hardware/keyboard-layout.nix
       ../../modules/nixos/hardware/wooting.nix

       #../../modules/nixos/utils/system-maintenance.nix
        ../../modules/nixos/utils/virtual-machines.nix #(also needs home manager config
        ../../modules/nixos/utils/docker.nix
        
    ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.sessionVariables = {
    FLAKE = "~/dotfiles";
  };

  # LD fix
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # add any missing dynamic libraries for unpackaged programs here
  ];


  # hyprland
  #programs.hyprland.enable = true;


  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Define your hostname.
  networking.hostName = "nixos-legion"; 

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


  # Configure keymap in X11
  #services.xserver = {
    #layout = "us";
    #xkbVariant = "colemak_dh";
  #};

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
    # If you want to use JACK applications, uncomment this
    # jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.lilijoy = {
    isNormalUser = true;
    description = "Lilijoy";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [

    ];
  };

  # Home Manager
  home-manager = {
    # also pass inputs to home-manager modules
    extraSpecialArgs = {inherit inputs;};
    users = {
      "lilijoy" = import ./home.nix;
    };
  };

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [ # STABLE installed packages
    wget
    grc
    nvtop
    eza 
    vlc

    qpwgraph

    zoxide

    bat
    ripgrep
    gitFull
    jdk
    python3

    distrobox
    ])
    ++
    (with pkgs-unstable; [ # UNSTABLE installed packages
    obsidian
    nh
    ]);

  
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
  # switch to fish in interactive shell
  programs.bash = {
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

  # GS-Connect/KDE-Connect
  programs.kdeconnect = {
    enable = true;
    package = pkgs.gnomeExtensions.gsconnect;
  };

  # Mullvad vpn
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

# Enable OpenGL, needed for NVIDIA drivers
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];


  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = false;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of 
    # supported GPUs is at: 
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus 
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = false;

    # Enable the Nvidia settings menu.
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

}

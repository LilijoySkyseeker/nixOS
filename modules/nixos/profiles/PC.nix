{
  config,
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  ...
}: {
  imports = [
    ../virtual-machines.nix #(also needs home manager config)
    ../shared.nix
    ../../../custom-packages/tpm-fido/package.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [
      # STABLE installed packages

      grc # Text colors
      ripgrep
      gitFull
      nvtopPackages.full
      xclip # for nvim clipboard
      gjs # for kdeconnect
      restic # backups
      fd
      nixos-anywhere
      ssh-to-age
      yubikey-manager

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
      yubioath-flutter

      discord
      obsidian
      spotify
    ])
    ++ (with pkgs-unstable; []); # UNSTABLE installed packages

  # tpm-fido
  tpm-fido.enable = true;

  # ssh key type order
  programs.ssh.hostKeyAlgorithms = [
    "ssh-ed25519"
    "ecdsa"
  ];

  # service for yubikey
  services.pcscd.enable = true;

  # restric nix package manager to @wheel
  nix.settings.allowed-users = ["@wheel"];

  # sops config
  sops.age.sshKeyPaths = ["/home/lilijoy/.ssh/id_ed25519" "/home/lilijoy/.ssh/id_ecdsa-sk"];
  sops.secrets = {
    open_weather_key = {};
    restic = {
      owner = config.users.users.lilijoy.name;
    };
  };

  # nix helper
  programs.nh = {
    flake = "/home/lilijoy/dotfiles";
  };

  # Stylix
  stylix = {
    enable = true;
    autoEnable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = /home/lilijoy/dotfiles/files/gruvbox-dark-rainbow.png;
    polarity = "dark";
    cursor.package = pkgs.capitaine-cursors-themed;
    cursor.name = "Capitaine Cursors";
  };

  # Disable uneeded GNOME apps
  environment.gnome.excludePackages = with pkgs.gnome; [
    totem # video player
    geary # mail
    gnome-calculator
    gnome-shell-extensions
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

  # Docker
  virtualisation.docker = {
    enable = true;
  };

  # Intel CPU freq stuck fix
  boot.kernelParams = ["intel_pstate=active"];

  # LD fix
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # add any missing dynamic libraries for unpackaged programs here
  ];

  # sudo
  security.sudo = {
    execWheelOnly = true;
    package = pkgs.sudo.override {withInsults = true;};
  };

  # Enable bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

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
    extraGroups = ["networkmanager" "wheel"];
  };

  # Git
  programs.git = {
    enable = true;
  };

  # fish
  programs.fish = {
    enable = true;
    vendor.completions.enable = true;
  };
  programs.bash = {
    # switch to fish in interactive shell
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
    package = with pkgs;
      steam.override {
        extraPkgs = pkgs: [
          # for FAF, https://discord.com/channels/197033481883222026/1228471001633914950/1228506126900006982
          jq
          cabextract
          wget
        ];
      };
  };

  # feral gamemode
  programs.gamemode = {
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
    (nerdfonts.override {fonts = ["Meslo"];})
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

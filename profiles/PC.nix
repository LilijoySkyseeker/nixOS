{
  pkgs-unstable,
  pkgs-stable,
  inputs,
  ...
}:
{
  imports = [
    ../modules/nixos/virtual-machines.nix # (also needs home manager config)
    ../modules/nixos/tooling.nix
    ./default.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs-unstable; [
      grc # Text colors
      ripgrep
      gitFull
      nvtopPackages.full
      gjs # for kdeconnect
      restic # backups
      fd
      nixos-anywhere
      ssh-to-age
      rclone

      yubikey-manager
      distrobox
      bitwarden
      thunderbird
      vscode-fhs
      cider
      kdenlive
      qbittorrent
      jellyfin-media-player
      easyeffects
      qpwgraph
      youtube-music
      libreoffice
      vial
      vlc
      r2modman
      yubioath-flutter
      prismlauncher
      nicotine-plus

      # closed source
      obsidian
      spotify
      vesktop
      zoom

    ])
    ++ (with pkgs-stable; [
      feishin
    ]);

  #flatpak
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = true;
    packages = [
      "info.beyondallreason.bar"
    ];
  };

  # udev rules for vial
  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';

  # ssh key type order
  programs.ssh.hostKeyAlgorithms = [
    #   "ed25519"
    #   "ecdsa"
  ];

  # home-manager
  home-manager.users.lilijoy = {
    imports = [
      ../modules/home-manager/tooling.nix
      inputs.impermanence.homeManagerModules.impermanence
      inputs.plasma-manager.homeManagerModules.plasma-manager
    ];
    home.stateVersion = "23.11";
    home.username = "lilijoy";
    home.homeDirectory = "/home/lilijoy";
    programs.home-manager.enable = true;
  };

  # service for yubikey
  services.pcscd.enable = true;

  # restrict nix package manager to @wheel
  nix.settings.allowed-users = [ "@wheel" ];

  # sops config
  sops.age.sshKeyPaths = [
    "/home/lilijoy/.ssh/id_ed25519"
    "/home/lilijoy/.ssh/id_ed25519"
  ];

  # nh, nix helper
  # programs.nh.flake = ./.;
  environment.variables = {
    FLAKE = "/home/liljoy/dotfiles";
  };

  # Stylix
  stylix = {
    enable = true; # TESTING
    autoEnable = true;
    base16Scheme = "${pkgs-unstable.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = ../files/gruvbox-dark-rainbow.png;
    polarity = "dark";
    cursor.package = pkgs-unstable.capitaine-cursors-themed;
    cursor.name = "Capitaine Cursors";
    fonts = {
      monospace = {
        package = pkgs-unstable.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs-unstable.dejavu_fonts;
        name = "DejaVu Sans";
      };
      serif = {
        package = pkgs-unstable.dejavu_fonts;
        name = "DejaVu Serif";
      };
    };
    targets = {
      nixvim.transparentBackground.main = true;
    };
  };

  # Kde Connect
  programs.kdeconnect = {
    enable = true;
  };

  # LD fix
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs-unstable; [
    # add any missing dynamic libraries for unpackaged programs here
  ];

  # sudo
  security.sudo = {
    execWheelOnly = true;
    package = pkgs-unstable.sudo.override { withInsults = true; };
  };

  # Enable bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  hardware.pulseaudio.support32Bit = true;
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
    initialPassword = "123456";
    description = "Lilijoy";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    package =
      with pkgs-unstable;
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

  # Mullvad vpn
  services.mullvad-vpn = {
    enable = true;
    package = pkgs-unstable.mullvad-vpn;
  };

}

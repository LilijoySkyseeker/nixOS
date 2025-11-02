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
    ../modules/nixos/wooting.nix
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
      distrobox
      caligula # cli burning tool
      scrcpy
      isd

      yubikey-manager
      distrobox
      bitwarden
      thunderbird
      vscode-fhs
      jellyfin-media-player
      easyeffects
      qpwgraph
      youtube-music
      libreoffice
      vlc
      r2modman
      yubioath-flutter
      nicotine-plus
      vial
      element-desktop
      ungoogled-chromium
      python313Packages.nomadnet
      rns
      signal-desktop

      texliveFull

      atkinson-hyperlegible-next
      atkinson-hyperlegible-mono

      # closed source
      obsidian
      spotify

      # restrictive licences
      grayjay
    ])
    ++ (with pkgs-stable; [
      feishin
      prismlauncher
      vesktop
      discord
      kdePackages.kdenlive
      wl-clipboard # for waydroid
      quickemu
      qbittorrent
      texlive.combined.scheme-full

      # closed source
      bambu-studio
    ]);

  # android
  programs.adb.enable = true;

  # Waydroid
  virtualisation.waydroid.enable = true;

  # Appimage
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # distrobox and other docker
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  #qmk, allow udev rules
  hardware.keyboard.qmk.enable = true;

  #flatpak
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = false;
    packages = [
      "info.beyondallreason.bar"
    ];
  };

  # udev rules
  services.udev.packages = [
    pkgs-unstable.via
    pkgs-unstable.vial
  ];
  services.udev.extraRules = ''
    # 8bitdo 2.4 GHz / Wired
    KERNEL=="hidraw*", ATTRS{idVendor}=="2dc8", MODE="0660", TAG+="uaccess"

    # 8bitdo Bluetooth
    KERNEL=="hidraw*", KERNELS=="*2DC8:*", MODE="0660", TAG+="uaccess"

    # plover
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
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
      inputs.plover-flake.homeManagerModules.plover
    ];
    home.stateVersion = "23.11";
    home.username = "lilijoy";
    home.homeDirectory = "/home/lilijoy";
    programs.home-manager.enable = true;

    programs.plover = {
      enable = true;
      package = inputs.plover-flake.packages.${pkgs-unstable.system}.plover-full;
    };
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
  environment.variables = {
    FLAKE = "/home/lilijoy/dotfiles";
    NH_FLAKE = "/home/lilijoy/dotfiles";
  };

  # Stylix
  stylix = {
    enable = true;
    autoEnable = true;
    base16Scheme = "${pkgs-stable.base16-schemes}/share/themes/gruvbox-dark-soft.yaml";
    image = ../files/gruvbox-dark-rainbow.png;
    polarity = "dark";
    cursor.package = pkgs-unstable.capitaine-cursors-themed;
    cursor.name = "Capitaine Cursors";
    cursor.size = 24;
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
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  services.pulseaudio.support32Bit = true;
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
      "dialout" # for plover
      "input" # for plover
    ];
  };

  # steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
  };
  hardware.steam-hardware.enable = true;

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

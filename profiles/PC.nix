{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.stylix.nixosModules.stylix
    ../modules/nixos/virtual-machines.nix # (also needs home manager config)
    ../modules/nixos/tooling.nix
    ./default.nix
  ];

  # System installed pkgs
  environment.systemPackages = with pkgs; [
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
    gnome-extension-manager
    baobab # gnome disk usage utilty
    gnome-tweaks
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
    qalculate-gtk
    libreoffice
    vial
    vlc
    r2modman
    yubioath-flutter
    feishin
    prismlauncher

    # closed source
    obsidian
    spotify
    vesktop
  ];

  # home-manager
  home-manager.users.lilijoy = {
    imports = [ ../modules/home-manager/tooling.nix ];
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
  programs.nh.flake = ../.;

  # Stylix
  stylix = {
    enable = true; # TESTING
    autoEnable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = ../files/gruvbox-dark-rainbow.png;
    polarity = "dark";
    cursor.package = pkgs.capitaine-cursors-themed;
    cursor.name = "Capitaine Cursors";
    targets = {
      nixvim.transparentBackground.main = true;
    };
  };

  # Kde Connect
  programs.kdeconnect = {
    enable = true;
  };

  # Docker
  virtualisation.docker = {
    enable = true;
  };

  # LD fix
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # add any missing dynamic libraries for unpackaged programs here
  ];

  # sudo
  security.sudo = {
    execWheelOnly = true;
    package = pkgs.sudo.override { withInsults = true; };
  };

  # Enable bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
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
      with pkgs;
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
    package = pkgs.mullvad-vpn;
  };

}

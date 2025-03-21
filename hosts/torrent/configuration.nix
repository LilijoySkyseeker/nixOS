{
  pkgs-unstable,
  pkgs-stable,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../profiles/PC.nix
    ../../modules/nixos/wooting.nix
    ../../modules/nixos/copypartymount.nix
    ../../modules/nixos/kde.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs-unstable; [
      ckan # ksp mod manager
    ])
    ++ (with pkgs-stable; [
      filelight # kde disk ussage
      qalculate-qt
      kile
      texlive.combined.scheme-full
    ]);

  # kde partition manager
  programs.partition-manager.enable = true;

  # networking
  networking.networkmanager = {
    enable = true;
    insertNameservers = [
      "8.8.8.8"
      "1.1.1.1"
    ];
  };

  # zfs snapshots
  services.sanoid = {
    enable = true;
    extraArgs = [ "--verbose" ];
    interval = "minutely";
    settings = {
      "zroot/local/root".use_template = "working";
      "zroot/local/home".use_template = "working";
      template_working = {
        frequent_period = 1;
        frequently = 59;
        hourly = 24;
        daily = 1;
        weekly = 0;
        monthly = 0;
        yearly = 0;
        autosnap = "yes";
        autoprune = "yes";
      };
    };
  };
  systemd.services.sanoid.serviceConfig = {
    User = lib.mkForce "root";
  };

  # cpu power management
  powerManagement.cpuFreqGovernor = "performance";

  # home manager
  home-manager.users.lilijoy = {
    imports = [ ../../modules/home-manager/kde.nix ];
  };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Define your hostname.
  networking.hostName = "torrent";

  # Set extra groups
  users.users.lilijoy.extraGroups = [ "" ];

  # zfs support
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "0376f9ae";
  fileSystems."/nix".neededForBoot = true;
}

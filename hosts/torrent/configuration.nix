{
  pkgs-unstable,
  pkgs-stable,
  lib,
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../profiles/PC.nix
    ../../modules/nixos/kde.nix
    ../../modules/nixos/pull-deploy.nix
    ../../modules/nixos/nfs-homelab-mounts.nix
    ../../modules/nixos/iso-autobuild.nix
    ../../modules/nixos/build-worker.nix
  ];
  home-manager.users.lilijoy.imports = [ ];

  myPullDeploy = {
    enable = true;
    flakeDir = "/home/lilijoy/dotfiles";
    hostAttr = "torrent";
    dates = "Thu 03:00";
    autoReboot = false;
    operation = "boot";
  };

  # rebuild the recovery iso into ~/Downloads every time pull-deploy
  # successfully updates this host, for manual copying onto Ventoy
  myIsoAutobuild = {
    enable = true;
    flakeDir = "/home/lilijoy/dotfiles";
    buildUser = "lilijoy";
    isoAttr = "isoimage";
    triggeredBy = [ "pull-deploy.service" ];
  };

  # distributed builds — torrent is the strongest machine in the fleet,
  # so it submits its own rebuilds to homelab and accepts builds
  # submitted by homelab/thinkpad. Always on AC (desktop), so no
  # acGated. See .claude/plans/quirky-herding-teapot.md.
  myBuildWorker = {
    enable = true;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJlNXC+Q2BiJvRqBFkSffDHEzSt2QEQxQLezW5+SBwk3 nix-builder@torrent"
    ];
  };
  sops.secrets.builder_key_homelab = { };
  sops.secrets.builder_key_thinkpad = { };
  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "homelab";
      sshUser = "nix-builder";
      sshKey = config.sops.secrets.builder_key_homelab.path;
      protocol = "ssh-ng";
      # TODO before deploying: fetch and set publicHostKey via
      # `ssh-keyscan homelab | grep ed25519 | awk '{print $3}' | base64 -w0`
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # TODO confirm live via `nproc` on homelab before deploying
      maxJobs = 8;
      speedFactor = 2;
    }
    {
      hostName = "thinkpad";
      sshUser = "nix-builder";
      sshKey = config.sops.secrets.builder_key_thinkpad.path;
      protocol = "ssh-ng";
      # TODO before deploying: fetch and set publicHostKey via
      # `ssh-keyscan thinkpad | grep ed25519 | awk '{print $3}' | base64 -w0`
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # TODO confirm live via `nproc` on thinkpad before deploying
      maxJobs = 4;
      speedFactor = 1;
    }
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs-unstable; [
      # closed source
      bambu-studio
    ])
    ++ (with pkgs-stable; [
    ]);

  # drivers, r8125 for ethernet, look for when kernel is 6.7+ to try wifi and bt drivers, https://wireless.docs.kernel.org/en/latest/en/users/drivers/mediatek.html, mt7925
  boot.extraModulePackages = with config.boot.kernelPackages; [ r8125 ];
  boot.kernelModules = [ "r8125" ];
  nixpkgs.config.allowBroken = true; # check on next stable release to see if needed

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

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Define your hostname.
  networking.hostName = "torrent";

  # zfs support
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "0376f9ae";
  fileSystems."/nix".neededForBoot = true;
}

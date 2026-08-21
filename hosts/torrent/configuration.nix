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
  ];

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

  # push home+root snapshots to homelab's zbackup pool over tailscale
  # (see TODO.md "syncoid push backups" for the design)
  sops.secrets.torrent_backup_push_key = {
    owner = "backup-push"; # readable only by the dedicated backup-push user, not root-wide
  };
  myBackupPush = {
    enable = true;
    targetHost = "backup-recv@homelab";
    identityFile = config.sops.secrets.torrent_backup_push_key.path;
    datasets = {
      "zroot/local/home" = "zbackup/backup/torrent/home";
      "zroot/local/root" = "zbackup/backup/torrent/root";
    };
  };

  # home holds large, frequently-churned Steam/game libraries — zfs
  # snapshots pin the space of anything they touch, so heavy install/
  # uninstall cycles can eat free space fast even with sanoid's normal
  # retention. Auto-prune oldest snapshots under pressure; see
  # `systemctl start zfs-emergency-prune.service` for an immediate
  # manual escape hatch. Safe alongside myBackupPush above since
  # --create-bookmark already preserves incremental replication history
  # independent of which local snapshots survive.
  myZfsSpaceGuard = {
    enable = true;
    pool = "zroot";
    datasets = [
      "zroot/local/home"
      "zroot/local/root"
    ];
    freeThresholdPercent = 15;
  };
}

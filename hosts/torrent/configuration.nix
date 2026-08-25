{
  pkgs-unstable,
  pkgs-stable,
  lib,
  config,
  vars,
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

  # zfs snapshots, and serving them to homelab's puller (zrepl; replaced
  # sanoid + the syncoid-based myBackupPush).
  #
  # This host is the passive side of replication: it answers homelab's
  # pulls but never initiates a connection and holds no credential for
  # homelab. Backup retention is decided by homelab's pull job
  # (keep_sender), so a compromise here cannot delete backup history.
  #
  # Snapshotting and a local prune ceiling are handled on-box by the
  # module's snap job, independent of homelab being reachable -- without
  # that, an extended homelab outage would mean no pruning here at all,
  # since under pull the puller owns retention.
  myZrepl = {
    enable = true;
    preserveLegacySnapshots = false;
    serve = {
      enable = true;
      datasets = [
        "zroot/local/home"
        "zroot/local/root"
      ];
      clients.homelab.publicKey = vars.zreplPullerKey;
    };
  };

  # sshd exists on this host solely to carry zrepl's stdinserver
  # transport. It is reachable only over the tailnet (no openFirewall), and
  # root login is forced-commands-only, so the single forced command in
  # root's authorized_keys -- rendered by the zrepl module -- is the only
  # thing an SSH connection here can ever do. There are no other root keys
  # on this host to weaken that.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "forced-commands-only";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # auto snapshot pruning at low disk space
  # manual `systemctl start zfs-emergency-prune.service`
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

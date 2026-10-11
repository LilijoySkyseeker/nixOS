{
  pkgs-unstable,
  pkgs-stable,
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
    # root has no SSH identity here; reuse lilijoy's, already trusted by origin
    sshKeyPath = "/home/lilijoy/.ssh/id_ed25519";
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

  # zroot root dataset's own properties, applied live as well as at disko install
  myZfsDatasetProperties."zroot" = vars.zfsRootFsOptions;

  # zfs snapshots served to homelab's zrepl puller; passive side: holds no
  # homelab credential and homelab owns retention, so a compromise here can't
  # delete backup history. the local snap job prunes even if homelab is away
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

  # sshd only carries zrepl's stdinserver transport: tailnet-only, root is
  # forced-commands-only, and there must be no other root keys
  services.openssh = {
    enable = true;
    openFirewall = false;
    # also disables scp (sftp-based in modern OpenSSH); zrepl uses neither
    allowSFTP = false;
    settings = {
      PermitRootLogin = "forced-commands-only";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;

      # rest of docs/hardening.md's SSH baseline; in `settings`, not
      # `extraConfig`: sshd_config is first-directive-wins and `settings`
      # renders first. trailing values are the OpenSSH 10.4p1 defaults
      AuthenticationMethods = "publickey"; # default: any
      AllowAgentForwarding = false; # default: yes
      AllowStreamLocalForwarding = false; # default: yes
      AllowTcpForwarding = false; # default: yes
      PermitTunnel = "no"; # default: no
      ClientAliveInterval = 60; # default: 0, no idle timeout
      ClientAliveCountMax = 5; # default: 3
    };
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # emergency space reclaim: `systemctl start zfs-emergency-prune.service`
  myZfsSpaceGuard = {
    enable = true;
    datasets = [
      "zroot/local/home"
      "zroot/local/root"
    ];
  };

  # backup restore-test canaries: content must match homelab's
  # myBackupRestoreTest.zbackup.targets byte for byte
  myBackupCanary.paths = {
    "/home/.backup-canary/canary.txt" = "backup-canary torrent zroot/local/home v1";
    "/.backup-canary/canary.txt" = "backup-canary torrent zroot/local/root v1";
  };

  # failed-unit / stuck-switch alerts to Discord; one fleet-wide webhook,
  # shared on purpose (write-only sink, worst case is forged alerts)
  sops.secrets.discord_webhook = {
    owner = "health-check";
    group = "health-check";
  };

  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.discord_webhook.path;
    # off: smartctl needs the disk group + CAP_SYS_RAWIO (root-equivalent), and
    # the fleet-wide smartd already reaches a human via the graphical session
    checkSmart = false;
    # no backupStaleness: homelab's own myHealthAlerts watches this host's replicas
    #
    # profile mtime catches a pull-deploy that skips (guards exit 0, so no
    # failed unit); 504h = 21 days, weekly deploys plus two weeks of slack
    staleMarkerFiles = {
      "/nix/var/nix/profiles/system" = 504;
    };
  };
}

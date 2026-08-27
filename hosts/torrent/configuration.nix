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
    # Disabled 2026-08-27 with the rest of the fleet's schedules — see
    # hosts/homelab/configuration.nix's myAutoUpdate for the reasoning,
    # and TODO.md's "rebuild the update/build/deploy pipeline properly".
    # The service stays: `systemctl start pull-deploy` still works.
    scheduleEnable = false;
    # root has no home-manager profile (and thus no SSH identity of its
    # own) on this PC host -- reuse lilijoy's, whose known_hosts/agent
    # already trusts and authenticates to the origin remote day-to-day.
    sshKeyPath = "/home/lilijoy/.ssh/id_ed25519";
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
    # Modern OpenSSH implements scp over the SFTP protocol, so this
    # removes both scp and sftp. Nothing copies files to this host --
    # zrepl uses ssh+stdinserver, not sftp -- and there is no interactive
    # login here to use them from: root is forced-commands-only and no
    # non-root user has an authorized_keys (checked on-box).
    allowSFTP = false;
    settings = {
      PermitRootLogin = "forced-commands-only";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;

      # The rest of docs/hardening.md's SSH baseline, which this host was
      # missing entirely (F-P5-07): of the nine directives the rule
      # lists, only three were rendered, so OpenSSH's own defaults
      # applied to the other six -- and three of those defaults are the
      # opposite of what the rule asks for.
      #
      # These go in `settings`, not `extraConfig`, deliberately.
      # sshd_config is first-directive-wins, and the module emits
      # `settings` into the configFile half that sshd reads *first*
      # (sshd.nix:82-89, :893), so a directive written here cannot be
      # silently overridden. The same set written into `extraConfig` on
      # homelab and vps is inert for exactly that reason -- it works
      # there only because nothing else emits those keys, i.e. by luck
      # (threat model §7.2, F-P2-09/F-P3-18).
      #
      # Each "was" is the pinned OpenSSH 10.4p1's own documented default,
      # read out of sshd_config.5 rather than assumed. Note the third
      # one: docs/hardening.md claimed AllowTcpForwarding already
      # defaults to `no`. It does not -- it defaults to `yes`, so
      # forwarding has been on everywhere it was not explicitly set. That
      # sentence is corrected in the same commit as this change.
      AuthenticationMethods = "publickey"; # was: any
      AllowAgentForwarding = false; # was: yes
      AllowStreamLocalForwarding = false; # was: yes
      AllowTcpForwarding = false; # was: yes
      PermitTunnel = "no"; # was: no -- the one already correct, by accident
      ClientAliveInterval = 60; # was: 0, i.e. no idle timeout at all
      ClientAliveCountMax = 5; # was: 3
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

  # failed-unit / stuck-switch alerts to Discord (F-P7-09)
  #
  # myPullDeploy runs unattended every Thursday, and until now a build
  # error, a fetch failure or a failed switch on this host was visible
  # only in the local journal: health-alerts was imported for homelab and
  # vps only, so nothing anywhere reported that a laptop had quietly
  # stopped deploying. The failed-units check is the whole point of
  # enabling it here -- pull-deploy.service entering "failed" is exactly
  # what it catches.
  #
  # It does NOT yet catch a *skipped* deploy. Every guard in
  # deploy-guards.nix ends in `exit 0`, so a skip is recorded as success
  # and never enters `systemctl --failed`; closing that needs the
  # deploy-marker half of F-P7-09, which is not this change.
  #
  # Reusing homelab's webhook rather than minting a per-host one: adding
  # a key is a user-only sops edit, and under .sops.yaml's single
  # creation_rules entry every host already decrypts all 31 secrets, so
  # this grants no access this host did not already have. Re-point it at
  # a per-host key when .sops.yaml is split per path (F-P8-01, F-P8-05).
  sops.secrets.homelab_discord_webhook = {
    owner = "health-check";
    group = "health-check";
  };
  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.homelab_discord_webhook.path;
    # checkSmart is the one option here that costs something: the module
    # grants the unit the "disk" group plus CAP_SYS_RAWIO so smartctl can
    # issue its SG_IO ioctls, and /dev/sd* is root:disk 0660 -- read *and
    # write* on every raw block device, i.e. root-equivalent. homelab
    # pays that because it is headless, where smartd's wall/x11 sinks
    # reach nobody. This host has a graphical session, so the fleet-wide
    # services.smartd (profiles/default.nix) already reaches a human --
    # paying a root-equivalent grant for a duplicate alert is a bad
    # trade.
    checkSmart = false;
    # checkZfs stays on and needs no privilege: /dev/zfs is 0666, and
    # `zpool status -x` was verified to succeed as the unprivileged
    # health-check user on homelab.
    #
    # backupStaleness is deliberately absent. This host is the passive
    # side of replication, and homelab's own myHealthAlerts already
    # watches zbackup/backup/torrent/* at a 336h threshold -- measuring
    # it again here would only report on the puller's behalf.
    #
    # The failed-units check above catches a pull-deploy that *fails*. It
    # cannot catch one that *skips*: every guard exits 0, so a tree left
    # dirty or parked on a branch (easy here -- flakeDir is this user's own
    # ~/dotfiles, which is a working checkout, not a deploy-only clone)
    # silently stops this host updating with no failed unit anywhere.
    # Watching the profile symlink measures the outcome instead.
    #
    # 504h = 21 days: dates is weekly and minSwitchInterval is 7 days, so
    # 14 days is the normal ceiling, plus a week of slack. This is a
    # desktop that is usually powered on, so it needs no laptop-style
    # allowance for long absences.
    staleMarkerFiles = {
      "/nix/var/nix/profiles/system" = 504;
    };
  };
}

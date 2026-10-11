{
  config,
  pkgs-stable,
  lib,
  vars,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  # System installed pkgs
  environment.systemPackages = with pkgs-stable; [
    zfs
    restic
    backblaze-b2
    btop
  ];

  boot = {
    # disable staggered hdd spin up
    extraModprobeConfig = ''
      options libahci ignore_sss=1
    '';

    # force BOT instead of UAS for the TerraMaster enclosure's ASMedia bridge
    # (174c:55aa), which silently corrupts in-flight data under UAS load
    kernelParams = [ "usb-storage.quirks=174c:55aa:u" ];
  };

  # tailscale UDP GRO forwarding compatibility, enp3s0 is this host's real NIC
  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = [ "routable" ];
      script = ''
        ${lib.getExe pkgs-stable.ethtool} -K enp3s0 rx-udp-gro-forwarding on rx-gro-list off
      '';
    };
  };

  # docker settings
  # SECURITY: the LAN NIC has a public IPv6 and myDockerPublishGuard is
  # IPv4-only; do not set `ipv6 = true` or restore userland-proxy without
  # extending the guard to ip6tables, or the game ports go internet-facing
  virtualisation.docker.daemon.settings = {
    userland-proxy = false;
  };

  # docker-published ports bypass networking.firewall.interfaces, so the
  # game ports' wg0/tailscale0 scoping is enforced here in DOCKER-USER;
  # no LAN exception on purpose
  myDockerPublishGuard = {
    enable = true;
    allowedInterfaces = [
      "wg0" # public players, DNAT'd in by vps (its networking.nat.forwardPorts)
      "tailscale0" # our own devices
    ];
    ports = [
      {
        port = 25565;
        protocol = "tcp";
        comment = "minecraft: java edition";
      }
      {
        port = 19132;
        protocol = "udp";
        comment = "minecraft: geyser bedrock listener";
      }
      {
        port = 34197;
        protocol = "udp";
        comment = "factorio";
      }
    ];
  };

  # oci containers
  virtualisation.oci-containers.backend = "docker";

  # container uid 0 != host uid 0; per-path uid migrations live in
  # modules/services/{factorio,minecraft}.nix next to their paths
  myDockerUserns.enable = true;

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

  # GPU hardware acceleration for Jellyfin
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs-stable; [
      intel-media-driver # VAAPI/QSV for Kaby Lake HD 630
      vpl-gpu-rt
    ];
  };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    # nvidiaPackages.stable (production) dropped Pascal support upstream
    # plan: 2026-09-03-fix-homelab-jellyfin-ffmpeg-high-cpu-nvidia-driver-dropped-gtx-1050.md
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    # GP107 (Pascal) predates Nvidia's open-source kernel modules (Turing+ only)
    open = false;
    modesetting.enable = true;
    nvidiaSettings = false; # headless, no GUI settings app needed
  };

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # networking
  networking.networkmanager = {
    enable = true;
    insertNameservers = [
      "8.8.8.8"
      "1.1.1.1"
    ];
  };

  # directory permissions
  # don't lock down /srv itself (0770 root breaks traversal for its non-root
  # services); its secrets are protected at the leaves, in each service module
  systemd.tmpfiles.rules = [
    "A /storage - - - - group:multimedia:rwx"
    "A /storage-bulk - - - - group:multimedia:rwx"
  ];

  # sops
  sops.secrets = {
    homelab_backblaze_rclone_config = { };
    homelab_backblaze_restic_password = { };
    discord_webhook = {
      owner = "health-check";
      group = "health-check";
    };
  };

  # restic to backblaze with rclone https://restic.readthedocs.io/en/latest/050_restore.html
  services.restic.backups = {
    backblazeWeekly = {
      initialize = true;
      createWrapper = true; # usable with restic-backblazeWeekly
      passwordFile = "${config.sops.secrets.homelab_backblaze_restic_password.path}";
      # using rclone because the normal restic s3 b2 integration did not work with both the service and the wrapper, "Daily" name is legacy
      repository = "rclone:backblazeDaily:restic21029709384";
      rcloneOptions = {
        transfers = "32";
        b2-hard-delete = "false";
      };
      rcloneConfigFile = config.sops.secrets.homelab_backblaze_rclone_config.path;
      # mount each dataset's latest snapshot under $RUNTIME_DIRECTORY, not
      # /tmp: a pre-planted symlink there would be followed by mkdir -p
      # datasets: legacy list + every offsite-tier myDatasets root, recursive
      # (`zfs list -r` orders parents first); newline-delimited since dataset
      # names may contain spaces
      backupPrepareCommand = ''
        datasets="zroot/local/state"$'\n'"zdata/storage/storage"

        for root in zroot/offsite zdata/offsite; do
          if names=$(zfs list -H -o name -t filesystem -r "$root" 2>/dev/null); then
            datasets="$datasets"$'\n'"$names"
          fi
        done

        printf '%s\n' "$datasets" | while IFS= read -r dataset; do
          [ -n "$dataset" ] || continue
          snapshot=$(zfs list -H -t snapshot -o name -s creation -r "$dataset" | tail -n 1)
          if [[ -n "$snapshot" ]]; then
            mkdir -p "$RUNTIME_DIRECTORY/$snapshot"
            mount -t zfs "$snapshot" "$RUNTIME_DIRECTORY/$snapshot"
          fi
        done
        echo "### Mounted Snapshots ###"
      '';
      backupCleanupCommand = ''
        # unmount only what this run mounted; cut, not awk: no gawk on this unit's path
        grep " on $RUNTIME_DIRECTORY/" /proc/mounts \
          | cut -d' ' -f2 \
          | tac \
          | xargs -r -I{} umount -t zfs {}
        echo "### Unmounted Snapshots ###"
      '';
      user = "root";
      paths = [ "/run/restic-backups-backblazeWeekly" ];
      timerConfig = {
        OnCalendar = "Fri 03:00:00";
        # no catch-up run at boot: it would pile ~2.9TiB of I/O onto zrepl's
        # post-boot catch-up; a skipped week still pages via staleMarkerFiles
        Persistent = false;
      };
      # daily means keep n runs, so actually 2 snapshots, 1 per week
      pruneOpts = [
        "--retry-lock 15m"
        "--keep-daily 2"
      ];
      runCheck = true;
      checkOpts = [
        "--retry-lock 15m"
        "--read-data-subset=1%"
      ];
    };
  };
  systemd.services.restic-backups-backblazeWeekly = {
    path = with pkgs-stable; [
      # necessary for pre and post scripts
      zfs
      coreutils-full
      mount
      umount
      findutils
      bash
    ];
    serviceConfig = {
      NoNewPrivileges = true;
      PrivateTmp = lib.mkForce false;
      TimeoutStartSec = "1w";
      StateDirectory = "restic-backups-backblazeWeekly";
      # 0700: holds the mounted snapshots of the persisted-state and media trees
      RuntimeDirectory = "restic-backups-backblazeWeekly";
      RuntimeDirectoryMode = "0700";
      # backblaze bucket config
      ExecStartPre = "${pkgs-stable.rclone}/bin/rclone backend lifecycle backblazeDaily:restic21029709384 --config ${config.sops.secrets.homelab_backblaze_rclone_config.path} -o daysFromHidingToDeleting=1";
      # time since last success timer for alerting
      ExecStartPost = "${pkgs-stable.coreutils}/bin/touch /var/lib/restic-backups-backblazeWeekly/last-success";
    };
  };

  # backup restore-and-verify canaries; content strings must match each
  # source host's myBackupCanary.paths byte for byte
  myBackupCanary.paths = {
    "/storage/.backup-canary/canary.txt" = "backup-canary homelab zdata/storage/storage v1";
    "/storage-bulk/.backup-canary/canary.txt" = "backup-canary homelab zdata/storage/storage-bulk v1";
    "/nix/state/.backup-canary/canary.txt" = "backup-canary homelab zroot/local/state v1";
  };

  myBackupRestoreTest = {
    zbackup = {
      enable = true;
      targets = {
        "zbackup/backup/homelab/zdata/storage/storage".expectedContent =
          "backup-canary homelab zdata/storage/storage v1";
        "zbackup/backup/homelab/zdata/storage/storage-bulk".expectedContent =
          "backup-canary homelab zdata/storage/storage-bulk v1";
        "zbackup/backup/homelab/zroot/local/state".expectedContent =
          "backup-canary homelab zroot/local/state v1";
        "zbackup/backup/torrent/zroot/local/home".expectedContent =
          "backup-canary torrent zroot/local/home v1";
        "zbackup/backup/torrent/zroot/local/root".expectedContent =
          "backup-canary torrent zroot/local/root v1";
        "zbackup/backup/thinkpad/zroot/local/home".expectedContent =
          "backup-canary thinkpad zroot/local/home v1";
        "zbackup/backup/thinkpad/zroot/local/root".expectedContent =
          "backup-canary thinkpad zroot/local/root v1";
      };
    };
    restic = {
      enable = true;
      wrapperCommand = "restic-backblazeWeekly";
      # must match backupPrepareCommand's RuntimeDirectory above
      mountPrefix = "/run/restic-backups-backblazeWeekly";
      triggerUnit = "restic-backups-backblazeWeekly.service";
      # only the datasets restic actually backs up (see backupPrepareCommand)
      targets = {
        "zroot/local/state".expectedContent = "backup-canary homelab zroot/local/state v1";
        "zdata/storage/storage".expectedContent = "backup-canary homelab zdata/storage/storage v1";
      };
    };
  };

  # import zbackup at boot: no fileSystems entry references it (all
  # mountpoint=none), so nixpkgs otherwise generates no import unit
  boot.zfs.extraPools = [ "zbackup" ];

  # zfs snapshots + replication (zrepl)
  # pull, never push: zrepl's receiver exposes DestroySnapshots, so a
  # compromised source must have no handle on this host's backup history
  # restart on key rotation; a killed pull just retries next interval
  sops.secrets.homelab_zrepl_key.restartUnits = [ "zrepl.service" ];

  # zrepl's ssh has no TTY to accept an unknown host key, so pin source hosts' keys
  programs.ssh.knownHosts.torrent = {
    hostNames = [ "torrent" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJESBjkAOLvKdaRlpAg/CiBh/WvW0lzb4QScEw40o3Kc";
  };

  programs.ssh.knownHosts.thinkpad = {
    hostNames = [ "thinkpad" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF2TU4+7NDf2QOY8x/48KYt/1WX1jtCRhUOwKgYW7pNY";
  };

  myZrepl = {
    enable = true;

    pull.remotes = {
      # received filesystems land at <rootFs>/<full source dataset path>,
      # e.g. zbackup/backup/torrent/zroot/local/home
      torrent = {
        host = "torrent";
        identityFile = config.sops.secrets.homelab_zrepl_key.path;
        rootFs = "zbackup/backup/torrent";
      };
      thinkpad = {
        host = "thinkpad";
        identityFile = config.sops.secrets.homelab_zrepl_key.path;
        rootFs = "zbackup/backup/thinkpad";
      };
    };

    local = {
      enable = true;
      datasets = [
        "zdata/storage/storage"
        "zdata/storage/storage-bulk"
        "zroot/local/state"
      ]
      # onsite/offsite myDatasets entries join local replication
      # automatically; homelab is the "local" role for its own datasets.
      ++ config.myDatasetsReplicated;
      rootFs = "zbackup/backup";
      clientIdentity = "homelab";
    };

    preserveLegacySnapshots = false;
  };

  # cpu power management
  powerManagement.cpuFreqGovernor = "performance";

  # disable emergencymode
  systemd.enableEmergencyMode = false;

  # lock down users
  users.mutableUsers = false;
  #users.users.root.hashedPassword = "!";

  # Define your hostname.
  networking.hostName = "homelab";

  # weekly deploy of master, servers first: homelab Tue, vps Wed, PCs Thu,
  # so an update that breaks the servers hasn't yet reached the PCs used
  # to fix them. homelab is slow to build, hence a day each.
  # by hand: cd /etc/nixos && git pull && nh os switch
  myPullDeploy = {
    enable = true;
    flakeDir = "/etc/nixos";
    hostAttr = "homelab";
    dates = "Tue 03:00";
    operation = "switch";
    autoReboot = true;
    # the weekly restic->Backblaze run can take days (~2.9TiB), and a switch
    # restarts any changed unit, so defer rather than kill it
    protectedUnits = [ "restic-backups-backblazeWeekly.service" ];
  };

  # vps can't build its own closure (~2GB RAM), so homelab builds it and
  # pushes it over SSH as the unprivileged vps-deploy user (activation via
  # nixos-rebuild's run0 elevator; see hosts/vps/configuration.nix)
  sops.secrets.homelab_vps_deploy_key = { };
  myPushDeploy = {
    enable = true;
    flakeDir = "/etc/nixos";
    hostAttr = "vps";
    targetHost = "vps-deploy@vps";
    identityFile = config.sops.secrets.homelab_vps_deploy_key.path;
    dates = "Wed 03:00";
  };
  # no catch-up run at boot after an outage: it would contend with zrepl's
  # own post-boot catch-up replication; next week's run is soon enough
  systemd.timers.pull-deploy.timerConfig.Persistent = lib.mkForce false;
  systemd.timers.push-deploy-vps.timerConfig.Persistent = lib.mkForce false;

  # discord alerts for ZFS/SMART/failed-unit/stuck-switch issues
  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.discord_webhook.path;
    interval = "*:0/15";
    # hours; zrepl replicates every 15m
    backupStaleness = {
      "zbackup/backup/homelab/zdata/storage/storage" = 6;
      "zbackup/backup/homelab/zdata/storage/storage-bulk" = 6;
      "zbackup/backup/homelab/zroot/local/state" = 6;
      # PCs can be off for long stretches; 336h = 2 weeks
      "zbackup/backup/torrent/zroot/local/home" = 336;
      "zbackup/backup/torrent/zroot/local/root" = 336;
      "zbackup/backup/thinkpad/zroot/local/home" = 336;
      "zbackup/backup/thinkpad/zroot/local/root" = 336;
    };
    staleMarkerFiles = {
      # weekly restic: 312h = 13 days, deliberately not 336h (2 weeks), which
      # coincides with the next scheduled run and lets it mask a missed one
      "/var/lib/restic-backups-backblazeWeekly/last-success" = 312;
      # a failed deploy pages via the failed-units check, but a skipped one
      # exits 0, so watch the outcome: the profile symlink's mtime is the
      # last activation by any route. 504h = 21 days: weekly deploys, plus
      # room for a restic deferral and a week of slack.
      "/nix/var/nix/profiles/system" = 504;
      # no input update merged in 30 days; mtime changes only when
      # pull-deploy fast-forwards a new lock
      "/etc/nixos/flake.lock" = 720;
      # touched by an all-PASS scripts/restore-drill run
      # (docs/procedures/backup-restore.md); 2160h = 90 days, quarterly drills
      "/var/lib/restore-drill/last-drill-success" = 2160;
      # myBackupRestoreTest's canary restore-and-verify, catches it stopping entirely
      "/var/lib/backup-restore-test/zbackup-last-success" = 30; # daily check
      "/var/lib/backup-restore-test/restic-last-success" = 312; # matches restic's own staleness threshold above
    };
  };

  # ssh server
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    enable = true;
    allowSFTP = true;
    # LAN NIC has a public IPv6; port 22 is opened on tailscale0 only, below
    openFirewall = false;
    settings.KbdInteractiveAuthentication = false;
    # must be a structured option: sshd is first-directive-wins and the
    # module renders its own default before extraConfig
    settings.PasswordAuthentication = false;
    extraConfig = ''
      PermitRootLogin = prohibit-password
      AllowTcpForwarding no
      X11Forwarding no
      AllowAgentForwarding no
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
      PermitTunnel no
      ClientAliveInterval 60
      ClientAliveCountMax 5
    '';
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # zfs support
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "e0019fd8";

  # tailscale: advertise the LAN subnet and act as an exit node
  # overrides the fleet's "client" default (also sets ip forwarding); without
  # it the advertise flags below silently stop working
  services.tailscale.useRoutingFeatures = lib.mkForce "both";
  services.tailscale.extraUpFlags = lib.mkAfter [
    "--advertise-routes=192.168.1.0/24"
    "--advertise-exit-node"
  ];

  # wireguard: dial out to the vps as our public endpoint from behind CGNAT
  # wireguard-wg0 is a RemainAfterExit oneshot that reads the key once, so a
  # rotation needs an explicit restart (cycles the peer units too)
  sops.secrets.homelab_wireguard_private_key.restartUnits = [ "wireguard-wg0.service" ];
  # same PSK as vps's wireguard_vps_homelab_psk
  sops.secrets.wireguard_vps_homelab_psk.restartUnits = [ "wireguard-wg0.service" ];
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.2/24" ];
    privateKeyFile = config.sops.secrets.homelab_wireguard_private_key.path;
    peers = [
      {
        # vps
        publicKey = "ngxeCJV7bMtJQS1x93UhEuiWdLNXbCAsESrN4bcOrxk=";
        presharedKeyFile = config.sops.secrets.wireguard_vps_homelab_psk.path;
        # IPv4, not IPv6: homelab's rotating IPv6 privacy addresses leave
        # vps's learned endpoint stale and the tunnel silently dies
        endpoint = "137.184.45.18:51820";
        allowedIPs = [ "10.100.0.1/32" ];
        # CGNAT mappings expire without periodic traffic
        persistentKeepalive = 25;
      }
    ];
  };

  # .zfs/snapshot is world-traversable and exposes old secrets at their old
  # modes; takes full effect only after a mount cycle, not just a switch
  myZfsDatasetProperties."zroot/local/state".snapdir = "disabled";

  # pool root datasets' properties, applied live as well as at disko install
  myZfsDatasetProperties."zroot" = vars.zfsRootFsOptions;
  myZfsDatasetProperties."zdata" = vars.zfsRootFsOptions;
  myZfsDatasetProperties."zbackup" = vars.zfsRootFsOptions;

  # myDatasets: per-service ZFS datasets, tiered.
  # a new entry needs a manual zfs create on the live host before deploy
  # (docs/procedures/new-service.md)
  myDatasets = {
    # jellyfin cacheDir + /var/lib/docker reclassified persist
    # managePersistence = false: entries already exist elsewhere
    # (jellyfin.nix's cacheDir, the /var/lib/docker line below)
    # no owner/group either, they'd have no effect
    "zroot/persist/jellyfin-cache" = {
      tier = "persist";
      mountpoint = config.services.jellyfin.cacheDir;
      managePersistence = false;
    };
    "zroot/persist/docker" = {
      tier = "persist";
      mountpoint = "/var/lib/docker";
      managePersistence = false;
    };
  };

  # impermanance
  fileSystems."/nix/state".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;
  boot.initrd = {
    systemd = {
      enable = true;
      services.rollback = {
        description = "Rollback root filesystem to a pristine state on boot";
        wantedBy = [ "initrd.target" ];
        after = [ "zfs-import-zroot.service" ];
        before = [ "sysroot.mount" ];
        path = with pkgs-stable; [ zfs ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          zfs rollback -r zroot/local/root@blank && echo "  >> >> ROLLBACK COMPLETE << <<"
        '';
      };
    };
  };

  # persistence
  environment.persistence."/nix/state" = {
    # https://github.com/nix-community/impermanence?tab=readme-ov-file#module-usage
    enable = true;
    hideMounts = true;
    directories = [
      "/etc/nixos"
      "/var/log"
      "/var/lib/systemd/timers" # for systemd persistant timers during off time
      "/var/lib/nixos" # to stop complaiing about uid and guid on reboot
      "/var/lib/tailscale" # node identity/state; authKeyFile is single-use
      "/var/lib/health-alerts" # alert dedup stamps
      "/var/lib/docker" # container images/layers, avoids re-pulling minecraft/factorio images every boot
      # no zrepl entry: its cursors, holds and bookmarks live in ZFS
      "/var/lib/restic-backups-backblazeWeekly" # last-success marker for staleness alerting
      "/var/lib/restore-drill" # restore-drill success marker, same staleness pattern
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };
}

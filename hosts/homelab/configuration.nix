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

    ../../profiles/default.nix
    ../../profiles/server.nix

    ../../modules/nixos/auto-update.nix
    ../../modules/nixos/health-alerts.nix
    ../../modules/nixos/push-deploy.nix

    ../../services/jellyfin.nix
    ../../services/minecraft.nix
    ../../services/factorio.nix
    ../../services/octodns.nix
    ../../services/nfs.nix
  ];

  # System installed pkgs
  environment.systemPackages = with pkgs-stable; [
    sanoid # also installs syncoid and findoid
    zfs
    restic
    backblaze-b2
    btop
    tmux
    zellij
  ];

  # disable staggered hdd spin up
  boot.extraModprobeConfig = ''
    options libahci ignore_sss=1
  '';

  # tailscale UDP GRO forwarding tweak — enp3s0 is this host's real NIC,
  # not applicable to any other host in this repo.
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
  virtualisation.docker.daemon.settings = {
    userland-proxy = false;
  };

  # oci containers
  virtualisation.oci-containers.backend = "docker";

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

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
  systemd.tmpfiles.rules = [
    "d /srv 0770 - root root -"
    "A /storage - - - - group:multimedia:rwx"
    "A /storage-bulk - - - - group:multimedia:rwx"
  ];

  sops.secrets = {
    # the whole rclone ini stanza ([backblazeDaily]/type/account/key) as one
    # multiline secret, so it can be handed to rcloneConfigFile directly —
    # no prefetcher service needed to assemble it from separate fields.
    homelab_backblaze_rclone_config = { };
    homelab_backblaze_restic_password = { };
    homelab_discord_webhook = {
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
      # "backblazeDaily" here is the rclone remote name (the [stanza] header
      # inside the homelab_backblaze_rclone_config secret), not this
      # backup's name — it's a leftover from before the backblazeWeekly
      # rename and must stay in sync with the secret unless that's also
      # updated (sops secrets aren't edited directly; see repo docs).
      repository = "rclone:backblazeDaily:restic21029709384"; # using rclone because the normal restic s3 b2 integration did not work with both the service and the wrapper
      rcloneOptions = {
        transfers = "32";
        b2-hard-delete = "false";
      };
      rcloneConfigFile = config.sops.secrets.homelab_backblaze_rclone_config.path;
      #       mount all the most recent backups in a temp folder for restic to trawl
      backupPrepareCommand = ''
        datasets="zroot/local/state zdata/storage/storage zdata/storage/storage-bulk"

        for dataset in $datasets; do
          snapshot=$(zfs list -H  -t snapshot -o name -s name -r $dataset | tail -n 1)
          if [[ -n "$snapshot" ]]; then
            mkdir -p /tmp/restic/$snapshot
            mount -t zfs $snapshot /tmp/restic/$snapshot
          fi
        done
        echo "### Mounted Snapshots ###"
      '';
      backupCleanupCommand = ''
        zfs list  -t snapshot -H -o name | xargs -I {} umount -t zfs {} 2> /dev/null
        echo "### Unmounted Snapshots ###"
          rm -rf /tmp/restic
      '';
      user = "root";
      paths = [ "/tmp/restic" ];
      timerConfig = {
        OnCalendar = "Fri 03:00:00";
        Persistent = true;
      };
      pruneOpts = [
        "--retry-lock 15m"
        "--keep-daily 30"
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
      # backup is always lowest priority to not effect running processes
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      # this service mounts/unmounts ZFS snapshots into a shared /tmp
      # (that's why PrivateTmp is already forced off below) and needs
      # real mount(8) access — ProtectSystem/namespace restrictions
      # would conflict with that, so only the always-safe flag applies.
      NoNewPrivileges = true;
      PrivateTmp = lib.mkForce false;
      # a Backblaze auth failure can make restic/rclone retry its lock
      # operations forever instead of erroring out — this once left the
      # unit "running" (and thus blocking every future weekly trigger) for
      # 7+ weeks with no successful backup. Force a hard failure instead,
      # so the timer can retry and the failed-units health check fires.
      # (RuntimeMaxSec has no effect on Type=oneshot — there's no separate
      # "running" phase to bound, the ExecStart sequence *is* the start
      # phase — so TimeoutStartSec is the one that actually applies here.)
      # 6h was too short for the actual backlog (~2.9TiB): every weekly run
      # got killed mid-upload before committing a snapshot, so no progress
      # ever landed and it kept restarting from scratch (last successful
      # snapshot was 2026-06-23). Bumped to 1w — still bounded by the
      # weekly timer, but long enough for a run to actually finish.
      TimeoutStartSec = "1w";
      StateDirectory = "restic-backups-backblazeWeekly";
      # only reached on success (ExecStartPost doesn't run after a failed
      # ExecStart), so its mtime is proof a backup actually completed.
      ExecStartPost = "${pkgs-stable.coreutils}/bin/touch /var/lib/restic-backups-backblazeWeekly/last-success";
    };
  };

  # zfs snapshots
  services.sanoid = {
    enable = true;
    extraArgs = [ "--verbose" ];
    interval = "minutely";
    settings = {
      "zroot/local/state".use_template = "working";
      "zdata/storage/storage".use_template = "working";
      "zdata/storage/storage-bulk".use_template = "working";
      template_working = {
        frequent_period = 1;
        frequently = 59;
        # hourly/daily give syncoid ~2 weeks of slack to recover a stuck
        # target before its resume base gets pruned out from under it
        # (see localTargetAllow's "destroy" comment below for context) —
        # zdata has 8TB+ free and current snapshot overhead is negligible,
        # so this is cheap.
        hourly = 168;
        daily = 14;
        weekly = 0;
        monthly = 0;
        yearly = 0;
        autosnap = "yes";
        autoprune = "yes";
      };
      "zbackup" = {
        use_template = "backup";
        recursive = "yes";
      };
      template_backup = {
        frequently = 0;
        hourly = 168;
        daily = 366;
        weekly = 0;
        monthly = 0;
        yearly = 0;
        autosnap = "no";
        autoprune = "yes";
      };
    };
  };
  systemd.services.sanoid.serviceConfig = {
    User = lib.mkForce "root";
  };
  services.syncoid = {
    enable = true;
    interval = "hourly";
    commonArgs = [ "--no-sync-snap" ]; # "--create-bookmark" for mobile machines
    # Module default omits "destroy": without it, syncoid can't run "zfs
    # receive -A" to abort a partial receive whose source snapshot has since
    # been pruned, so it fails every run forever instead of self-healing.
    # Scoped to target datasets only (the ones syncoid already fully owns
    # via delegation) — source datasets don't get this permission.
    localTargetAllow = [
      "change-key"
      "compression"
      "create"
      "mount"
      "mountpoint"
      "receive"
      "rollback"
      "destroy"
    ];
    commands = {
      "zdata/storage/storage" = {
        source = "zdata/storage/storage";
        target = "zbackup/backup/homelab/storage";
        extraArgs = [ "--identifier=zdata_storage_storage" ];
      };
      "zdata/storage/storage-bulk" = {
        source = "zdata/storage/storage-bulk";
        target = "zbackup/backup-bulk/homelab/storage-bulk";
        extraArgs = [ "--identifier=zdata_storage_storage-bulk" ];
      };
      "zroot/local/state" = {
        source = "zroot/local/state";
        target = "zbackup/backup/homelab/state";
        extraArgs = [ "--identifier=zroot_local_state" ];
      };
    };
  };

  # receive side for torrent's + thinkpad's syncoid push backups (see
  # TODO.md "syncoid push backups" and modules/nixos/backup-push.nix).
  # Dedicated non-root user per feedback_dedicated_service_users; scoped
  # via `zfs allow` to only the two subtrees it needs, not the whole
  # zbackup pool, so a compromised source host key can't touch anything
  # else on this pool.
  users.users.backup-recv = {
    isSystemUser = true;
    group = "backup-recv";
    shell = pkgs-stable.bash; # needed for syncoid's remote zfs commands over ssh
    openssh.authorizedKeys.keys = [
      # "restrict" disables port/agent/X11 forwarding and pty allocation —
      # this key should only ever run zfs-receive-adjacent commands, same
      # least-privilege spirit as vps-deploy's forced-command key
      # (hosts/vps/configuration.nix). No forced `command=` here since
      # syncoid needs to run different zfs commands with dynamic args, so
      # `zfs allow`'s scoping (below) is the real boundary, not this.
      # TODO: paste torrent_backup_push_key's *public* key here, prefixed with "restrict "
      # TODO: paste thinkpad_backup_push_key's *public* key here, prefixed with "restrict "
    ];
  };
  users.groups.backup-recv = { };

  systemd.services.backup-recv-zfs-allow = {
    description = "Delegate zfs receive permissions on backup/{torrent,thinkpad} to backup-recv";
    after = [ "zfs-import-zbackup.service" ];
    wantedBy = [ "multi-user.target" ];
    # not gated in front of sshd: if this ever fails (e.g. zbackup import
    # trouble), ssh access to homelab should still come up — a syncoid
    # push just fails and gets caught by backupStaleness instead.
    path = [ pkgs-stable.zfs ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    # zfs allow is idempotent — safe to re-run every activation/boot.
    script = ''
      zfs allow backup-recv create,mount,mountpoint,receive,rollback,destroy zbackup/backup/torrent
      zfs allow backup-recv create,mount,mountpoint,receive,rollback,destroy zbackup/backup/thinkpad
    '';
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

  # automated flake.lock updates: bump inputs on a branch, build-test, merge
  # to master only if it builds, then switch (rebooting only if the kernel
  # actually changed)
  myAutoUpdate = {
    enable = true;
    hostAttr = "homelab";
    updateDates = "Wed 03:00";
    switchDates = "Thu 03:00";
  };

  # vps builds nothing itself anymore (myPullDeploy removed there — a
  # from-scratch local build peaked at ~1.7GB RAM + 424MB swap out of
  # its ~2GB total, measured live 2026-08-18, too tight to keep
  # building on-box). homelab builds vps's config here instead and
  # pushes+activates the finished closure over SSH, as the unprivileged
  # vps-deploy user (see hosts/vps/configuration.nix — real activation
  # happens via nixos-rebuild's polkit-based run0 elevator, not root
  # login, not sudo).
  sops.secrets.homelab_vps_deploy_key = { };
  myPushDeploy = {
    enable = true;
    flakeDir = "/etc/nixos";
    hostAttr = "vps";
    targetHost = "vps-deploy@vps";
    identityFile = config.sops.secrets.homelab_vps_deploy_key.path;
    # dates left at its default (Thu 03:15) as a periodic fallback —
    # the onSuccess wiring below is the primary trigger, right after
    # homelab's own myAutoUpdate switch, so this reuses the same
    # already-vetted master checkout instead of racing/duplicating it.
  };
  systemd.services.nixos-upgrade.onSuccess = [ "push-deploy-vps.service" ];

  # email alerts for ZFS/SMART/failed-unit/stuck-switch issues
  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.homelab_discord_webhook.path;
    interval = "*:0/15";
    # syncoid runs hourly; alert if a target hasn't advanced in 2x that plus
    # slack, so a stuck target is caught long before the source's ~24h
    # snapshot retention prunes the base it needs to resume from.
    backupStaleness = {
      "zbackup/backup/homelab/storage" = 6;
      "zbackup/backup-bulk/homelab/storage-bulk" = 6;
      "zbackup/backup/homelab/state" = 6;
      # torrent is a desktop, not a server — usually up, but can go dark
      # for a while too (e.g. powered off during vacation). Same
      # reasoning as thinkpad below: bookmarks make this a non-issue for
      # resync, so the threshold only exists to catch a genuinely broken
      # key/config, not normal off time. 336h = 2 weeks.
      "zbackup/backup/torrent/home" = 336;
      "zbackup/backup/torrent/root" = 336;
      # thinkpad is a laptop that legitimately goes offline for long
      # stretches (asleep/traveling) — syncoid's --create-bookmark means
      # that's not a resync risk, so this threshold is only meant to catch
      # a genuinely broken key/config, not normal laptop-off time. 336h =
      # 2 weeks.
      "zbackup/backup/thinkpad/home" = 336;
      "zbackup/backup/thinkpad/root" = 336;
    };
    # offsite restic backup runs weekly (Fri 03:00) and can now take up to
    # TimeoutStartSec=1w to finish a single run, so 192h (8 days) would give
    # zero slack; 336h = 14 days gives a full week of slack past a
    # worst-case 1-week run before alerting on a missed/stuck run.
    staleMarkerFiles = {
      "/var/lib/restic-backups-backblazeWeekly/last-success" = 336;
    };
  };

  # ssh server
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    enable = true;
    allowSFTP = true;
    settings.KbdInteractiveAuthentication = false;
    # PasswordAuthentication must be set as a structured option, not via
    # extraConfig — NixOS's openssh module renders its own default
    # (PasswordAuthentication yes) *before* extraConfig, and sshd_config
    # uses first-directive-wins, so "passwordAuthentication = no" here
    # was silently overridden and password auth was actually enabled
    # this whole time (confirmed live on vps, which had the identical
    # pattern; fixed there too — see hosts/vps/configuration.nix).
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

  # zfs support
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "e0019fd8";

  # tailscale: advertise the LAN subnet and act as an exit node
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
  services.tailscale.extraUpFlags = lib.mkAfter [
    "--advertise-routes=192.168.1.0/24"
    "--advertise-exit-node"
  ];

  # wireguard: dial out to the vps (hosts/vps) so it can act as a public
  # tunnel endpoint for us despite being behind CGNAT — homelab always
  # initiates, nothing needs to be reachable inbound at home.
  sops.secrets.homelab_wireguard_private_key = { };
  # same PSK file content as vps's wireguard_vps_homelab_psk — see
  # hosts/vps/configuration.nix's peer entry.
  sops.secrets.wireguard_vps_homelab_psk = { };
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.2/24" ];
    privateKeyFile = config.sops.secrets.homelab_wireguard_private_key.path;
    peers = [
      {
        # vps
        publicKey = "DIYtQyvp/KWNg1rVMjMM8FxfkvMRp5iNEt8iYOonKmA=";
        presharedKeyFile = config.sops.secrets.wireguard_vps_homelab_psk.path;
        endpoint = "[2604:a880:4:1d0:0:3:5045:8000]:51820";
        allowedIPs = [ "10.100.0.1/32" ];
        # CGNAT mappings expire without periodic traffic; keep the
        # tunnel (and the vps's route back to us) alive.
        persistentKeepalive = 25;
      }
    ];
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
      "/var/lib/tailscale" # node identity/state; without this, a non-reusable authKeyFile
      # is consumed on first boot then fails every boot after since the state gets wiped
      "/var/lib/health-alerts" # alert dedup stamps
      "/var/lib/docker" # container images/layers, avoids re-pulling minecraft/factorio images every boot
      "/var/lib/sanoid" # snapshot state cache
      "/var/lib/restic-backups-backblazeWeekly" # last-success marker for staleness alerting
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };
}

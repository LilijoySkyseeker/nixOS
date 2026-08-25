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

  # disable staggered hdd spin up
  boot.extraModprobeConfig = ''
    options libahci ignore_sss=1
  '';

  # tailscale UDP GRO forwarding compatibility, enp3s0 is this host's real NIC,
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
    package = config.boot.kernelPackages.nvidiaPackages.stable;
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
  systemd.tmpfiles.rules = [
    "d /srv 0770 - root root -"
    "A /storage - - - - group:multimedia:rwx"
    "A /storage-bulk - - - - group:multimedia:rwx"
  ];

  # sops
  sops.secrets = {
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
      # using rclone because the normal restic s3 b2 integration did not work with both the service and the wrapper, "Daily" name is legacy
      repository = "rclone:backblazeDaily:restic21029709384";
      rcloneOptions = {
        transfers = "32";
        b2-hard-delete = "false";
      };
      rcloneConfigFile = config.sops.secrets.homelab_backblaze_rclone_config.path;
      # mount all the most recent backups in a temp folder for restic to trawl
      backupPrepareCommand = ''
        datasets="zroot/local/state zdata/storage/storage"

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
      # daily means keep n runs, so actully 2 snapshots, 1 per week
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
      # backblaze bucket config
      ExecStartPre = "${pkgs-stable.rclone}/bin/rclone backend lifecycle backblazeDaily:restic21029709384 --config ${config.sops.secrets.homelab_backblaze_rclone_config.path} -o daysFromHidingToDeleting=1";
      # time since last success timer for alerting
      ExecStartPost = "${pkgs-stable.coreutils}/bin/touch /var/lib/restic-backups-backblazeWeekly/last-success";
    };
  };

  # Import zbackup at boot.
  #
  # nixpkgs only generates a zfs-import-<pool>.service for pools something
  # actually references -- a `fileSystems` entry, or this option. zdata gets
  # one implicitly because /storage and /storage-bulk are mountpoints on it.
  # Every zbackup dataset is `mountpoint = "none"` (see disko.nix) precisely
  # because nothing should mount from the backup pool, so nothing referenced
  # it and nothing imported it: after the 2026-08-23 reboot zbackup simply
  # stayed exported and every replication job failed for ~23h with
  # "dataset does not exist". disko does not help here -- it only creates
  # pools at format time and emits no import units at all.
  boot.zfs.extraPools = [ "zbackup" ];

  # zfs snapshots + replication (zrepl; replaced sanoid+syncoid)
  #
  # homelab is the active side of every replication relationship here. It
  # pulls from torrent and thinkpad rather than having them push, so a
  # compromised source host has no RPC handle on this machine at all --
  # zrepl's receiving endpoint exposes DestroySnapshots to whoever is
  # authenticated, which under push would let a compromised source delete
  # its own backup history. Pulling keeps retention authority here.
  #
  # It also replicates its own datasets into zbackup over zrepl's local
  # transport, replacing the three hourly syncoid jobs that used to do it.
  #
  # Snapshotting itself belongs to the module's snap job (on by default,
  # covering every dataset named below), not to any replication job, so it
  # keeps running regardless of what any peer is doing. Local replication
  # therefore runs on its own interval rather than firing every time a
  # snapshot is taken -- which matters here because zbackup sits behind a
  # USB link (USB 2.0 and heavily contended until the 2026-08-23 cable
  # change moved it to USB 3.0; see hosts/homelab/README.md).
  sops.secrets.homelab_zrepl_key = { };

  # zrepl's ssh+stdinserver client (go-netssh, shelling out to system ssh)
  # has no interactive TTY to prompt on an unrecognized host key, so the
  # very first connection to a freshly-deployed source host fails outright
  # with "Host key verification failed" rather than TOFU-prompting -- hit
  # this deploying torrent (2026-08-24), the pull job's first real attempt
  # after its sshd came up. Pinning the host key declaratively (rather
  # than `StrictHostKeyChecking=accept-new`, or `ssh-keyscan`ing by hand)
  # keeps this reproducible from source and doesn't weaken the actual
  # protection host-key checking provides -- these are public keys, not
  # secrets. thinkpad will need the same entry once it's deployed and its
  # host key is known.
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
      # Received filesystems land at <rootFs>/<full source dataset path>,
      # e.g. zbackup/backup/torrent/zroot/local/home -- zrepl extends
      # root_fs with the whole source path rather than a chosen leaf name,
      # so this tree is deeper than the syncoid layout it replaces.
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
      ];
      rootFs = "zbackup/backup";
      clientIdentity = "homelab";
    };

    # homelab's own zrepl history is proven (local replication completed
    # and verified 2026-08-24) -- the sanoid-era autosnap_ snapshots are
    # no longer needed as a safety net and were destroyed by hand once
    # this landed.
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
    # Paths carry the full source dataset path because zrepl extends
    # root_fs with it (see myZrepl above) — these are NOT the old syncoid
    # target names.
    #
    # zrepl replicates every 15m; alert if a target hasn't advanced in
    # well over that, so a stuck target is caught early. It is no longer a
    # race against the source pruning its incremental base: zrepl's
    # replication cursor holds that base regardless of how long a target
    # lags, which is the failure that stranded the old syncoid push.
    backupStaleness = {
      "zbackup/backup/homelab/zdata/storage/storage" = 6;
      "zbackup/backup/homelab/zdata/storage/storage-bulk" = 6;
      "zbackup/backup/homelab/zroot/local/state" = 6;
      # torrent is a desktop, not a server — usually up, but can go dark
      # for a while (e.g. powered off during vacation). The threshold only
      # exists to catch a genuinely broken key/config, not normal off
      # time. 336h = 2 weeks.
      "zbackup/backup/torrent/zroot/local/home" = 336;
      "zbackup/backup/torrent/zroot/local/root" = 336;
      # thinkpad is a laptop that legitimately goes offline for long
      # stretches (asleep/traveling), same reasoning as torrent above.
      "zbackup/backup/thinkpad/zroot/local/home" = 336;
      "zbackup/backup/thinkpad/zroot/local/root" = 336;
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
        # IPv4 literal, not vps's IPv6 address — confirmed live this
        # tunnel silently died for hours despite persistentKeepalive:
        # homelab's own outbound IPv6 addresses are RFC4941 "temporary
        # dynamic" privacy addresses that rotate periodically, and once
        # one rotated, the vps side's auto-learned endpoint for this
        # peer went stale (source-address roaming only relearns from a
        # freshly-arriving packet, and nothing forced one). vps's IPv4
        # (137.184.45.18, ens3 — see hosts/vps/configuration.nix) is
        # static and is what every other IPv4-only piece of this path
        # (game-port DNAT/SNAT/rate-limits) already keys off of.
        endpoint = "137.184.45.18:51820";
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
      # zrepl needs no persisted state directory: its replication cursors,
      # holds and bookmarks all live in ZFS itself, so there is no
      # equivalent of sanoid's /var/lib/sanoid cache to keep here.
      "/var/lib/restic-backups-backblazeWeekly" # last-success marker for staleness alerting
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };
}

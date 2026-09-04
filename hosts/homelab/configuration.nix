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

    # The 4 zdata/zbackup HDDs sit in a TerraMaster USB enclosure (ASMedia
    # bridge, USB id 174c:55aa) bound to the kernel's uas driver. That bridge
    # chip has a well-documented history (see TerraMaster/kernel bug threads)
    # of silently corrupting in-flight data under I/O load -- the bridge is
    # powered off the USB port while only the drives get power from the
    # enclosure's own supply, so bus-side power sag glitches transfers without
    # ever dropping the link. Ref: 2026-08-28-homelab-zdata-pool-usb-uas-checksum-errors.md
    # Force plain USB Mass Storage (BOT) instead of UAS to avoid this.
    kernelParams = [ "usb-storage.quirks=174c:55aa:u" ];
  };

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
  #
  # SECURITY-LOAD-BEARING, which it does not look like.
  #
  # A docker-published port bypasses the NixOS firewall entirely: a bare
  # `-p` binds 0.0.0.0 and makes docker DNAT in nat/PREROUTING before the
  # routing decision, so the packet is forwarded and never traverses
  # nixos-fw in INPUT. The pinned oci-containers module says so in its
  # own option docs ("Publishing a port bypasses the NixOS firewall"),
  # and networking.firewall.filterForward = false means NixOS does not
  # manage FORWARD either. So the interface-scoped tailscale0/wg0 rules
  # in modules/services/{minecraft,factorio}.nix cannot constrain the
  # published game ports -- they render, and they do nothing (F-P4-02).
  # That left those ports reachable from anything on 192.168.1.0/24.
  #
  # RESOLVED 2026-08-27 by myDockerPublishGuard below, which adds the
  # DOCKER-USER allowlist. The published ports are now filtered in
  # FORWARD, where DNAT'd traffic actually goes, rather than in INPUT,
  # where it never arrives. The LAN path is closed; the wg0 and
  # tailscale0 paths are unchanged.
  #
  # The IPv6 half is the part still live, and it is why this comment
  # stays. What keeps these ports off the *internet* is narrower than it
  # looks: this host's LAN NIC carries a real globally-routable
  # ISP-delegated IPv6 address, and the only thing stopping the game
  # servers being directly internet-reachable on it is docker's default
  # of not enabling IPv6 for containers -- `ipv6` is unset in these
  # settings, and userland-proxy = false (below, added as a performance
  # tweak) removes the userland proxy whose dual-stack listener
  # historically caused exactly this. Verified live 2026-08-26:
  # `ip6tables -t nat -S` matched nothing for any published port, and
  # every listener was bound by dockerd on 0.0.0.0 with none on ::.
  #
  # The guard is IPv4-only for the same reason -- docker's ip6tables
  # chains do not exist while container IPv6 is off, so an ip6tables rule
  # would have nothing to attach to. Do not set `ipv6 = true` here, and
  # do not restore userland-proxy, without extending the guard to
  # ip6tables first. Either change silently converts a LAN exposure into
  # an internet one.
  virtualisation.docker.daemon.settings = {
    userland-proxy = false;
  };

  # Make the intent that modules/services/{minecraft,factorio}.nix
  # already declare actually true. Those files scope the game ports to
  # tailscale0 and wg0 via networking.firewall.interfaces, which reads
  # correctly and constrains nothing for a published port (F-P4-02);
  # this is the same policy expressed where it can take effect.
  #
  # D13, answered 2026-08-27: the user never reaches these servers from a
  # LAN machine — only over the tailnet, or over the public address,
  # which arrives here as wg0 traffic DNAT'd by vps. So there is no LAN
  # exception to carve out, and anything on 192.168.1.0/24 should go from
  # working to refused.
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
    # nvidiaPackages.stable (production) dropped Pascal support upstream --
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
  #
  # /srv is deliberately NOT managed here any more. It used to carry
  # `d /srv 0770 root root -`, added to close a real finding: factorio's
  # token/password and jellyfin's config sit under /srv and were
  # world-readable. That rule broke jellyfin on 2026-08-28. /srv is a
  # shared parent for three services running as three different non-root
  # users, and 0770 root:root denies every one of them the `x` bit they
  # need to traverse into their own data -- it is not a stricter version of
  # correct, it is non-functional. It also fought two other systems that
  # both assert 0755 (systemd's own home.conf, and impermanence's
  # create-directories) and won only by sorting first, so whether it
  # applied at all depended on boot vs switch.
  #
  # The exposure it was reaching for is real, but it lives one level down
  # and is fixed there instead -- see the leaf modes below. /srv itself is
  # a namespace, not a secret. See
  # 2026-08-28-fix-srv-permissions-stop-three-systems-fighting-ov.md.
  systemd.tmpfiles.rules = [
    "A /storage - - - - group:multimedia:rwx"
    "A /storage-bulk - - - - group:multimedia:rwx"
  ];

  # The confidentiality rules for the game-server state directories are
  # NOT here. They live in modules/services/{factorio,minecraft}.nix, next
  # to the paths they protect -- a `z` rule silently becomes a no-op if its
  # path is renamed, so keeping mode and path apart reintroduces exactly
  # the silent-failure shape this whole change exists to remove.

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
      # Mount the most recent snapshot of each dataset under $RUNTIME_DIRECTORY
      # (systemd-managed, 0700, created fresh by this unit) rather than a
      # hand-rolled /tmp/restic: /tmp is world-traversable for the run's
      # whole multi-day duration, and mkdir -p on a path an unprivileged
      # process pre-planted as a symlink would follow it — systemd's
      # RuntimeDirectory creation refuses that (docs/audits/2026-08-26/findings-tail.md L-02).
      backupPrepareCommand = ''
        datasets="zroot/local/state zdata/storage/storage"

        for dataset in $datasets; do
          snapshot=$(zfs list -H -t snapshot -o name -s creation -r $dataset | tail -n 1)
          if [[ -n "$snapshot" ]]; then
            mkdir -p "$RUNTIME_DIRECTORY/$snapshot"
            mount -t zfs "$snapshot" "$RUNTIME_DIRECTORY/$snapshot"
          fi
        done
        echo "### Mounted Snapshots ###"
      '';
      backupCleanupCommand = ''
        # Unmount only what this run mounted under $RUNTIME_DIRECTORY, not
        # every snapshot on the system (the previous version piped every
        # zfs snapshot name — including zbackup's replicated ones — into
        # umount). cut, not awk: this unit's `path` carries no gawk.
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
        # Persistent=false (default) is deliberate: after a long outage this
        # would otherwise fire its missed run immediately at boot, piling
        # ~2.9TiB of I/O on top of zrepl's own post-boot catch-up
        # replication (see 2026-08-18-homelab-backup-replication-stack-has-several-compo.md).
        # Skipping straight to next Friday
        # instead isn't silent — myHealthAlerts pages if
        # last-success goes over 336h/14 days stale (see below).
        Persistent = false;
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
      # 0700: the mounted snapshots hold the whole persisted-state and
      # media trees for up to a week; nothing but root should be able to
      # traverse into them (findings-tail.md L-02).
      RuntimeDirectory = "restic-backups-backblazeWeekly";
      RuntimeDirectoryMode = "0700";
      # backblaze bucket config
      ExecStartPre = "${pkgs-stable.rclone}/bin/rclone backend lifecycle backblazeDaily:restic21029709384 --config ${config.sops.secrets.homelab_backblaze_rclone_config.path} -o daysFromHidingToDeleting=1";
      # time since last success timer for alerting
      ExecStartPost = "${pkgs-stable.coreutils}/bin/touch /var/lib/restic-backups-backblazeWeekly/last-success";
    };
  };

  # Backup restore-and-verify (Tier 1) -- see
  # 2026-09-04-automated-canary-based-backup-restore-and-verify-tier-1.md.
  # Canary content strings must match, byte for byte, what each source
  # host's own myBackupCanary.paths declares.
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
      # Must match backupPrepareCommand's RuntimeDirectory above.
      mountPrefix = "/run/restic-backups-backblazeWeekly";
      triggerUnit = "restic-backups-backblazeWeekly.service";
      # Only the two datasets restic actually backs up (see backupPrepareCommand above) -- not storage-bulk, torrent, or thinkpad.
      targets = {
        "zroot/local/state".expectedContent = "backup-canary homelab zroot/local/state v1";
        "zdata/storage/storage".expectedContent = "backup-canary homelab zdata/storage/storage v1";
      };
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
  # go-netssh shells out to the system ssh binary per connection attempt,
  # which reads -i's target fresh each time -- unlike wireguard's
  # RemainAfterExit oneshot, this is plausibly a per-invocation reader
  # already. Not verified either way (SYS-11's rule: check which kind you
  # have, don't assume), and restartUnits costs nothing here -- a zrepl
  # pull that gets killed mid-run simply retries on the next interval, per
  # rotation-runbook.md item 9 -- so set it rather than rely on the
  # per-invocation read actually being true.
  sops.secrets.homelab_zrepl_key.restartUnits = [ "zrepl.service" ];

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
    # the weekly restic->Backblaze run can take multiple days (~2.9TiB) —
    # switch-to-configuration restarts any unit whose definition changed, so
    # a same-cycle switch would kill it mid-run. Defer instead (see
    # 2026-08-18-homelab-s-weekly-restic-to-backblaze-backup-has-no.md).
    protectedUnits = [ "restic-backups-backblazeWeekly.service" ];
    # DISABLED 2026-08-27, deliberately and temporarily. Removes both the
    # flake-update-test and auto-switch timers; the services stay, so
    # `systemctl start auto-switch-now` is still the manual deploy path.
    #
    # Two reasons. There is active development, so these hosts are being
    # deployed by hand anyway — the scheduled path buys nothing right now
    # while carrying every risk in the D11 analysis. And the pipeline is
    # being rebuilt rather than patched (see
    # 2026-08-27-rebuild-the-update-build-deploy-pipeline-properly.md),
    # so leaving the old shape
    # armed would mean maintaining something already known to be wrong.
    #
    # This also stops D11 firing on its own: flake-update-test can no
    # longer auto-merge to master unattended. It does NOT answer D11 —
    # the decision is deferred into the project, not made.
    #
    # RE-ENABLE with the new pipeline, not before. The safety net for
    # being disabled is myHealthAlerts' staleness check on
    # /nix/var/nix/profiles/system: if the fleet stops being deployed,
    # it says so within three weeks rather than never.
    scheduleEnable = false;
    # Replaces `systemd.services.auto-switch.onSuccess`, which fired this
    # on a *skipped* switch too — observed live 2026-08-25T13:18:15, where
    # the min-interval guard deferred the switch and systemd started the
    # vps closure build 0 seconds later anyway. This only fires after a
    # real activation (F-P7-09).
    onDeployUnits = [ "push-deploy-vps.service" ];
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
    # Disabled with the rest of the fleet's schedules, 2026-08-27 — see
    # myAutoUpdate above. The unit remains, so `systemctl start
    # push-deploy-vps` is still how vps gets deployed by hand.
    #
    # Belt and braces: onDeployUnits below would only fire this after a
    # real auto-switch activation, and auto-switch no longer has a timer,
    # so the chain is already dead. Disabling the periodic fallback too
    # means there is exactly one way vps gets deployed right now, and it
    # is a human.
    scheduleEnable = false;
    # dates left at its default (Thu 03:15) as a periodic fallback —
    # the onSuccess wiring below is the primary trigger, right after
    # homelab's own myAutoUpdate switch, so this reuses the same
    # already-vetted master checkout instead of racing/duplicating it.
  };
  # email alerts for ZFS/SMART/failed-unit/stuck-switch issues
  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.discord_webhook.path;
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
    # Offsite restic backup runs weekly (Fri 03:00).
    #
    # 312h = 13 days, lowered from 336h on 2026-08-28. 336h was sized
    # against TimeoutStartSec=1w, reasoning that a worst-case 1-week run
    # needed a full week of slack on top of the 1-week schedule. That is
    # exactly the problem: 168h schedule + 168h worst-case run = 336h, so
    # the threshold landed on the same instant as the next scheduled run.
    # A run that succeeded then refreshed this marker at almost precisely
    # the moment the alarm came due, and a fortnight with no offsite
    # backup could pass without ever paging. Nearly happened for real --
    # the 2026-08-21 run was the last success, the 2026-08-28 run was
    # killed mid-flight, and the alarm was due 2026-09-04, the same day as
    # the next attempt.
    #
    # Dropping a single day breaks that coincidence: the alarm now fires
    # 24h *before* the run that would otherwise mask it, so a missed run
    # is reported rather than papered over.
    #
    # The 1-week worst case it was protecting against is theoretical --
    # it comes from the timeout, not from behaviour. Measured runs:
    # 2d16h for the initial 522.8 GB full upload (2026-08-18 -> 08-21),
    # and 8h28m for an incremental before a deploy killed it. At 312h a
    # run may take 144h (6 days) before false-alarming, still more than
    # double the longest real run.
    #
    # If a run ever legitimately approaches a week, raise this again --
    # but raise the *schedule* too, or the coincidence comes back.
    staleMarkerFiles = {
      "/var/lib/restic-backups-backblazeWeekly/last-success" = 312;
      # F-P7-09's skipped-deploy half. A *failed* auto-switch already pages
      # via the failed-units check (confirmed working: the 2026-08-27 03:00
      # read-only-git-config failure did enter systemctl --failed). A
      # *skipped* one does not — the guards exit 0 — so a host that defers
      # every week, or whose timer stops firing, drifts silently forever.
      # This watches the outcome instead: the profile symlink's mtime is the
      # last real activation by any route, scheduled or manual.
      #
      # 504h = 21 days. The normal ceiling is 14: switchDates is weekly and
      # minSwitchInterval is 7 days, so a deploy on day 0 defers the day-7
      # run and lands on day 14. 21 allows one further deferral for the
      # protectedUnits restic run (weekly, and able to run for days), which
      # is the realistic third week. Tighten once there is real cadence data
      # — a threshold this loose still turns "silently stopped deploying"
      # from never-detected into detected-within-three-weeks.
      "/nix/var/nix/profiles/system" = 504;
      # myBackupRestoreTest's canary restore-and-verify. These prove the
      # backup is actually restorable, not just advancing (backupStaleness
      # above only checks the latter) -- a broken run also trips
      # failed-units, this catches one that stops running entirely.
      "/var/lib/backup-restore-test/zbackup-last-success" = 30; # daily check
      "/var/lib/backup-restore-test/restic-last-success" = 312; # matches restic's own staleness threshold above
    };
  };

  # ssh server
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    enable = true;
    allowSFTP = true;
    # unlike vps, this was never set here — left port 22 open on every
    # interface via NixOS's own openssh module default, including the LAN
    # NIC, which (confirmed 2026-08-26) carries a real ISP-delegated public
    # IPv6 address alongside its private IPv4 one. Access to this host is
    # tailscale-only in practice anyway (getent hosts homelab resolves to
    # its tailscale IP, not the LAN IP) — close the blanket allow and
    # re-open explicitly on tailscale0 below, matching vps's own
    # "force port 22 closed" precedent and the tailscale0-only scoping
    # already used by nfs.nix/samba.nix.
    openFirewall = false;
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
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # zfs support
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "e0019fd8";

  # tailscale: advertise the LAN subnet and act as an exit node.
  #
  # This is the one host in the fleet that genuinely routes, so it opts back
  # in to the forwarding features that modules/profiles/default.nix now
  # withholds by default. Keep this and the profile default in sync: if this
  # mkForce is ever dropped while the advertise flags below stay, the exit
  # node and the 192.168.1.0/24 subnet route silently stop working -- that
  # failure is visible in `tailscale status`, not in a build.
  services.tailscale.useRoutingFeatures = lib.mkForce "both";
  # The explicit net.ipv4.ip_forward / net.ipv6.conf.all.forwarding sysctls
  # that used to sit here are gone: the tailscale module already sets both
  # (at mkOverride 97) whenever useRoutingFeatures is "both", so they were
  # redundant restatements of something the option above controls. They are
  # removed in the same commit as the profile-default inversion deliberately
  # -- removing them first, while the default was still "both", would have
  # been a no-op that quietly became load-bearing later.
  services.tailscale.extraUpFlags = lib.mkAfter [
    "--advertise-routes=192.168.1.0/24"
    "--advertise-exit-node"
  ];

  # wireguard: dial out to the vps (hosts/vps) so it can act as a public
  # tunnel endpoint for us despite being behind CGNAT — homelab always
  # initiates, nothing needs to be reachable inbound at home.
  # restartUnits is load-bearing, not tidiness. wireguard-wg0.service is
  # Type=oneshot + RemainAfterExit=true: it reads privateKeyFile once when
  # the link is created and never re-runs, so rotating the key in sops
  # leaves the interface running the OLD key indefinitely. Hit for real
  # during the 2026-08-27 rotation (items 5-7): activation logged
  # "modifying secrets: homelab_wireguard_private_key", the peer unit
  # restarted because its name is derived from the peer's public key, and
  # `wg show` still reported the previous interface key — the interface
  # unit had last started the day before. The peer units carry the PSK and
  # are Requires=/WantedBy= this unit, so cycling it cycles them too.
  sops.secrets.homelab_wireguard_private_key.restartUnits = [ "wireguard-wg0.service" ];
  # same PSK file content as vps's wireguard_vps_homelab_psk — see
  # hosts/vps/configuration.nix's peer entry.
  sops.secrets.wireguard_vps_homelab_psk.restartUnits = [ "wireguard-wg0.service" ];
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.2/24" ];
    privateKeyFile = config.sops.secrets.homelab_wireguard_private_key.path;
    peers = [
      {
        # vps
        publicKey = "ngxeCJV7bMtJQS1x93UhEuiWdLNXbCAsESrN4bcOrxk=";
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

  # /nix/state's .zfs/snapshot directory was world-traversable (0777),
  # letting any local uid read old snapshot contents at whatever
  # permissions they had at snapshot time -- proven live, and how the
  # factorio credentials leaked. `snapdir=disabled` closes it entirely
  # (verified: even root gets ENOENT on the exact path that used to
  # succeed for uid 65534) and, unlike a raw chmod on `.zfs`, is real
  # dataset metadata that survives a mount cycle rather than resetting.
  # Servers only -- see
  # `2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md`#D1
  # for why the PCs are deliberately excluded and the caveat that this
  # needs a mount cycle (not just a switch) to fully close access already
  # cached before the property changes.
  myZfsDatasetProperties."zroot/local/state".snapdir = "disabled";

  # Each pool root dataset's own properties, self-healed live too now,
  # not just at disko install. plan:
  # 2026-09-01-unify-myzfsdatasetproperties-and-disko-so-one-declaration-covers-both.md#G2
  myZfsDatasetProperties."zroot" = vars.zfsRootFsOptions;
  myZfsDatasetProperties."zdata" = vars.zfsRootFsOptions;
  myZfsDatasetProperties."zbackup" = vars.zfsRootFsOptions;

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

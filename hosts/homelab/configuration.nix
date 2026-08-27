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
    # Fields are: type path mode user group age [argument]. This previously
    # read "d /srv 0770 - root root -", which puts "-" in the user field and
    # shifts everything right, landing "root" in the *age* field --
    # systemd-tmpfiles rejects the whole line with "Invalid age 'root'" and
    # carries on, so /srv was silently left at its default 0755 for the
    # entire life of this config. That matters because /srv holds factorio's
    # server directories (which contain the account token and game password)
    # and jellyfin's config, so they were world-readable throughout.
    "d /srv 0770 root root -"
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
        # Persistent=false (default) is deliberate: after a long outage this
        # would otherwise fire its missed run immediately at boot, piling
        # ~2.9TiB of I/O on top of zrepl's own post-boot catch-up
        # replication (see TODO.md). Skipping straight to next Friday
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
    # the weekly restic->Backblaze run can take multiple days (~2.9TiB) —
    # switch-to-configuration restarts any unit whose definition changed, so
    # a same-cycle switch would kill it mid-run. Defer instead (see TODO.md).
    protectedUnits = [ "restic-backups-backblazeWeekly.service" ];
    # DISABLED 2026-08-27, deliberately and temporarily. Removes both the
    # flake-update-test and auto-switch timers; the services stay, so
    # `systemctl start auto-switch-now` is still the manual deploy path.
    #
    # Two reasons. There is active development, so these hosts are being
    # deployed by hand anyway — the scheduled path buys nothing right now
    # while carrying every risk in the D11 analysis. And the pipeline is
    # being rebuilt rather than patched (TODO.md, "rebuild the
    # update/build/deploy pipeline properly"), so leaving the old shape
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
    # offsite restic backup runs weekly (Fri 03:00) and can now take up to
    # TimeoutStartSec=1w to finish a single run, so 192h (8 days) would give
    # zero slack; 336h = 14 days gives a full week of slack past a
    # worst-case 1-week run before alerting on a missed/stuck run.
    staleMarkerFiles = {
      "/var/lib/restic-backups-backblazeWeekly/last-success" = 336;
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

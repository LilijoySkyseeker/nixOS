{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  vars,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    ../../profiles/default.nix
    ../../profiles/server.nix

    ../../services/jellyfin.nix
    ../../services/minecraft.nix
    #   ../../services/nextcloud.nix
    ../../services/rss.nix
    #   ../../services/webdav.nix
    ../../services/copyparty.nix
    #   ../../services/samba.nix

    ../../modules/nixos/beets.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [
      # STABLE installed packages
      sanoid # also installs syncoid and findoid
      zfs
      restic
      backblaze-b2
      btop
      tmux
      zellij
    ])
    ++ (with pkgs-unstable; [
      # UNSTABLE installed packages
    ]);

  # auto updates
  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
    flake = "/etc/nixos";
    flags = [
      "--update-input"
      "nixpkgs"
      "--update-input"
      "nixpkgs-unstable"
      "--update-input"
      "home-manager"
      "--update-input"
      "stylix"
      "--update-input"
      "sops-nix"
      "--update-input"
      "disko"
      "--update-input"
      "impermanence"
      "--update-input"
      "nixvim"
      "--update-input"
      "nix-on-droid"
      "--commit-lock-file"
    ];
    allowReboot = true;
  };

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # networking
  networking.networkmanager = {
    enable = true;
    insertNameservers = ["8.8.8.8" "1.1.1.1"];
  };

  # directory permissions
  systemd.tmpfiles.rules = [
    "d /srv 0770 - root root -"
    "A /storage - - - - group::rwx"
    "A /storage-bulk - - - - group::rwx"
  ];

  # caddy
  services.caddy = {
    enable = true;
    #   acmeCA = "https://acme.zerossl.com/v2/DV90";
    email = "lilijoyskyseeker@gmail.com";
  };
  networking.firewall.allowedTCPPorts = [
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443
  ];

  # duckdns
  services.cron = {
    enable = true;
    systemCronJobs = [
      "*/5 * * * * /etc/duckdns/duck.sh >/dev/null 2>&1"
    ];
  };

  # backblaze secrets prefetcher for rclone config file
  sops.secrets = {
    homelab_backblaze_restic_AWS_ACCESS_KEY_ID = {};
    homelab_backblaze_restic_AWS_SECRET_ACCESS_KEY = {};
    homelab_backblaze_restic_password = {};
  };
  systemd.services.restic-backups-backblazeDaily-startup = {
    enable = true;
    wantedBy = ["multi-user.target"];
    before = ["restic-backups-backblazeDaily.service"];
    script = ''
      rm -rf /etc/rclone
      mkdir /etc/rclone
      echo "[backblazeDaily]" >> /etc/rclone/rcloneCfg
      echo "type = b2" >> /etc/rclone/rcloneCfg
      echo "account = $(cat ${config.sops.secrets.homelab_backblaze_restic_AWS_ACCESS_KEY_ID.path})" >> /etc/rclone/rcloneCfg
      echo "key = $(cat ${config.sops.secrets.homelab_backblaze_restic_AWS_SECRET_ACCESS_KEY.path})" >> /etc/rclone/rcloneCfg
    '';
    serviceConfig = {
      User = "root";
      Type = "oneshot";
    };
  };

  # restic to backblaze with rclone https://restic.readthedocs.io/en/latest/050_restore.html
  services.restic.backups = {
    backblazeDaily = {
      initialize = true;
      createWrapper = true; # usable with restic-backblazeDaily
      passwordFile = "${config.sops.secrets.homelab_backblaze_restic_password.path}";
      repository = "rclone:backblazeDaily:restic21029709384"; # using rclone because the normal restic s3 b2 integration did not work with both the service and the wrapper
      rcloneOptions = {
        transfers = "32";
        b2-hard-delete = "false";
      };
      rcloneConfigFile = "/etc/rclone/rcloneCfg";
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
      paths = [
        "/tmp/restic"
      ];
      timerConfig = {
        OnCalendar = "04:00";
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
  systemd.services.restic-backups-backblazeDaily = {
    path = [
      # necessary for pre and post scripts
      pkgs.zfs
      pkgs.coreutils-full
      pkgs.mount
      pkgs.umount
      pkgs.findutils
      pkgs.bash
    ];
    serviceConfig = {
      # backup is always lowest priority to not effect running processes
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      PrivateTmp = lib.mkForce false;
    };
  };

  # zfs snapshots
  services.sanoid = {
    enable = true;
    extraArgs = ["--verbose"];
    interval = "minutely";
    settings = {
      "zroot/local/state".use_template = "working";
      "zdata/storage/storage".use_template = "working";
      "zdata/storage/storage-bulk".use_template = "working";
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
    commonArgs = ["--no-sync-snap"]; # "--create-bookmark" for mobile machines
    commands = {
      "zdata/storage/storage" = {
        source = "zdata/storage/storage";
        target = "zbackup/backup/homelab/storage";
        extraArgs = ["--identifier=zdata_storage_storage"];
      };
      "zdata/storage/storage-bulk" = {
        source = "zdata/storage/storage-bulk";
        target = "zbackup/backup-bulk/homelab/storage-bulk";
        extraArgs = ["--identifier=zdata_storage_storage-bulk"];
      };
      "zroot/local/state" = {
        source = "zroot/local/state";
        target = "zbackup/backup/homelab/state";
        extraArgs = ["--identifier=zroot_local_state"];
      };
    };
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

  #security
  # lock down nix
  nix.settings.allowed-users = ["root"];
  # disable sudo
  security.sudo.enable = false;

  # ssh server
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    enable = true;
    allowSFTP = true;
    settings.KbdInteractiveAuthentication = false;
    extraConfig = ''
      passwordAuthentication = no
      PermitRootLogin = prohibit-password
      AllowTcpForwarding yes
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
  boot.supportedFilesystems = ["zfs"];
  ##   environment.systemPackages = with pkgs; [zfs];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "e0019fd8";

  # impermanance
  fileSystems."/nix/state".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;
  boot.initrd = {
    systemd = {
      enable = true;
      services.rollback = {
        description = "Rollback root filesystem to a pristine state on boot";
        wantedBy = ["initrd.target"];
        after = ["zfs-import-zroot.service"];
        before = ["sysroot.mount"];
        path = with pkgs; [zfs];
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
      "/etc/duckdns"
      "/var/log"
      "/var/lib/systemd/timers" # for systemd persistant timers during off time
      "/var/lib/nixos" # to stop complaiing about uid and guid on reboot
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };
}

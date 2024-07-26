{
  config,
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  vars,
  sops-nix,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos/shared.nix
    ../../modules/nixos/profiles/server.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [
      # STABLE installed packages
      sanoid # also installs syncoid and findoid
      zfs
      restic
      backblaze-b2
    ])
    ++ (with pkgs-unstable; [
      # UNSTABLE installed packages
    ]);

  # backblaze secrets prefetcher
  systemd.services.restic-backups-backblazeDaily-startup = {
    enable = true;
    wantedBy = ["multi-user.target"];
    before = ["restic-backups-backblazeDaily.service"];
    script = ''
      rm -rf /etc/restic
      mkdir /etc/restic
      echo "AWS_ACCESS_KEY_ID=$(cat ${config.sops.secrets.homelab_backblaze_restic_AWS_ACCESS_KEY_ID.path})" >> /etc/restic/resticEnv
      echo "AWS_SECRET_ACCESS_KEY=$(cat ${config.sops.secrets.homelab_backblaze_restic_AWS_SECRET_ACCESS_KEY.path})" >> /etc/restic/resticEnv
      echo "RCLONE_CONFIG_RESTIC_ACCESS_KEY_ID=$(cat ${config.sops.secrets.homelab_backblaze_restic_AWS_ACCESS_KEY_ID.path})" >> /etc/restic/rcloneConfig
      echo "RCLONE_CONFIG_RESTIC_SECRET_ACCESS_KEY=$(cat ${config.sops.secrets.homelab_backblaze_restic_AWS_SECRET_ACCESS_KEY.path})" >> /etc/restic/rcloneConfig
      echo "RCLONE_CONFIG_RESTIC_TYPE=b2" >> /etc/restic/rcloneConfig
    '';
    serviceConfig = {
      User = "root";
      Type = "oneshot";
    };
  };

  # restic to backblaze https://restic.readthedocs.io/en/latest/050_restore.html
  sops.secrets = {
    homelab_backblaze_restic_AWS_ACCESS_KEY_ID = {};
    homelab_backblaze_restic_AWS_SECRET_ACCESS_KEY = {};
    homelab_backblaze_restic_password = {};
    homelab_backblaze_restic_repository = {};
  };
  services.restic.backups = {
    backblazeDaily = {
      initialize = true;
      createWrapper = true;
      passwordFile = "${config.sops.secrets.homelab_backblaze_restic_password.path}";
      repositoryFile = "${config.sops.secrets.homelab_backblaze_restic_repository.path}";
      environmentFile = "/etc/restic/resticEnv";
      #     rcloneConfig = {
      #       hard_delete = false;
      #       type = "b2";
      #     };
      rcloneConfigFile = "/etc/restic/rcloneConfig";
      backupPrepareCommand = ''
        zfs snapshot zbackup@restic -r
        zfs list -t snapshot | grep -o "zbackup.*restic" | xargs -I {} bash -c "mkdir -p /tmp/{} && mount -t zfs {} /tmp/{}"
      '';
      backupCleanupCommand = ''
        zfs list -t snapshot | grep -o "zbackup.*restic" | xargs -I {} bash -c "umount -t zfs {}"
        rm -rf /tmp/zbackup
        zfs destroy zbackup@restic -r
      '';
      user = "root";
      paths = [
        "/tmp/zbackup"
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
        "--read-data-subset=1%"
      ];
    };
  };
  systemd.services.restic-backups-backblazeDaily = {
    environment = {
    };
    path = [
      pkgs.zfs
      pkgs.coreutils-full
      pkgs.mount
      pkgs.umount
      pkgs.findutils
      pkgs.bash
    ];
    serviceConfig = {
      Nice = 19;
      CPUSchedulingPolicy = "idle";
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
        daily = 0;
        weekly = 0;
        monthly = 0;
        yearly = 0;
        autosnap = "yes";
        autoprune = "yes";
      };
      "zbackup/backup" = {
        use_template = "backup";
        recursive = "yes";
      };
      template_backup = {
        frequently = 0;
        hourly = 168;
        daily = 32;
        weekly = 0;
        monthly = 12;
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
    '';
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
      "/var/log"
      "/etc/nixos"
      "/var/lib/systemd/timers" # for systemd persistant timers during off time
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}

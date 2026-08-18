{
  pkgs-unstable,
  pkgs-stable,
  lib,
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./nvidia.nix
    ./disko.nix
    ../../profiles/PC.nix
    ../../modules/nixos/kde.nix
    ../../modules/nixos/pull-deploy.nix
    ../../modules/nixos/nfs-homelab-mounts.nix
    ../../modules/nixos/backup-push.nix
    ../../modules/nixos/zfs-space-guard.nix
  ];

  myPullDeploy = {
    enable = true;
    flakeDir = "/home/lilijoy/dotfiles";
    hostAttr = "thinkpad";
    dates = "Thu 03:00";
    autoReboot = false;
    operation = "boot";
    requireACPower = true;
  };

  # System installed pkgs
  environment.systemPackages =
    (with pkgs-unstable; [
    ])
    ++ (with pkgs-stable; [
    ]);

  # fingerprint reader
  services.fprintd.enable = true;

  # state change settings/buttons
  services.logind.settings.Login = {
    HandleLidSwitch = "hybrid-sleep";
    HandlePowerKey = "poweroff";
  };

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

  # keyboard
  services.keyd = {
    enable = true;
    keyboards.default.ids = [ "0001:0001" ];
    keyboards.default.settings = {
      main = {
        # mods
        capslock = "overload(control, esc)";
        esc = "overload(capslock, esc)";
        leftalt = "layer(navigation)";
        leftcontrol = "leftalt";
      };
      navigation = {
        j = "left";
        k = "down";
        i = "up";
        l = "right";
        u = "pageup";
        o = "pagedown";
      };
    };
  };

  # Define your hostname.
  networking.hostName = "thinkpad";

  # Fix Clickpad Bug and Intel CPU freq stuck fix
  boot.kernelParams = [
    "psmouse.synaptics_intertouch=0"
    "intel_pstate=active"
  ];

  # zfs snapshots
  services.sanoid = {
    enable = true;
    extraArgs = [ "--verbose" ];
    interval = "minutely";
    settings = {
      "zroot/local/root".use_template = "working";
      "zroot/local/home".use_template = "working";
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
    };
  };
  systemd.services.sanoid.serviceConfig = {
    User = lib.mkForce "root";
  };

  # zfs support
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "5f763495";
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/nix/state".neededForBoot = true;

  # push home+root snapshots to homelab's zbackup pool over tailscale
  # (see TODO.md "syncoid push backups" for the design)
  sops.secrets.thinkpad_backup_push_key = {
    owner = "backup-push"; # readable only by the dedicated backup-push user, not root-wide
  };
  myBackupPush = {
    enable = true;
    targetHost = "backup-recv@homelab";
    identityFile = config.sops.secrets.thinkpad_backup_push_key.path;
    datasets = {
      # backup-bulk, not backup: this data (large game libraries under
      # home) is not offsite-eligible — see hosts/homelab/disko.nix.
      "zroot/local/home" = "zbackup/backup-bulk/thinkpad/home";
      "zroot/local/root" = "zbackup/backup-bulk/thinkpad/root";
    };
  };

  # same rationale as torrent's myZfsSpaceGuard (see its comment) — this
  # laptop's home also carries large game libraries.
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

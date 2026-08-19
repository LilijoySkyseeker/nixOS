{
  config,
  pkgs-unstable,
  pkgs-stable,
  lib,
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
    ../../modules/nixos/build-worker.nix
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

  # distributed builds — thinkpad submits its own rebuilds to
  # homelab/torrent, accepts builds submitted by them, and drops out of
  # rotation as a worker while on battery (myBuildWorker.acGated below).
  # See .claude/plans/quirky-herding-teapot.md.
  myBuildWorker = {
    enable = true;
    acGated = true;
    # TODO before deploying: confirm the real AC supply node name via
    # `ls /sys/class/power_supply/` on thinkpad — "AC" is a guess.
    acPowerSupplyName = "AC";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMqCpIC0zswd04rbRZU+DYx3T0BXzIvpZB6Z6fvlrFZH nix-builder@thinkpad"
    ];
  };
  sops.secrets.builder_key_homelab = { };
  sops.secrets.builder_key_torrent = { };
  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "torrent";
      sshUser = "nix-builder";
      sshKey = config.sops.secrets.builder_key_torrent.path;
      protocol = "ssh-ng";
      # TODO before deploying: fetch and set publicHostKey via
      # `ssh-keyscan torrent | grep ed25519 | awk '{print $3}' | base64 -w0`
      systems = [ "x86_64-linux" ];
      # TODO confirm live via `nproc` on torrent before deploying
      maxJobs = 8;
      speedFactor = 3;
    }
    {
      hostName = "homelab";
      sshUser = "nix-builder";
      sshKey = config.sops.secrets.builder_key_homelab.path;
      protocol = "ssh-ng";
      # TODO before deploying: fetch and set publicHostKey via
      # `ssh-keyscan homelab | grep ed25519 | awk '{print $3}' | base64 -w0`
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # TODO confirm live via `nproc` on homelab before deploying
      maxJobs = 8;
      speedFactor = 2;
    }
  ];

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
}

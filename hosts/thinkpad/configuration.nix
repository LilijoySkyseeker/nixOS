{
  pkgs-unstable,
  pkgs-stable,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./nvidia.nix
    ./disko.nix

    inputs.lanzaboote.nixosModules.lanzaboote

    ../../profiles/PC.nix
    ../../modules/nixos/kde.nix
    ../../modules/nixos/pull-deploy.nix
    ../../modules/nixos/nfs-homelab-mounts.nix
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
      sbctl # Secure Boot key mgmt/debugging (boot.lanzaboote below)
    ])
    ++ (with pkgs-stable; [
    ]);

  # Secure Boot (TODO.md Phase 1: lanzaboote), tested here first —
  # easiest host to physically recover if boot breaks. Beta-quality
  # upstream (NixOS wiki flags sharp edges). See README.md for the
  # one-time manual sbctl/firmware steps this config alone can't do.
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
  boot.loader.systemd-boot.enable = lib.mkForce false;

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

  # impermanence (TODO.md Phase 2: folded in alongside the LUKS
  # reinstall since it's already mandatory). Root goes ephemeral,
  # /home stays untouched — it's already its own zfs dataset
  # (local/home in disko.nix), separate from local/root, so the
  # rollback below never touches it. Mirrors homelab's existing
  # pattern (hosts/homelab/configuration.nix); the flake checkout
  # itself lives under /home/lilijoy/dotfiles (myPullDeploy above), so
  # unlike homelab this host doesn't need /etc/nixos persisted.
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
  environment.persistence."/nix/state" = {
    enable = true;
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/systemd/timers" # persistent timers across reboots
      "/var/lib/nixos" # avoids uid/gid complaints on reboot
      "/var/lib/sops-nix" # profiles/PC.nix's sops.age.generateKey identity
      "/var/lib/sanoid" # snapshot state cache
      "/var/lib/NetworkManager" # connection state
      "/etc/NetworkManager/system-connections" # actual saved wifi profiles
      "/var/lib/bluetooth" # paired device keys
      "/var/lib/fprint" # fprintd-enrolled fingerprints (services.fprintd above)
      "/var/lib/containers" # podman/distrobox images, avoids re-pulling
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };
}

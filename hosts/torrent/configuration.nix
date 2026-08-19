{
  pkgs-unstable,
  pkgs-stable,
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    inputs.lanzaboote.nixosModules.lanzaboote

    ../../profiles/PC.nix
    ../../modules/nixos/kde.nix
    ../../modules/nixos/pull-deploy.nix
    ../../modules/nixos/nfs-homelab-mounts.nix
    ../../modules/nixos/iso-autobuild.nix
  ];
  home-manager.users.lilijoy.imports = [ ];

  myPullDeploy = {
    enable = true;
    flakeDir = "/home/lilijoy/dotfiles";
    hostAttr = "torrent";
    dates = "Thu 03:00";
    autoReboot = false;
    operation = "boot";
  };

  # rebuild the recovery iso into ~/Downloads every time pull-deploy
  # successfully updates this host, for manual copying onto Ventoy
  myIsoAutobuild = {
    enable = true;
    flakeDir = "/home/lilijoy/dotfiles";
    buildUser = "lilijoy";
    isoAttr = "isoimage";
    triggeredBy = [ "pull-deploy.service" ];
  };

  # System installed pkgs
  environment.systemPackages =
    (with pkgs-unstable; [
      # closed source
      bambu-studio
      sbctl # Secure Boot key mgmt/debugging (boot.lanzaboote below)
    ])
    ++ (with pkgs-stable; [
    ]);

  # drivers, r8125 for ethernet, look for when kernel is 6.7+ to try wifi and bt drivers, https://wireless.docs.kernel.org/en/latest/en/users/drivers/mediatek.html, mt7925
  boot.extraModulePackages = with config.boot.kernelPackages; [ r8125 ];
  boot.kernelModules = [ "r8125" ];
  nixpkgs.config.allowBroken = true; # check on next stable release to see if needed

  # Secure Boot (TODO.md Phase 1: lanzaboote), landed after thinkpad
  # proved it out. Beta-quality upstream (NixOS wiki flags sharp
  # edges). See README.md for the one-time manual sbctl/firmware steps
  # this config alone can't do.
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
  boot.loader.systemd-boot.enable = lib.mkForce false;

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

  # cpu power management
  powerManagement.cpuFreqGovernor = "performance";

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Define your hostname.
  networking.hostName = "torrent";

  # zfs support
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "0376f9ae";
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
      "/etc/NetworkManager/system-connections" # actual saved wifi/ethernet profiles
      "/var/lib/bluetooth" # paired device keys
      "/var/lib/containers" # podman/distrobox images, avoids re-pulling
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };
}

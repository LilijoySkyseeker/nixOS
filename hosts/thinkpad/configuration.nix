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
    ./nvidia.nix
    ./disko.nix

    ../../profiles/PC.nix
    ../../modules/nixos/kde.nix
    ../../modules/nixos/pull-deploy.nix
    ../../modules/nixos/nfs-homelab-mounts.nix
    ../../modules/nixos/phase2-gate.nix
    ../../modules/nixos/secure-boot.nix
    ../../modules/nixos/zfs-support.nix
    ../../modules/nixos/zfs-snapshots.nix
    ../../modules/nixos/zfs-root-impermanence.nix
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

  # Secure Boot (modules/nixos/secure-boot.nix — TODO.md Phase 1),
  # tested here first — easiest host to physically recover if boot
  # breaks.
  mySecureBoot.enable = config.myPhase2.reinstalled;

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

  # zfs snapshots (modules/nixos/zfs-snapshots.nix — defaults match
  # this host's prior inline template, so no override needed here)
  myZfsSnapshots = {
    enable = true;
    workingDatasets = [
      "zroot/local/root"
      "zroot/local/home"
    ];
  };

  # zfs support (modules/nixos/zfs-support.nix)
  myZfsSupport = {
    enable = true;
    hostId = "5f763495";
  };

  # impermanence (modules/nixos/zfs-root-impermanence.nix — TODO.md
  # Phase 2, folded in alongside the LUKS reinstall since it's already
  # mandatory). Root goes ephemeral, /home stays untouched — it's
  # already its own zfs dataset (local/home in disko.nix), separate
  # from local/root, so the rollback never touches it. Mirrors
  # homelab's existing pattern; the flake checkout itself lives under
  # /home/lilijoy/dotfiles (myPullDeploy above), so unlike homelab
  # this host doesn't need /etc/nixos persisted (module default files
  # list — machine-id + SSH host key — covers what's needed as-is).
  myZfsImpermanence = {
    enable = config.myPhase2.reinstalled;
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

      # GUI desktop state (verified against the pinned nixpkgs source,
      # not assumed — modules/nixos/kde.nix enables plasma6+sddm, whose
      # own module forces services.accounts-daemon.enable and defaults
      # services.power-profiles-daemon/upower on via
      # config.powerManagement.enable):
      "/var/lib/AccountsService" # user icon + session/language picked in
      # SDDM's greeter — accountsservice is force-enabled by the plasma6
      # module; without this, the account picture and last-used session
      # reset every boot
      "/var/lib/upower" # battery history (upower.enable follows
      # config.powerManagement.enable, on by default) — battery health
      # estimates reset every boot otherwise, most relevant on a laptop
      "/etc/cups" # printer definitions (services.printing, profiles/PC.nix)
      "/var/lib/flatpak" # declaratively-managed apps (services.flatpak,
      # profiles/PC.nix) — without this every boot would re-download
      # Grayjay/BAR + runtimes from Flathub from scratch
      "/var/lib/waydroid" # Android container rootfs/image
      # (virtualisation.waydroid, profiles/PC.nix) — multi-GB, avoids a
      # full `waydroid init` re-provision every boot
    ];
  };
}

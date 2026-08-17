{
  pkgs-unstable,
  modulesPath,
  vars,
  config,
  lib,
  ...
}:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    "${modulesPath}/installer/cd-dvd/channel.nix"
    ../../services/copyparty-iso.nix
  ];
  nixpkgs.hostPlatform = "x86_64-linux";

  environment.systemPackages = with pkgs-unstable; [
    neovim
    git
    tmux
    btop

    # partitioning / disk layout
    disko
    parted
    gptfdisk
    ntfs3g
    exfatprogs

    # filesystem tools for whatever a target/failed disk is running
    e2fsprogs
    xfsprogs
    btrfs-progs
    dosfstools

    # data recovery / cloning / imaging
    ddrescue
    testdisk
    cpio

    # disk & hardware diagnostics
    smartmontools
    nvme-cli
    pciutils
    usbutils
    dmidecode
    lm_sensors

    # cloning/sync/backup — mirrors the tooling homelab/thinkpad/torrent
    # use, so a recovered disk can be restored from/to the same targets
    rsync
    rclone
    restic
    backblaze-b2
    sanoid # also installs syncoid, for zfs snapshot send/receive recovery

    # networking diagnostics
    inetutils
    nmap
    tcpdump
  ];

  # zfs recovery/import support — homelab's pool needs to be importable
  # from this ISO in a disk-failure scenario. Pinned nixpkgs-unstable
  # kernel/zfs compat can lag; if this fails to build, drop
  # boot.zfs.forceImportRoot and re-pin `boot.kernelPackages` to the
  # latest kernel zfs actually supports.
  boot.supportedFilesystems = [
    "zfs"
    "btrfs"
    "xfs"
    "ntfs"
  ];
  networking.hostId = "10ad6c0f"; # required by zfs, arbitrary+fixed for this iso

  # wifi, for on-site recovery where only wireless is available
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # "minimal" -> "recovery": overrides installation-cd-minimal.nix's
  # isoImage.edition. The rest of the filename (nixos version + build
  # date + revision) is already dynamic via system.nixos.label, e.g.
  # nixos-recovery-26.11.20260813.<rev>-x86_64-linux.iso.
  isoImage.edition = "recovery";

  # recovery convenience: auto-login as root, no password, on the
  # local tty this boots to. Root already has an empty password by
  # default on nixos installer media (installation-device.nix); this
  # only swaps *which* account autologins from "nixos" to "root" so a
  # local user has full access immediately. SSH stays locked to
  # pubkey-only regardless (see services.openssh below).
  services.getty.autologinUser = lib.mkForce "root";

  # drivers
  boot.extraModulePackages = with config.boot.kernelPackages; [ r8125 ];
  boot.kernelModules = [ "r8125" ];

  # TEMP BYPASS FOR 'r8125' driver
  nixpkgs.config.allowBroken = true;

  # ssh server
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    ports = [ 22 ];
    allowSFTP = true;
    enable = true;
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
}

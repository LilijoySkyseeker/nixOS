{
  config,
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/shared.nix
    ../../modules/nixos/wooting.nix
    ../../modules/home-manager/profiles/PC.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [cura]) # STABLE installed packages
    ++ (with pkgs-unstable; []); # UNSTABLE installed packages

  # Home Manager
  home-manager.users.lilijoy.dconf.settings = {
    "org/gnome/shell/extensions/tiling-assistant" = {
      # Tiling Assistant
      window-gap = 8;
      single-screen-gap = 8;
    };
  };

  # allow qmk and via
  hardware.keyboard.qmk.enable = true;

  # Define your hostname.
  networking.hostName = "nixos-legion";

  # Set extra groups
  users.users.lilijoy.extraGroups = ["docker"];

  # NVIDIA ========================================================================================
  hardware.opengl = {
    # enable openGL
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  services.xserver.videoDrivers = ["nvidia"]; # Load nvidia driver for Xorg and Wayland
  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = false;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = false;

    # Enable the Nvidia settings menu.
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  # ===============================================================================================

  # State Version for first install, don't touch
  system.stateVersion = "23.11";
}

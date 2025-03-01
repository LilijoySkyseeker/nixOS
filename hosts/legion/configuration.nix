{
  config,
  pkgs-unstable,
  pkgs-stable,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/PC.nix
    ../../modules/nixos/kde.nix
  ];

  # Intel CPU freq stuck fix
  boot.kernelParams = [ "intel_pstate=active" ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs-unstable; [
    ])
    ++ (with pkgs-stable; [
    ]);

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Define your hostname.
  networking.hostName = "legion";

  # NVIDIA ========================================================================================
  hardware = {
    graphics.enable = true;
    graphics.enable32Bit = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ]; # Load nvidia driver for Xorg and Wayland
  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = true;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = true;

    # Enable the Nvidia settings menu.
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  # ===============================================================================================
}

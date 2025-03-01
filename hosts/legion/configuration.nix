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
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };
  # ===============================================================================================
}

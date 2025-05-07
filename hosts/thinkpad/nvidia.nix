{ config, lib, ... }:
{
  config.specialisation.gpu-enabled.configuration = {
    environment.etc."specialisation".text = "gpu-enabled"; # for nh helper
    # NVIDIA ==============================================================================
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
      package = config.boot.kernelPackages.nvidiaPackages.stable; # info for beta/specific drivers https://github.com/NixOS/nixpkgs/pull/322963/commits/10ed11d6856a7b67b9b2cef5e52af5c7de34b93f and reddit post https://www.reddit.com/r/NixOS/comments/1dqipyx/updating_nvidia_driver_from_5554202_to_the_latest/
    };
    hardware.nvidia.prime = {
      # Bus ID of the Intel GPU.
      intelBusId = lib.mkDefault "PCI:0:2:0";
      # Bus ID of the NVIDIA GPU.
      nvidiaBusId = lib.mkDefault "PCI:1:0:0";
      # set primary render to NVIDIA gpu, but use intel gpu display outputs
      sync.enable = true;
    };
    # =====================================================================================
  };

  # default gpu-disabled
  imports = [
    (
      { lib, config, ... }:
      {
        config = lib.mkIf (config.specialisation != { }) {
          boot.extraModprobeConfig = ''
            blacklist nouveau
            options nouveau modeset=0
          '';
          boot.blacklistedKernelModules = [
            "nouveau"
            "nvidia"
            "nvidia_drm"
            "nvidia_modeset"
          ];

          services.udev.extraRules = ''
            # Remove NVIDIA USB xHCI Host Controller devices, if present
            ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
            # Remove NVIDIA USB Type-C UCSI devices, if present
            ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
            # Remove NVIDIA Audio devices, if present
            ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
            # Remove NVIDIA VGA/3D controller devices
            ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
          '';
        };
      }
    )
  ];
}

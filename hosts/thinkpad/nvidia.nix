{ config, lib, ... }:
{
  config.specialisation.gpu-enabled.configuration = {
    environment.etc."specialisation".text = "gpu-enabled"; # for nh helper
    hardware = {
      graphics.enable = true;
      graphics.enable32Bit = true;
    };

    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia = {
      modesetting.enable = true;
      # saves VRAM across hibernation; without it the display breaks on resume
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      open = true;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };
    hardware.nvidia.prime = {
      intelBusId = lib.mkDefault "PCI:0:2:0";
      nvidiaBusId = lib.mkDefault "PCI:1:0:0";
      sync.enable = true;
    };
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
            ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
            ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
            ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
            ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
          '';
        };
      }
    )
  ];
}

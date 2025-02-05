{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/wooting.nix
    ../../profiles/PC.nix
    ../../modules/nixos/gnome.nix
  ];

  # Intel CPU freq stuck fix
  boot.kernelParams = [ "intel_pstate=active" ];

  # GS Connect
  services.kdeconnect.package = pkgs.gnomeExtensions.gsconnect;

  # System installed pkgs
  environment.systemPackages = with pkgs; [
  ];

  # disable laptop display
  services.xserver = {
    monitorSection = ''
      Identifier "integrated display"
      Option "ignore" "true"
    '';
    deviceSection = ''
      Identifier "onboard"
      Option "Monitor-DP-2" "integrated display"
    '';
  };

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

  # udev rules for vial
  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';

  # Home Manager
  home-manager.users.lilijoy.dconf.settings = {
    "org/gnome/shell/extensions/tiling-assistant" = {
      # Tiling Assistant
      window-gap = 8;
      single-screen-gap = 8;
    };
  };
  home-manager.users.lilijoy.imports = [ ../../../modules/home-manager/gnome.nix ];

  # Set your time zone.
  time.timeZone = "America/New_York";

  # allow qmk and via
  hardware.keyboard.qmk.enable = true;

  # Define your hostname.
  networking.hostName = "legion";

  # Set extra groups
  users.users.lilijoy.extraGroups = [ "docker" ];

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
    # 535 driver
    package =
      let
        rcu_patch = pkgs.fetchpatch {
          url = "https://github.com/gentoo/gentoo/raw/c64caf53/x11-drivers/nvidia-drivers/files/nvidia-drivers-470.223.02-gpl-pfn_valid.patch";
          hash = "sha256-eZiQQp2S/asE7MfGvfe6dA/kdCvek9SYa/FFGp24dVg=";
        };
      in
      config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "535.154.05";
        sha256_64bit = "sha256-fpUGXKprgt6SYRDxSCemGXLrEsIA6GOinp+0eGbqqJg=";
        sha256_aarch64 = "sha256-G0/GiObf/BZMkzzET8HQjdIcvCSqB1uhsinro2HLK9k=";
        openSha256 = "sha256-wvRdHguGLxS0mR06P5Qi++pDJBCF8pJ8hr4T8O6TJIo=";
        settingsSha256 = "sha256-9wqoDEWY4I7weWW05F4igj1Gj9wjHsREFMztfEmqm10=";
        persistencedSha256 = "sha256-d0Q3Lk80JqkS1B54Mahu2yY/WocOqFFbZVBh+ToGhaE=";
        patches = [ rcu_patch ];
      };
  };
  # ===============================================================================================
}

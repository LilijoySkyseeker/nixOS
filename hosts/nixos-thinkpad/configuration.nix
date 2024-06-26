{ config, pkgs, pkgs-unstable, inputs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
       inputs.home-manager.nixosModules.default

       ../../modules/nixos/shared.nix
    ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [ # STABLE installed packages

    ])
    ++
    (with pkgs-unstable; [ # UNSTABLE installed packages

    ]);

  # Enviromental Variables
  environment.sessionVariables = {
    FLAKE = "/home/lilijoy/dotfiles";
  };

  # Stylix
  stylix = {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = /home/lilijoy/dotfiles/files/gruvbox-dark-rainbow.png;
    polarity = "dark";
    cursor.package = pkgs.capitaine-cursors-themed;
    cursor.name = "Capitaine Cursors";
    };

  # Define your hostname.
  networking.hostName = "nixos-thinkpad"; 

  # Set extra groups
  users.users.lilijoy.extraGroups = [ "docker" "tss" ]; # tss for accessing tpm

  # Home Manager
  home-manager = {
    # also pass inputs to home-manager modules
    extraSpecialArgs = {inherit inputs;};
    users = {
      "lilijoy" = import ./home.nix;
    };
    backupFileExtension = "backup";# Force backup conflicted files
  };

  # NVIDIA ========================================================================================
  hardware.opengl = { # eanble openGL
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

  hardware.nvidia.prime = {
    # Bus ID of the Intel GPU.
    intelBusId = lib.mkDefault "PCI:0:2:0";
    # Bus ID of the NVIDIA GPU.
    nvidiaBusId = lib.mkDefault "PCI:1:0:0";

    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
  };
  # ==============================================================================================

  # Fix Clickpad Bug
  boot.kernelParams = [ "psmouse.synaptics_intertouch=0" ];

  # State Version for first install, don't touch
  system.stateVersion = "23.11";
}

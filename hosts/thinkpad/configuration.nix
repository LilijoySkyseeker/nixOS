{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../profiles/PC.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [
      # STABLE installed packages
      drawio
    ])
    ++ (with pkgs-unstable; [
      # UNSTABLE installed packages
    ]);

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

  services.keyd = {
    enable = true;
    keyboards.default.ids = ["0001:0001"];
    keyboards.default.settings = {
      main = {
        capslock = "overload(control, esc)";
        rightalt = "overload(navigation, backspace)";
        leftalt = "layer(navigation)";
        leftcontrol = "leftalt";
        esc = "layer(esc)";
      };
      navigation = {
        h = "left";
        j = "down";
        k = "up";
        l = "right";

        ";" = "%";
        "," = "^";
        "." = "$";

        leftshift = "timeout(<, 200, >)";
        z = "timeout([, 200, ])";
        x = "timeout({, 200, })";
        c = "timeout((, 200, ))";

        g = "=";

        w = "~";
        e = "#";
        r = "|";
        u = "@";
        i = "\\";
        o = "`";

        a = "oneshot(meta)";
        s = "oneshot(alt)";
        d = "oneshot(control)";
        f = "oneshot(shift)";

        leftalt = "layer(numbers)";
        rightalt = "overload(numbers, backspace)";
      };
      numbers = {
        j = "0";
        m = "1";
        "," = "2";
        "." = "3";
        k = "4";
        l = "5";
        "\;" = "6";
        u = "7";
        i = "8";
        o = "9";
      };
      colemak = {
        q = "q";
        w = "w";
        e = "f";
        r = "p";
        t = "b";
        y = "j";
        u = "l";
        i = "u";
        o = "y";
        p = ";";
        a = "a";
        s = "r";
        d = "s";
        f = "t";
        g = "g";
        h = "m";
        j = "n";
        k = "e";
        l = "i";
        ";" = "o";
        z = "x";
        x = "c";
        c = "d";
        v = "v";
        b = "z";
        n = "k";
        m = "h";
      };
      handsdown = {
        q = "timeout(j, 200, z)";
        w = "timeout(g, 200, q)";
        e = "m";
        r = "p";
        t = "v";
        y = "timeout(;, 200, :)";
        u = "timeout(., 200, &)";
        i = "timeout(\/, 200, *)";
        o = "timeout(\", 200, ?)";
        p = "timeout(\', 200, !)";
        a = "r";
        s = "s";
        d = "n";
        f = "d";
        g = "b";
        h = "timeout(\,, 200, _)";
        j = "a";
        k = "e";
        l = "i";
        ";" = "h";
        leftshift = "x";
        z = "f";
        x = "l";
        c = "c";
        v = "w";
        b = "noop";
        n = "timeout(-, 200, +)";
        m = "u";
        "," = "o";
        "." = "y";
        "\/" = "k";
        leftalt = "overload(navigation, t)";
      };
      esc = {
        "1" = "toggle(colemak)";
        "2" = "toggle(handsdown)";
      };
    };
  };

  # restic test https://restic.readthedocs.io/en/latest/050_restore.html
  services.restic.backups = {
    hourly = {
      initialize = true;
      passwordFile = "${config.sops.secrets.restic.path}";
      repository = "/home/lilijoy/backup";
      user = "lilijoy";
      paths = [
        "/home/lilijoy"
      ];
      exclude = [
        "/home/lilijoy/backup"
      ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
      pruneOpts = [
        "--host ${config.networking.hostName}"
        "--retry-lock 15m"
        "--keep-hourly 24"
        "--keep-daily 32"
      ];
    };
  };
  systemd.services.restic-backups-hourly.serviceConfig = {
    Nice = 19;
    CPUSchedulingPolicy = "idle";
  };

  #    users.users.restic = {
  #      description = "restic service user";
  #      isSystemUser = true;
  #      group = "nogroup";
  #    };

  # Define your hostname.
  networking.hostName = "thinkpad";

  # Set extra groups
  users.users.lilijoy.extraGroups = ["docker"];

  # NVIDIA ==============================================================================
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
    package = config.boot.kernelPackages.nvidiaPackages.stable; # info for beta/specific drivers https://github.com/NixOS/nixpkgs/pull/322963/commits/10ed11d6856a7b67b9b2cef5e52af5c7de34b93f and reddit post https://www.reddit.com/r/NixOS/comments/1dqipyx/updating_nvidia_driver_from_5554202_to_the_latest/
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
  # =====================================================================================

  # Fix Clickpad Bug
  boot.kernelParams = ["psmouse.synaptics_intertouch=0"];
}

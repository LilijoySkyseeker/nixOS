{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./nvidia.nix
    ../../profiles/PC.nix
  ];

  # System installed pkgs
  environment.systemPackages =
    with pkgs; [
      # STABLE installed packages
      drawio
    ];

  # state change settings/buttons
  services.logind = {
    lidSwitch = "hybrid-sleep";
    powerKey = "poweroff";
  };

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

  services.keyd = {
    enable = true;
    keyboards.default.ids = [ "0001:0001" ];
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
        k = "1";
        l = "2";
        ";" = "3";
        m = "4";
        "," = "5";
        "." = "6";
        u = "";
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
        i = "timeout(/, 200, *)";
        o = ''timeout(", 200, ?)'';
        p = "timeout(', 200, !)";
        a = "r";
        s = "s";
        d = "n";
        f = "d";
        g = "b";
        h = "timeout(,, 200, _)";
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
        "/" = "k";
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
      paths = [ "/home/lilijoy" ];
      exclude = [ "/home/lilijoy/backup" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
      pruneOpts = [
        "--host ${config.networking.hostName}"
        "--retry-lock 15m"
        "--keep-hourly 24"
        "--keep-daily 7"
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
  users.users.lilijoy.extraGroups = [ "docker" ];

  # Fix Clickpad Bug
  boot.kernelParams = [ "psmouse.synaptics_intertouch=0" ];
}

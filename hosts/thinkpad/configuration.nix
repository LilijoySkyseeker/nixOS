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
    ../../custom-packages/tpm-fido/package.nix
    ../../modules/nixos/gnome.nix
  ];

  # System installed pkgs
  environment.systemPackages = with pkgs; [
    drawio
    qalculate-gtk
  ];

  # sops secrets
  sops.secrets = {
    restic = {
      owner = config.users.users.lilijoy.name;
    };
  };

  # home manager
  home-manager.users.lilijoy.imports = [ ../../modules/home-manager/gnome.nix ];

  # GS Connect
  # services.kdeconnect.package = pkgs.gnomeExtensions.gsconnect;

  # tpm-fido
  tpm-fido.enable = true;

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
        rightalt = "layer(navigation)";
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
        rightalt = "layer(numbers)";
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
      esc = {
        "1" = "toggle(colemak)";
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

  # Fix Clickpad Bug and Intel CPU freq stuck fix
  boot.kernelParams = [
    "psmouse.synaptics_intertouch=0"
    "intel_pstate=active"
  ];
}

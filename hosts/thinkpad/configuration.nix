{
  pkgs-unstable,
  pkgs-stable,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./nvidia.nix
    ../../profiles/PC.nix
    ../../modules/nixos/gnome.nix
  ];
  home-manager.users.lilijoy.imports = [ ../../modules/home-manager/gnome.nix ];

  # System installed pkgs
  environment.systemPackages =
    (with pkgs-unstable; [
    ])
    ++ (with pkgs-stable; [
      openscad
      qalculate-gtk
    ]);

  # fingerprint reader
  services.fprintd.enable = true;

  # state change settings/buttons
  services.logind = {
    lidSwitch = "hybrid-sleep";
    powerKey = "poweroff";
  };

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

  # keyboard
  services.keyd = {
    enable = true;
    keyboards.default.ids = [ "0001:0001" ];
    keyboards.default.settings = {
      main = {
        capslock = "overload(control, esc)";
        rightalt = "overload(navigation, backspace)";
        leftalt = "overload(navigation, t)";
        leftcontrol = "leftalt";
        esc = "layer(esc)";
      };
      navigation = {
        j = "left";
        k = "down";
        i = "up";
        l = "right";
        u = "pageup";
        o = "pagedown";

        a = "oneshot(meta)";
        s = "oneshot(alt)";
        d = "oneshot(control)";
        f = "oneshot(shift)";

        leftalt = "layer(numbers)";
        rightalt = "layer(numbers)";
      };
      numbers = {
        "/" = "0";
        ";" = "0";
        "p" = "0";

        "m" = "1";
        "," = "2";
        "." = "3";
        "j" = "4";
        "k" = "5";
        "l" = "6";
        "u" = "7";
        "i" = "8";
        "o" = "9";
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
      hd-gold = {
        q = "j";
        w = "g";
        e = "m";
        r = "p";
        t = "v";
        y = ";";
        u = ".";
        i = "/";
        o = "!";
        p = "'";
        a = "r";
        s = "s";
        d = "n";
        f = "d";
        g = "b";
        h = ",";
        j = "a";
        k = "e";
        l = "i";
        ";" = "h";
        z = "f";
        x = "l";
        c = "c";
        v = "w";
        b = "x";
        n = "-";
        m = "u";
        "," = "o";
        "." = "y";
        "/" = "k";

        "[" = "z";
        "\'" = "q";
      };

      "hd-gold+shift" = {
        y = ":";
        u = "*";
        i = "\\";
        o = "?";
        p = "\"";
        h = "#";
        n = "_";
      };
      esc = {
        "1" = "toggle(colemak)";
        "2" = "toggle(hd-gold)";
      };
    };
  };

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

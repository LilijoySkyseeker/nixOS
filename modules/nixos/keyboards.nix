{ config, ... }: {
  flake.modules.nixos."keyboards" = { pkgs-unstable, ... }: {
    imports = [ config.flake.modules.nixos.wooting ];
    environment.systemPackages = [ pkgs-unstable.vial ];
    hardware.keyboard.qmk.enable = true;

    # kde: keyboard > keyboard > key bindings > function keys > "use
    # f13-f24 as usual function keys" -- system-wide xkb option, not
    # kde/kxkbrc-specific, so applies at login and on any tty too
    services.xserver.xkb.options = "terminate:ctrl_alt_bksp,fkeys:basic_13-24";
    services.udev.packages = [
      pkgs-unstable.vial
    ];
  };
}

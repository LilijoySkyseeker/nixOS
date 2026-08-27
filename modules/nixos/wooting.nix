{ ... }:
{
  flake.modules.nixos.wooting =
    { ... }:
    {
      # Wooting keyboard
      #
      # The `input` group membership that used to be re-added here is gone
      # (F-P1-01/F-P8-09). It was never needed: hardware.wooting.enable's
      # only access mechanism is services.udev.packages =
      # [ pkgs.wooting-udev-rules ], and every rule in that package is
      # `TAG+="uaccess"` on the hidraw/usb nodes -- which grants the
      # logged-in user access through a logind ACL, not through a group.
      # Checked against the pinned nixpkgs module and the rules package
      # itself rather than assumed.
      #
      # It also mattered more than a duplicate normally would: this module
      # merged with PC.nix's own list, so dropping `input` there alone
      # would have left the grant fully intact and looked like a fix.
      hardware.wooting.enable = true;
    };
}

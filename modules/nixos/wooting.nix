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
      #
      # Still owed one live check, since the above is source-reading and
      # not a keyboard: after the first switch, confirm the board types
      # and that wootility still detects it and can read/write profiles
      # (that path talks to hidraw directly). Tracked in
      # docs/audits/2026-08-26/user-actions.md. If it does break, the fix
      # is a uaccess-scoped grant -- not restoring `input`, which is read
      # of every evdev node on the machine.
      hardware.wooting.enable = true;
    };
}

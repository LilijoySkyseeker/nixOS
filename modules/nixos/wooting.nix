_: {
  flake.modules.nixos.wooting = _: {
    # wooting keyboard; access via wooting-udev-rules' uaccess (logind ACL)
    # don't add the `input` group if wootility breaks: it grants read of
    # every evdev node; use a uaccess-scoped grant instead
    hardware.wooting.enable = true;
  };
}

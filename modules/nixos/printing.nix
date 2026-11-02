_: {
  flake.modules.nixos."printing" = _: {
    services.printing.enable = true;

    # no avahi/mDNS: opens udp 5353 host-wide on a roaming laptop; the printer
    # has a static address, so don't re-add it for printing
  };
}

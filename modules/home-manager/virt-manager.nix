_: {
  flake.modules.homeManager."virt-manager" = _: {
    # desktop-only: needs a dconf/dbus session, so not in tooling.nix (headless homelab)
    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = [ "qemu:///system" ];
        uris = [ "qemu:///system" ];
      };
    };
  };
}

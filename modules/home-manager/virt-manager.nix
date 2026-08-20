{ ... }:
{
  flake.modules.homeManager."virt-manager" =
    { ... }:
    {
      # Virtual-machine (also needs nixos module: modules/nixos/virtual-machines.nix).
      # Desktop-only: requires a dconf/dbus session, so keep this out of tooling.nix
      # (which is also imported by root@homelab, a headless server).
      dconf.settings = {
        "org/virt-manager/virt-manager/connections" = {
          autoconnect = [ "qemu:///system" ];
          uris = [ "qemu:///system" ];
        };
      };
    };
}

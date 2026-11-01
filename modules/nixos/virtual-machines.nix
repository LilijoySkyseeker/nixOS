_: {
  flake.modules.nixos."virtual-machines" =
    { pkgs-unstable, ... }:
    {
      virtualisation.libvirtd.enable = true;
      programs.virt-manager.enable = true;
      users.users.lilijoy.extraGroups = [ "libvirtd" ];

      environment.systemPackages = with pkgs-unstable; [ gnome-boxes ];

      virtualisation.spiceUSBRedirection.enable = true;
    };
}

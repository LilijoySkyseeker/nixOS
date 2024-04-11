{config, pkgs, inputs, lib, ...}:
{

  # Virt-manager (also needs home manager config)
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  users.users.lilijoy.extraGroups = [ "libvirtd" ];

}


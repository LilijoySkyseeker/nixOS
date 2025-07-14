{
  pkgs-unstable,
  ...
}:
{
  # Virt-manager (also needs home manager config)
  # Adtional manual config required, read wiki
  # https://nixos.wiki/wiki/Virt-manager
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  users.users.lilijoy.extraGroups = [ "libvirtd" ];

  # gnome-boxes
  environment.systemPackages = with pkgs-unstable; [ gnome-boxes ];

  # usb passthrough
  virtualisation.spiceUSBRedirection.enable = true;
  security.polkit.enable = true;
}

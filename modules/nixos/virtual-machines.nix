_: {
  flake.modules.nixos."virtual-machines" = _: {
    # Virt-manager (also needs home manager config)
    # Adtional manual config required, read wiki
    # https://nixos.wiki/wiki/Virt-manager
    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;
    users.users.lilijoy.extraGroups = [ "libvirtd" ];

    # usb passthrough
    virtualisation.spiceUSBRedirection.enable = true;
  };
}

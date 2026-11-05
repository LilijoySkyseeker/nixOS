_: {
  flake.modules.nixos."mullvad" = _: {
    services.mullvad-vpn = {
      enable = true;
      gui.enable = true;
    };
  };
}

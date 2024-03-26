{ config, pkgs, inputs, ... }:
{

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "colemak_dh";
  };

}

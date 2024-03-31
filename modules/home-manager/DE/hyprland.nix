{ config, pkgs, ... }:
{

  # hyprland
  wayland.windowManager.hyprland.settings = {
    "$mod" = "SUPER";

    bind =
      [
      ]
  };

}

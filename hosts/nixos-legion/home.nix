{ config, pkgs, pkgs-unstable, ... }:

{
  imports = [
    ../../modules/home-manager/shared.nix
  ];

# GNOME config: Use 'dconf watch /'
  dconf.settings = {
    "org/gnome/shell" = {
      last-selected-power-profile = "performance";
    };

# Dash to Panel
    "org/gnome/shell/extensions/dash-to-panel" = {
#      panel-sizes = {"0":32,"1":32,"2":32};
#      panel-element-positions = {"0":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}],"1":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}],"2":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}]};
    };


# Tiling Assistant
    "org/gnome/shell/extensions/tiling-assistant" = {
      window-gap = 8;
      single-screen-gap = 8;
    };

# extensions
    "org/gnome/shell" = {
      enabled-extensions = [
      ];
    };
  };
  home.packages = with pkgs.gnomeExtensions; [
  ];

# Home Manager starting version, do not touch
  home.stateVersion = "23.11";
}

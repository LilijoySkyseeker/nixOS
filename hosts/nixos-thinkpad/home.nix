{ config, pkgs, ... }:

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
#      panel-element-positions = "{\"0\":[{\"element\":\"showAppsButton\",\"visible\":false,\"position\":\"stackedTL\"},{\"element\":\"activitiesButton\",\"visible\":false,\"position\":\"stackedTL\"},{\"element\":\"leftBox\",\"visible\":true,\"position\":\"stackedTL\"},{\"element\":\"taskbar\",\"visible\":true,\"position\":\"stackedTL\"},{\"element\":\"centerBox\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"rightBox\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"dateMenu\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"systemMenu\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"desktopButton\",\"visible\":true,\"position\":\"stackedBR\"}]}";
    };
    
    # Tiling Assistant
    "org/gnome/shell/extensions/tiling-assistant" = {
      window-gap = 8;
      single-screen-gap = 0;
      maximize-with-gap = true;
    };

    # Openweather
    "org/gnome/shell/extensions/openweatherrefined" = {
      actual-city = 1;
      locs = "[(uint32 0, 'Lexington, Virginia, United States', uint32 0, '37.7840208,-79.4428157')]";
    };

  };
  

  # Home Enviorment Packages
  home.packages = with pkgs; [

  ];

  # Home Manager starting version, do not touch
  home.stateVersion = "23.11";
}

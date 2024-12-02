{ pkgs, lib, ... }:
{
  # GNOME config: Use 'dconf watch /'
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = lib.mkDefault "prefer-dark";
      enable-hot-corners = false;
      show-battery-percentage = true;
      clock-format = "12h";
      clock-show-weekday = true;
      clock-show-seconds = true;
    };
    "org/gtk/settings/file-chooser" = {
      clock-format = "12h";
    };
    "org/gtk/gtk4/settings/file-chooser" = {
      show-hidden = true;
    };
    "org/gnome/desktop/peripherals/mouse" = {
      accel-profile = "flat";
    };

    "org/gnome/mutter" = {
      dynamic-workspaces = false;
      workspaces-only-on-primary = true;
      check-alive-timeout = "uint32 60000";
      experimental-features = [ "variable-refresh-rate" ];
    };
    "org/gnome/settings-daemon/plugins/power" = {
      idle-dim = false;
      sleep-inactive-battery-type = "nothing";
      sleep-inactive-ac-type = "nothing";
      #           power-button-action = "interactive";
    };
    "org/gnome/desktop/wm/preferences" = {
      num-workspaces = 6;
      focus-mode = "sloppy";
      auto-raise = false;
      button-layout = "appmenu:minimize,maximize,close";
    };

    # Clipboard Indicator
    "org/gnome/shell/extensions/clipboard-indicator" = {
      enable-keybindings = false;
      history-size = 100;
    };

    # Dash to Panel
    "org/gnome/shell/extensions/dash-to-panel" = {
      multi-monitors = false;
      animate-appicon-hover = true;
      show-favorites = false;
      group-apps = false;
      group-apps-use-fixed-width = false;
      isolate-workspaces = true;
      appicon-padding = 0;
      appicon-margin = 4;
      tray-padding = 4;
      icon-padding = 0;
    };

    # Openweather
    "org/gnome/shell/extensions/openweatherrefined" = {
      refresh-interval-current = 600;
      refresh-interval-forecast = 3600;
      loc-refresh-interval = 60;
      disable-forecast = false;
      use-system-icons = true;
      delay-ext-init = 15;
      unit = "fahrenheit";
      wind-speed-unit = "mph";
      pressure-unit = "atm";
      clock-format = "12h";
      simplify-degrees = true;
      weather-provider = "openweathermap";
      custom-keys = [ "34f3635c44f16c3c385e875bdbbfb445" ];
      position-in-panel = "right";
      position-index = 0;
      show-text-in-panel = true;
      show-comment-in-panel = true;
      show-sunsetrise-in-panel = true;
      sun-in-panel-first = false;
      menu-alignment = 82;
      translate-condition = true;
      decimal-places = 0;
      pressure-decimal-places = -2;
      speed-decimal-places = -1;
      location-text-lenght = 0;
      hi-contrast = "none";
      center-forecast = true;
      show-comment-in-forecast = true;
      days-forecast = 5;
      expand-forecast = true;
      my-loc-prov = "ipinfoio";
      geolocation-provider = "openstreetmaps";
    };

    # Tiling Assistant
    "org/gnome/shell/extensions/tiling-assistant" = {
      maximize-with-gap = true;
      enable-tiling-popup = false;
      enable-raise-tile-group = false;
      dynamic-keybinding-behavior = 2;
      active-window-hint = 1;
      monitor-switch-grace-period = true;
    };

    # ddterm
    "org/gnome/shell/extensions/ddterm" = {
      window-monitor = "current";
      show-animation-duration = 0.1;
      theme-variant = "dark";
    };

    # enabled extensions
    "org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = [
        "dash-to-panel@jderose9.github.com"
        "clipboard-indicator@tudmotu.com"
        "openweather-extension@penguin-teal.github.io"
        "tiling-assistant@leleat-on-github"
        "ddterm@amezin.github.com"
        "gsconnect@andyholmes.github.io"
        "batterytimepercentagecompact@sagrland.de"
        "battery-usage-wattmeter@halfmexicanhalfamazing.gmail.com"
        "smart-auto-move@khimaros.com"
      ];
    };
  };

  # Gnome extension packages
  home.packages = with pkgs.gnomeExtensions; [
    dash-to-panel
    clipboard-indicator
    tiling-assistant
    ddterm
    battery-time-percentage-compact
    battery-usage-wattmeter
    smart-auto-move
    openweather-refined
  ];
}

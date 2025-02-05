{ pkgs, pkgs-stable, ... }:
{

  # System installed pkgs
  environment.systemPackages =
    (with pkgs; [
    baobab # gnome disk usage utilty
    gnome-tweaks
    ])
    ++ (with pkgs-stable; [
    gnome-extension-manager
    ]);

  # Enable X11 and Gnome
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # GS connect
  # programs.kdeconnect.package = pkgs.gnomeExtensions.gsconnect;

  # Disable uneeded GNOME apps
  environment.gnome.excludePackages = with pkgs; [
    totem # video player
    geary # mail
    gnome-calculator
    gnome-shell-extensions
  ];

  # sops secretse
  sops.secrets = {
    open_weather_key = { };
  };

  # Theme KDE apps like gnome
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };
}

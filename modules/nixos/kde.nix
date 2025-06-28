{ pkgs-stable, pkgs-unstable, ... }:
{
  # KDE Plasma
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

  # System installed pkgs
  environment.systemPackages =
    (with pkgs-unstable; [
    ])
    ++ (with pkgs-stable; [
      kdePackages.filelight # kde disk usage
      xdg-desktop-portal 
kdePackages.xdg-desktop-portal-kde    
]);

  # kde partition manager
  programs.partition-manager.enable = true;
}

{ pkgs, ... }:
{

    # Packages
    home.packages = with pkgs; [
      rc2nix
    ];

  # Plasma Manager
  programs.plasma = {
    enable = true;
  };
}

{ pkgs, pkgs-unstable, ... }: {
  imports = [ ../../modules/nixos/nixvim.nix ];

  # System installed pkgs
  environment.systemPackages = (with pkgs; [
    # STABLE installed packages
    git
    neovim
  ]) ++ (with pkgs-unstable;
    [
      # UNSTABLE installed packages
    ]);

  # Configure home-manager
  home-manager = {
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
    useUserPackages = true;
    config = { home.stateVersion = "24.05"; };
  };

  # backup instead of fail
  environment.etcBackupExtension = ".bak";

  # Set your time zone
  time.timeZone = "America/New_York";

  # State Version for first install, don't touch
  system.stateVersion = "24.05";
}

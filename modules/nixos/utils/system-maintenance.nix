{config, pkgs, inputs, lib, ...}:
{

options = {
  system-maintenance.enable = lib.mkEnableOption "enables unattended upgrades, nix store optimization, and garbage collection";
};

config = lib.mkIf config.system-maintenance.enable {
    # unattended upgrades
    system.autoUpgrade = {
      enable = true;
      flake = inputs.self.outPath;
      flags = [
        "--recreate-lock-file"
        "-L" # print build logs
      ];
    };
    
    # store optimization
    nix.settings.auto-optimise-store = true;
   # nix.optimise = {
   #   automatic = true;
   #   dates = [ "03:45" ];
   # };

    # garbage collection
    nix.gc = {
      automatic = true;
      options = "--delete-older-than 30d";
    };
};
}

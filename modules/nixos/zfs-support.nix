{ config, lib, ... }:
let
  cfg = config.myZfsSupport;
in
{
  options.myZfsSupport = {
    enable = lib.mkEnableOption "zfs root support (autoScrub, trim, hostId)";

    hostId = lib.mkOption {
      type = lib.types.strMatching "^[0-9a-f]{8}$";
      description = "8 hex-digit networking.hostId zfs requires, unique per host.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.supportedFilesystems = [ "zfs" ];
    services.zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };
    networking.hostId = cfg.hostId;
    # zfs needs /nix mounted before the rest of the store is usable —
    # true regardless of whether myZfsImpermanence is also enabled.
    fileSystems."/nix".neededForBoot = true;
  };
}

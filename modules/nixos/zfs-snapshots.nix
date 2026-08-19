{ config, lib, ... }:
let
  cfg = config.myZfsSnapshots;
in
{
  options.myZfsSnapshots = {
    enable = lib.mkEnableOption "sanoid local zfs snapshots";

    workingDatasets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Datasets to snapshot with the working template (frequent, short local retention).";
    };

    workingTemplate = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {
        frequent_period = 1;
        frequently = 59;
        hourly = 24;
        daily = 1;
        weekly = 0;
        monthly = 0;
        yearly = 0;
        autosnap = "yes";
        autoprune = "yes";
      };
      description = "sanoid template_working settings; override per-host for different retention (e.g. homelab's syncoid-slack tuning).";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra services.sanoid.settings entries merged in as-is (e.g. homelab's zbackup/template_backup recursive target).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.sanoid = {
      enable = true;
      extraArgs = [ "--verbose" ];
      interval = "minutely";
      settings =
        (lib.genAttrs cfg.workingDatasets (_: {
          use_template = "working";
        }))
        // {
          template_working = cfg.workingTemplate;
        }
        // cfg.extraSettings;
    };
    systemd.services.sanoid.serviceConfig = {
      User = lib.mkForce "root";
    };
  };
}

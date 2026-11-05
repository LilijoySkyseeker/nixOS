{ inputs, ... }:
{
  flake.modules.nixos."hibernate-only" =
    {
      config,
      lib,
      vars,
      ...
    }:
    let
      cfg = config.myHibernateOnly;

      profile = {
        autoSuspend = {
          action = "hibernate";
          idleTimeout = 3600;
        };
        whenLaptopLidClosed = "hibernate";
        inhibitLidActionWhenExternalMonitorConnected = false;
        turnOffDisplay.idleTimeout = "never";
        dimDisplay.enable = false;
      };
    in
    {
      options.myHibernateOnly = {
        enable = lib.mkEnableOption "hibernate in place of sleep: lid closed, idle and critical battery all hibernate, sleep is unavailable, and nothing happens on idle before the hibernate";

        lockOnResume = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Lock the session when hibernating. Turn off where the disk's unlock at resume (TPM2 + PIN) already proves who is there.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = config.myHibernate.enable or false;
            message = "myHibernateOnly needs a working hibernation (myHibernate on a ZFS root)";
          }
        ];

        systemd.sleep.settings.Sleep = {
          AllowSuspend = false;
          AllowHybridSleep = false;
          AllowSuspendThenHibernate = false;
        };

        # logind acts only when no session holds the lid (the SDDM greeter)
        services.logind.settings.Login = {
          HandleLidSwitch = "hibernate";
          HandleLidSwitchExternalPower = "hibernate";
          HandleLidSwitchDocked = "hibernate";
          HandleSuspendKey = "hibernate";
        };

        # in a session, KDE's powerdevil handles lid, idle and battery
        home-manager.users.${vars.username} = {
          imports = [ inputs.plasma-manager.homeModules.plasma-manager ];
          programs.plasma = {
            enable = true;
            powerdevil = {
              AC = profile;
              battery = profile;
              lowBattery = profile;
              batteryLevels.criticalAction = "hibernate";
            };
            kscreenlocker = {
              autoLock = false;
              inherit (cfg) lockOnResume;
            };
          };
        };
      };
    };
}

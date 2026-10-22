{ config, ... }:
let
  deployRevisionScript = config.flake.deployRevisionScript;
in
{
  flake.modules.nixos."pull-deploy" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myPullDeploy;
    in
    {
      options.myPullDeploy = {
        enable = lib.mkEnableOption "deploy master's latest revision on a schedule";

        repoUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://github.com/LilijoySkyseeker/nixOS.git";
          description = "Git URL to mirror master from. Public, so no credentials.";
        };

        hostAttr = lib.mkOption {
          type = lib.types.str;
          description = "nixosConfigurations attribute name to build/switch (e.g. \"thinkpad\").";
        };

        dates = lib.mkOption {
          type = lib.types.str;
          default = "Thu 03:00";
          description = "systemd OnCalendar spec for the deploy job.";
        };

        scheduleEnable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether the `pull-deploy` **timer** is installed. False keeps
            the service defined and manually startable
            (`systemctl start pull-deploy`) while stopping it happening
            on a schedule.

            The timer is removed rather than merely un-wanted, so a
            `switch` actually stops a running timer instead of leaving it
            armed until the next reboot.
          '';
        };

        autoReboot = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to reboot automatically when this job's switch changes the running kernel/initrd.";
        };

        operation = lib.mkOption {
          type = lib.types.enum [
            "switch"
            "boot"
          ];
          default = "switch";
          description = "nixos-rebuild operation to run: \"switch\" activates immediately, \"boot\" only sets the default boot entry for next reboot.";
        };

        requireACPower = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Only run the deploy job while on AC power (e.g. for laptops).";
        };

        protectedUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Systemd units that, if active, cause this scheduled job to skip
            (and retry next cycle) rather than build/switch and risk
            restarting them mid-run.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.pull-deploy = {
          description = "Deploy master's latest revision";
          path = with pkgs; [
            git
            nixos-rebuild
            nix
            coreutils
            systemd
          ];
          script = ''
            set -euo pipefail
            ${deployRevisionScript}

            mirror="$STATE_DIRECTORY/mirror.git"
            # the profile, not /run/current-system: a `boot` deploy is
            # installed before it's running
            profile=/nix/var/nix/profiles/system

            record_success() {
              touch "$STATE_DIRECTORY/deployed"
              # the deployed nixpkgs' date, e.g. 26.05.20261020.cd4ea8d
              local d
              d=$(cut -d. -f3 "$profile/nixos-version")
              if [ ''${#d} -eq 8 ]; then
                touch -d "''${d:0:4}-''${d:4:2}-''${d:6:2}" "$STATE_DIRECTORY/nixpkgs-date"
              fi
            }

            mirror_fetch "$mirror" ${lib.escapeShellArg cfg.repoUrl}
            target=$(mirror_master "$mirror")
            running=$("$profile/sw/bin/nixos-version" --configuration-revision 2>/dev/null || true)

            case "$(revision_relation "$mirror" "$running" "$target")" in
              current)
                echo "Already at $target."
                record_success
                exit 0
                ;;
              manual)
                echo "This host runs ''${running:-an unknown revision}, which isn't on master's history: a manual deploy. Not replacing it; deploy master by hand to resume." >&2
                exit 1
                ;;
            esac

            check_protected_units_inactive "${lib.concatStringsSep " " cfg.protectedUnits}"

            nixos-rebuild ${cfg.operation} --flake "git+file://$mirror?rev=$target#${cfg.hostAttr}"
            record_success

            ${lib.optionalString (cfg.autoReboot && cfg.operation == "switch") ''
              if [ "$(readlink /run/booted-system/kernel)" != "$(readlink /run/current-system/kernel)" ]; then
                echo "Kernel/initrd changed, rebooting."
                systemctl reboot
              fi
            ''}
          '';
          unitConfig = lib.mkIf cfg.requireACPower {
            ConditionACPower = true;
          };
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            StateDirectory = "pull-deploy";
            # runs real activation (nixos-rebuild switch/boot), so no
            # filesystem/kernel sandboxing
            NoNewPrivileges = true;
          };
        };

        # staleness markers exist from activation, so health-alerts doesn't
        # page "missing" before the first run
        systemd.tmpfiles.rules = [
          "d /var/lib/pull-deploy 0755 root root -"
          "f /var/lib/pull-deploy/deployed 0644 root root -"
          "f /var/lib/pull-deploy/nixpkgs-date 0644 root root -"
        ];

        systemd.timers.pull-deploy = lib.mkIf cfg.scheduleEnable {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.dates;
            Persistent = true;
          };
        };
      };
    };
}

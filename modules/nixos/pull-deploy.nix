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

        hostAttr = lib.mkOption {
          type = lib.types.str;
          description = "nixosConfigurations attribute name to build/switch (e.g. \"thinkpad\").";
        };

        dates = lib.mkOption {
          type = lib.types.str;
          description = "systemd OnCalendar spec for the deploy job.";
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
          # the switch it runs may change this unit; restarting it then
          # would kill the run before its post-switch steps (as nixos-upgrade)
          restartIfChanged = false;
          unitConfig.X-StopOnRemoval = false;
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
            profile=/nix/var/nix/profiles/system
            # what this operation installs: the running system for a
            # switch, the next boot's profile for a boot
            deployed=${if cfg.operation == "switch" then "/run/current-system" else "$profile"}

            revision_of() {
              "$1/sw/bin/nixos-version" --configuration-revision 2>/dev/null || true
            }

            record_success() {
              touch "$STATE_DIRECTORY/deployed"
              # the deployed nixpkgs' date, e.g. 26.05.20261020.cd4ea8d
              local d
              d=$(cut -d. -f3 "$deployed/nixos-version")
              case "$d" in
                [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
                  touch -d "''${d:0:4}-''${d:4:2}-''${d:6:2}" "$STATE_DIRECTORY/nixpkgs-date"
                  ;;
                *) echo "No nixpkgs date in $(cat "$deployed/nixos-version"); nixpkgs-date not updated." >&2 ;;
              esac
            }

            mirror_fetch "$mirror" https://github.com/LilijoySkyseeker/nixOS.git
            target=$(mirror_master "$mirror")
            running=$(revision_of /run/current-system)
            installed=$(revision_of "$profile")

            case "$(deploy_decision "$mirror" "$running" "$installed" "$target")" in
              current)
                echo "Already at $target."
                record_success
                exit 0
                ;;
              manual)
                echo "This host runs ''${running:-an unknown revision} (profile: ''${installed:-unknown}), not on master's history: a manual deploy. Not replacing it; deploy master by hand to resume." >&2
                exit 1
                ;;
            esac

            check_protected_units_inactive "${lib.concatStringsSep " " cfg.protectedUnits}"

            kernel_before=$(readlink /run/current-system/kernel)
            nixos-rebuild ${cfg.operation} --flake "git+file://$mirror?rev=$target#${cfg.hostAttr}"
            record_success

            ${lib.optionalString (cfg.operation == "switch") ''
              # only a kernel this switch brought in, not one a manual
              # switch left unbooted
              kernel_after=$(readlink /run/current-system/kernel)
              if [ "$kernel_after" != "$kernel_before" ] && [ "$kernel_after" != "$(readlink /run/booted-system/kernel)" ]; then
                echo "Kernel changed, rebooting."
                systemctl reboot
              fi
            ''}
          '';
          unitConfig.ConditionACPower = lib.mkIf cfg.requireACPower true;
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

        systemd.timers.pull-deploy = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.dates;
            Persistent = true;
          };
        };
      };
    };
}

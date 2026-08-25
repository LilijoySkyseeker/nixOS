{ config, ... }:
let
  deployGuardsScript = config.flake.deployGuardsScript;
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
        enable = lib.mkEnableOption "pull master, build-test, and switch on a schedule";

        flakeDir = lib.mkOption {
          type = lib.types.str;
          description = "Path to the local flake checkout to pull and rebuild from.";
        };

        hostAttr = lib.mkOption {
          type = lib.types.str;
          description = "nixosConfigurations attribute name to build/switch (e.g. \"thinkpad\").";
        };

        dates = lib.mkOption {
          type = lib.types.str;
          default = "Thu 03:00";
          description = "systemd OnCalendar spec for the pull/build/switch job.";
        };

        autoReboot = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to reboot automatically when a switch changes the running kernel/initrd.";
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

        minSwitchInterval = lib.mkOption {
          type = lib.types.ints.positive;
          default = 7 * 24 * 60 * 60;
          description = ''
            Minimum seconds since /nix/var/nix/profiles/system's last
            activation before this scheduled job will build/switch. Manual
            switches count too (they update the same profile symlink), so a
            manual deploy this week defers next week's scheduled one.
          '';
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

        sshKeyPath = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            SSH identity file to use for this job's git fetch, when this
            service (which runs as root) has no SSH identity of its own --
            e.g. a PC host where root has no home-manager profile at all,
            unlike the flakeDir-owning user. Root can read the file
            regardless of its permissions. Leave null to use whatever
            identity root's own SSH client would otherwise resolve.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.pull-deploy = {
          description = "Pull latest master and switch if it builds";
          path = with pkgs; [
            git
            openssh
            nixos-rebuild
            nix
            coreutils
          ];
          script = ''
            set -euo pipefail
            cd ${cfg.flakeDir}
            ${lib.optionalString (
              cfg.sshKeyPath != null
            ) "export DEPLOY_GUARDS_IDENTITY_FILE=${lib.escapeShellArg cfg.sshKeyPath}"}

            ${deployGuardsScript}

            require_clean_master
            fetch_and_merge_master

            last_switch=$(stat -c %Y /nix/var/nix/profiles/system)
            check_min_switch_interval ${toString cfg.minSwitchInterval} "$last_switch"
            check_protected_units_inactive "${lib.concatStringsSep " " cfg.protectedUnits}"

            if nixos-rebuild build --flake .#${cfg.hostAttr}; then
              nixos-rebuild ${cfg.operation} --flake .#${cfg.hostAttr}
            else
              echo "Build failed, not switching." >&2
              exit 1
            fi
          '';
          unitConfig = lib.mkIf cfg.requireACPower {
            ConditionACPower = true;
          };
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            # this unit runs `nixos-rebuild switch`/`boot` itself — real
            # system activation — so it can't be filesystem/kernel-sandboxed
            # the way a plain build-only job can (see myAutoUpdate's
            # flake-update-test vs auto-switch for the same distinction).
            NoNewPrivileges = true;
            ExecStartPost = lib.optionals cfg.autoReboot [
              (pkgs.writeShellScript "reboot-if-kernel-changed" ''
                if [ "$(readlink /run/booted-system/kernel)" != "$(readlink /run/current-system/kernel)" ]; then
                  echo "Kernel/initrd changed, rebooting."
                  systemctl reboot
                fi
              '')
            ];
          };
        };

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

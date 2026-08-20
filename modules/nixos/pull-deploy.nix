{ ... }:
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
      };

      config = lib.mkIf cfg.enable {
        systemd.services.pull-deploy = {
          description = "Pull latest master and switch if it builds";
          path = with pkgs; [
            git
            nixos-rebuild
            nix
            coreutils
          ];
          script = ''
            set -euo pipefail
            cd ${cfg.flakeDir}

            if [ -n "$(git status --porcelain)" ]; then
              echo "Working tree dirty, skipping auto-deploy."
              exit 0
            fi

            branch=$(git rev-parse --abbrev-ref HEAD)
            if [ "$branch" != "master" ]; then
              echo "Not on master (on $branch), skipping auto-deploy."
              exit 0
            fi

            git fetch origin
            git merge --ff-only origin/master

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
            # flake-update-test vs nixos-upgrade for the same distinction).
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

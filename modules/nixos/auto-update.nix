{ config, ... }:
let
  deployGuardsScript = config.flake.deployGuardsScript;
in
{
  flake.modules.nixos."auto-update" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myAutoUpdate;
      flakeDir = "/etc/nixos";

      # Shared by the scheduled `auto-switch` (full guards, timer-driven) and
      # `auto-switch-now` (manual-trigger only, no timer) below. Both always
      # re-fetch and ff-only-merge origin/master before building — never
      # trust whatever happens to already be checked out at /etc/nixos —
      # unlike the stock system.autoUpgrade this used to be; that's what
      # fixed the 2026-08-21 incident where a stale/dirty local checkout
      # getting switched silently reverted a manual `--target-host` deploy
      # (see TODO.md). Only the scheduled one also applies the min-interval
      # and protected-unit guards: those exist to keep an *unattended* run
      # from disrupting work in progress, not to second-guess a human who
      # just explicitly asked for a deploy right now.
      mkSwitchService =
        { enforceScheduleGuards }:
        {
          description =
            "Fetch master, build-test, and switch if it builds"
            + lib.optionalString (!enforceScheduleGuards) " (manual trigger, skips schedule guards)";
          path = with pkgs; [
            git
            nixos-rebuild
            nix
            coreutils
          ];
          script = ''
            set -euo pipefail
            cd ${flakeDir}

            ${deployGuardsScript}

            require_clean_master
            fetch_and_merge_master

            ${lib.optionalString enforceScheduleGuards ''
              last_switch=$(stat -c %Y /nix/var/nix/profiles/system)
              check_min_switch_interval ${toString cfg.minSwitchInterval} "$last_switch"
              check_protected_units_inactive "${lib.concatStringsSep " " cfg.protectedUnits}"
            ''}

            if nixos-rebuild build --flake .#${cfg.hostAttr}; then
              nixos-rebuild switch --flake .#${cfg.hostAttr}
            else
              echo "Build failed, not switching." >&2
              exit 1
            fi
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            # This unit runs `nixos-rebuild switch` itself — real system
            # activation (bootloader, kernel modules, arbitrary unit
            # restarts) — so it can't be sandboxed the way flake-update-test
            # (build-only) can. NoNewPrivileges is the one flag safe to add
            # regardless (root already has every privilege it could gain).
            NoNewPrivileges = true;
            # Only reboot if the switch actually changed the running
            # kernel/initrd, instead of rebooting on every switch.
            ExecStartPost = [
              (pkgs.writeShellScript "reboot-if-kernel-changed" ''
                if [ "$(readlink /run/booted-system/kernel)" != "$(readlink /run/current-system/kernel)" ]; then
                  echo "Kernel/initrd changed, rebooting."
                  systemctl reboot
                fi
              '')
            ];
          };
        };
    in
    {
      options.myAutoUpdate = {
        enable = lib.mkEnableOption "automated flake.lock update, build test, and switch";

        hostAttr = lib.mkOption {
          type = lib.types.str;
          description = "nixosConfigurations attribute name to build/test/switch (e.g. \"homelab\").";
        };

        updateDates = lib.mkOption {
          type = lib.types.str;
          default = "Sun 02:00";
          description = "systemd OnCalendar spec for the update/build-test/merge job.";
        };

        switchDates = lib.mkOption {
          type = lib.types.str;
          default = "Sun 04:00";
          description = "systemd OnCalendar spec for the actual switch job. Should run after updateDates.";
        };

        minSwitchInterval = lib.mkOption {
          type = lib.types.ints.positive;
          default = 7 * 24 * 60 * 60;
          description = ''
            Minimum seconds since /nix/var/nix/profiles/system's last
            activation before the scheduled switch job will build/switch.
            Manual switches (e.g. `nixos-rebuild switch --target-host`) count
            too, since they update the same profile symlink, so a manual
            deploy this week defers next week's scheduled one.
          '';
        };

        protectedUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Systemd units that, if active, cause the scheduled switch job to
            skip (and retry next cycle) rather than build/switch and risk
            restarting them mid-run.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # 1. On a branch: bump flake.lock, build-test it, and only if the build
        #    succeeds merge it into master and push. Never touches master unless
        #    the new inputs actually evaluate and build.
        systemd.services.flake-update-test = {
          description = "Update flake inputs on a branch and merge to master if the build succeeds";
          path = with pkgs; [
            git
            nixos-rebuild
            nix
            coreutils
          ];
          script = ''
            set -euo pipefail
            cd ${flakeDir}

            git fetch origin
            git checkout master
            git reset --hard origin/master
            git branch -D auto-update 2>/dev/null || true
            git checkout -b auto-update

            nix flake update

            if git diff --quiet -- flake.lock; then
              echo "No input updates available."
              git checkout master
              git branch -D auto-update
              exit 0
            fi

            git commit -am "chore: automated flake.lock update"

            if nixos-rebuild build --flake .#${cfg.hostAttr}; then
              echo "Build succeeded, merging auto-update into master."
              git checkout master
              git merge --ff-only auto-update
              git push origin master
              git branch -D auto-update
            else
              echo "Build failed, pushing auto-update branch for manual review instead of merging." >&2
              git push origin auto-update --force
              git checkout master
              exit 1
            fi
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            # `nixos-rebuild build` here delegates the actual build to
            # nix-daemon, so this process itself never needs kernel/module
            # access — unlike auto-switch below, this one never runs
            # `switch`. ProtectHome is deliberately left off: git push
            # authenticates via whatever's in /root (ssh key/credential
            # helper), unverified from here, so restricting it risked
            # silently breaking the push step.
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ flakeDir ];
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
          };
        };

        systemd.timers.flake-update-test = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.updateDates;
            Persistent = true;
          };
        };

        # 2. The actual switch, scheduled — full guards (see mkSwitchService
        #    above), triggered by the timer below.
        systemd.services.auto-switch = mkSwitchService { enforceScheduleGuards = true; };

        # 2b. Same build/switch logic, manual-trigger only
        #    (`systemctl start --wait auto-switch-now.service`) — skips the
        #    min-interval/protected-unit guards, since those exist to
        #    protect an *unattended* run from disrupting work in progress,
        #    not to silently no-op when a human explicitly asks for a
        #    deploy right now. No timer.
        systemd.services.auto-switch-now = mkSwitchService { enforceScheduleGuards = false; };

        systemd.timers.auto-switch = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.switchDates;
            Persistent = true;
          };
        };
      };
    };
}

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
      # (see verify-android-smb-share-end-to-end-2026-08-18.md). Only the
      # scheduled one also applies the min-interval
      # and protected-unit guards: those exist to keep an *unattended* run
      # from disrupting work in progress, not to second-guess a human who
      # just explicitly asked for a deploy right now.
      # `name` is the unit name, used for the per-unit RuntimeDirectory that
      # carries the "did this run actually activate anything" flag below.
      # `chainOnDeploy` decides whether this unit runs cfg.onDeployUnits
      # afterwards — see the option's description for why that is gated on a
      # real activation rather than on the unit merely succeeding.
      mkSwitchService =
        {
          name,
          enforceScheduleGuards,
          chainOnDeploy,
        }:
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

            # systemd recreates RuntimeDirectory on every start, so this flag
            # cannot survive from a previous run; clear it anyway so the
            # meaning does not depend on that (and so a manual `bash -x` of
            # this script does the right thing).
            rm -f "$RUNTIME_DIRECTORY/switched"

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
              # Reached only by a run that actually activated a new system.
              # Every guard above exits 0 on a deliberate skip, so unit
              # success alone does not mean a deploy happened -- this flag is
              # the difference, and ExecStartPost below reads it.
              touch "$RUNTIME_DIRECTORY/switched"
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
            # Carries the "we actually activated something" flag written by
            # the script above. Per-unit (auto-switch vs auto-switch-now) so
            # the two can never read each other's flag, and recreated by
            # systemd on every start so it cannot go stale.
            RuntimeDirectory = name;
            # Only reboot if the switch actually changed the running
            # kernel/initrd, instead of rebooting on every switch.
            ExecStartPost = [
              (pkgs.writeShellScript "reboot-if-kernel-changed" ''
                if [ "$(readlink /run/booted-system/kernel)" != "$(readlink /run/current-system/kernel)" ]; then
                  echo "Kernel/initrd changed, rebooting."
                  systemctl reboot
                fi
              '')
            ]
            ++ lib.optional (chainOnDeploy && cfg.onDeployUnits != [ ]) (
              pkgs.writeShellScript "start-on-deploy" ''
                units="${lib.concatStringsSep " " cfg.onDeployUnits}"

                # The whole point of this script. Under the OnSuccess= this
                # replaces, systemd fired these units whenever auto-switch
                # merely *succeeded* -- and a guard skip is a success. Caught
                # live on homelab, 2026-08-25T13:18:15:
                #
                #   auto-switch-start: Last switch activated 23 seconds ago
                #     (minimum 604800), skipping this scheduled run.
                #   systemd: auto-switch.service: Deactivated successfully.
                #   systemd: auto-switch.service: Triggering OnSuccess= dependencies.
                #   systemd: Starting Build locally and push+activate vps ...
                #
                # i.e. the protected-unit/min-interval guards deferred the
                # switch and systemd immediately started the closure build
                # and push anyway -- exactly the load those guards exist to
                # avoid (F-P7-09, consequence 1).
                if [ ! -e "$RUNTIME_DIRECTORY/switched" ]; then
                  echo "No activation this run (guard skipped it); not starting: $units"
                  exit 0
                fi

                echo "Activation completed; starting: $units"
                # Deliberately not allowed to fail this unit. The reboot
                # check above runs first and may already have asked systemd
                # to shut down, in which case queueing a new job legitimately
                # fails -- and marking auto-switch failed for that would page
                # on a completely successful deploy.
                if ! systemctl start --no-block $units; then
                  echo "Could not start $units (shutting down after a kernel change?)" >&2
                fi
                exit 0
              ''
            );
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

        scheduleEnable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether the `flake-update-test` and `auto-switch` **timers**
            are installed. Setting this false keeps every service defined
            and manually startable (`systemctl start auto-switch-now`,
            or `auto-switch` itself) while stopping anything from
            happening on a schedule.

            This is a deliberate half-measure and exists to be
            temporary. It is not `enable = false` because that would
            also remove `auto-switch-now`, which is the manual
            "deploy this host now" path and has no timer to begin with.

            The timers are removed rather than merely un-wanted, so that
            a `switch` actually stops a running timer instead of leaving
            it armed until the next reboot.

            Fleet-wide this is currently **false** — see
            rebuild-the-update-build-deploy-pipeline-properly-2026-08-27.md. The
            profile-staleness check in `myHealthAlerts` is what makes
            that survivable: if the fleet stops deploying, it says so.
          '';
        };

        onDeployUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "push-deploy-vps.service" ];
          description = ''
            Units to start after the scheduled `auto-switch` has *actually
            activated a new system* — not merely after it succeeded.

            Use this instead of `systemd.services.auto-switch.onSuccess`.
            The distinction is the whole point: every guard in
            `deployGuardsScript` ends in `exit 0`, so a run deferred by the
            min-interval or protected-unit guard still terminates cleanly and
            still fires `OnSuccess=`. On homelab that meant a switch deferred
            to protect a multi-day restic run immediately kicked off a full
            closure build and push to vps regardless — the exact contention
            the guard exists to prevent (F-P7-09).

            Only `auto-switch` chains. `auto-switch-now` is a human asking
            for a deploy right now and can start the follow-on itself, so it
            deliberately does not.
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
            # openssh: git fetch/push here talk to the origin remote over SSH,
            # and without a transport on PATH the very first `git fetch` fails.
            # myPullDeploy and myPushDeploy both already include it; this unit
            # was the odd one out, which is one of the two reasons it has never
            # completed a run (zero automated flake.lock commits in 1371).
            openssh
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
            # /root as well as the flake dir: ProtectSystem = "strict" makes
            # the whole filesystem read-only apart from what is listed here,
            # and this unit needs to write /root/.cache/nix (nix's eval and
            # fetcher caches) plus git's own state under /root. That omission
            # is the second reason this unit has never completed a run --
            # ProtectHome was already left off for the same underlying need,
            # but strict ProtectSystem re-imposed the restriction anyway.
            ReadWritePaths = [
              flakeDir
              "/root"
            ];
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
          };
        };

        systemd.timers.flake-update-test = lib.mkIf cfg.scheduleEnable {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.updateDates;
            # Persistent=false (default) is deliberate: after a long outage
            # this and auto-switch's timer would otherwise both fire their
            # missed run immediately at boot, piling I/O/CPU load on top of
            # zrepl's own post-boot catch-up replication (see
            # homelab-backup-replication-stack-has-several-compo-2026-08-18.md). A
            # week's delay on picking up flake updates is a non-issue —
            # missing this window just means the next one runs on schedule.
            Persistent = false;
          };
        };

        # 2. The actual switch, scheduled — full guards (see mkSwitchService
        #    above), triggered by the timer below.
        systemd.services.auto-switch = mkSwitchService {
          name = "auto-switch";
          enforceScheduleGuards = true;
          chainOnDeploy = true;
        };

        # 2b. Same build/switch logic, manual-trigger only
        #    (`systemctl start --wait auto-switch-now.service`) — skips the
        #    min-interval/protected-unit guards, since those exist to
        #    protect an *unattended* run from disrupting work in progress,
        #    not to silently no-op when a human explicitly asks for a
        #    deploy right now. No timer.
        systemd.services.auto-switch-now = mkSwitchService {
          name = "auto-switch-now";
          enforceScheduleGuards = false;
          chainOnDeploy = false;
        };

        systemd.timers.auto-switch = lib.mkIf cfg.scheduleEnable {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.switchDates;
            # See flake-update-test's timer above for why Persistent is off.
            Persistent = false;
          };
        };
      };
    };
}

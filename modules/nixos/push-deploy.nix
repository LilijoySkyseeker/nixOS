{ config, ... }:
let
  deployGuardsScript = config.flake.deployGuardsScript;
in
{
  flake.modules.nixos."push-deploy" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myPushDeploy;
    in
    {
      options.myPushDeploy = {
        enable = lib.mkEnableOption "build locally and push+activate on a remote target host on a schedule";

        flakeDir = lib.mkOption {
          type = lib.types.str;
          description = "Path to the local flake checkout to build from (evaluation/build happens on THIS machine).";
        };

        hostAttr = lib.mkOption {
          type = lib.types.str;
          description = "nixosConfigurations attribute name to build/switch (e.g. \"vps\") — this is the remote target's own config, not this machine's.";
        };

        targetHost = lib.mkOption {
          type = lib.types.str;
          description = "SSH destination for the remote target, e.g. \"vps-deploy@vps\".";
        };

        identityFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to the SSH private key authenticating to targetHost (e.g. a sops secret path).";
        };

        elevate = lib.mkOption {
          type = lib.types.enum [
            "none"
            "sudo"
          ];
          default = "sudo";
          description = ''
            Whether to pass nixos-rebuild's --sudo flag for the target's remote
            activation steps. nixos-rebuild-ng only wraps remote commands in
            the literal `sudo` binary, which on the target is the run0 alias
            (security.run0.enableSudoAlias). Default "sudo" since the target
            user (vps-deploy) is unprivileged and needs it for both the
            profile-set and switch-to-configuration steps.
          '';
        };

        dates = lib.mkOption {
          type = lib.types.str;
          default = "Thu 03:15";
          description = "systemd OnCalendar spec for the push/switch job.";
        };

        scheduleEnable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether the periodic `push-deploy-<hostAttr>` **timer** is
            installed. False keeps the service defined and manually
            startable (`systemctl start push-deploy-vps`) — which is how
            the target gets deployed by hand — while stopping it
            happening on a schedule.

            The timer is removed rather than merely un-wanted, so a
            `switch` actually stops a running timer instead of leaving it
            armed until the next reboot.
          '';
        };

        minSwitchInterval = lib.mkOption {
          type = lib.types.ints.positive;
          default = 6 * 24 * 60 * 60;
          description = ''
            Minimum seconds since the target's /nix/var/nix/profiles/system
            was last activated (checked remotely over SSH) before this
            scheduled job will build/push, so a manual deploy this week
            defers next week's scheduled one.
          '';
        };

        operation = lib.mkOption {
          type = lib.types.enum [
            "switch"
            "boot"
          ];
          default = "switch";
          description = "nixos-rebuild operation to run on the target: \"switch\" activates immediately, \"boot\" only sets the default boot entry for next reboot.";
        };

        rebootIfKernelChanged = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "After switching, reboot the target if the switch changed its running kernel/initrd (checked and triggered remotely over SSH).";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services."push-deploy-${cfg.hostAttr}" = {
          description = "Build locally and push+activate ${cfg.hostAttr} on ${cfg.targetHost}";
          path = with pkgs; [
            git
            nixos-rebuild
            nix
            openssh
            coreutils
          ];
          script = ''
            set -euo pipefail
            cd ${cfg.flakeDir}

            ${deployGuardsScript}

            require_clean_master
            fetch_and_merge_master

            export NIX_SSHOPTS="-i ${cfg.identityFile} -o StrictHostKeyChecking=accept-new"

            last_switch=$(ssh $NIX_SSHOPTS ${cfg.targetHost} stat -c %Y /nix/var/nix/profiles/system)
            check_min_switch_interval ${toString cfg.minSwitchInterval} "$last_switch"

            nixos-rebuild ${cfg.operation} \
              --flake .#${cfg.hostAttr} \
              --target-host ${cfg.targetHost} \
              ${lib.optionalString (cfg.elevate == "sudo") "--sudo"}

            ${lib.optionalString cfg.rebootIfKernelChanged ''
              # reboot goes through the same sudo/run0 alias as the switch;
              # hosts/vps/configuration.nix's vps-deploy dispatcher matches
              # this exact string
              booted=$(ssh $NIX_SSHOPTS ${cfg.targetHost} readlink /run/booted-system/kernel)
              current=$(ssh $NIX_SSHOPTS ${cfg.targetHost} readlink /run/current-system/kernel)
              if [ "$booted" != "$current" ]; then
                echo "Kernel/initrd changed on ${cfg.targetHost}, rebooting."
                ssh $NIX_SSHOPTS ${cfg.targetHost} "sudo systemctl reboot"
              fi
            ''}
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            # sandbox VM-tested in tests/push-deploy-sandbox.nix. PrivateTmp:
            # nixos-rebuild-ng's ssh ControlMaster socket; /root/.cache: nix
            # eval scratch, created by tmpfiles below (ReadWritePaths won't)
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            PrivateTmp = true;
            ReadWritePaths = [
              cfg.flakeDir # fetch_and_merge_master writes here
              "/root/.ssh" # known_hosts (StrictHostKeyChecking=accept-new)
              "/root/.cache" # nix's own eval/build scratch
            ];
          };
        };

        # ReadWritePaths targets must exist before the unit's mount namespace
        # is set up
        systemd.tmpfiles.rules = [
          "d /root/.cache 0700 root root -"
          "d /root/.ssh 0700 root root -"
        ];

        systemd.timers."push-deploy-${cfg.hostAttr}" = lib.mkIf cfg.scheduleEnable {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.dates;
            Persistent = true;
          };
        };
      };
    };
}

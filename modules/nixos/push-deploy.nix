{ config, ... }:
let
  deployRevisionScript = config.flake.deployRevisionScript;
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
        enable = lib.mkEnableOption "build locally and push+activate this host's own revision on a remote target host on a schedule";

        repoUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://github.com/LilijoySkyseeker/nixOS.git";
          description = "Git URL to mirror master from. Public, so no credentials.";
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
          # a switch of this host mid-push would otherwise kill the push
          # before it records success or checks the target's kernel
          restartIfChanged = false;
          unitConfig.X-StopOnRemoval = false;
          path = with pkgs; [
            git
            nixos-rebuild
            nix
            openssh
            coreutils
          ];
          script = ''
            set -euo pipefail
            ${deployRevisionScript}

            mirror="$STATE_DIRECTORY/mirror.git"
            mirror_fetch "$mirror" ${lib.escapeShellArg cfg.repoUrl}

            # the target follows this host: it only gets a revision this
            # host has already switched to itself
            target=$(/run/current-system/sw/bin/nixos-version --configuration-revision 2>/dev/null || true)
            if ! is_revision "$target"; then
              echo "This host runs ''${target:-an unknown revision}, not a master revision; not pushing it to ${cfg.targetHost}." >&2
              exit 1
            fi

            export NIX_SSHOPTS="-i ${cfg.identityFile} -o StrictHostKeyChecking=accept-new"

            # hosts/vps/configuration.nix's vps-deploy dispatcher matches
            # these exact strings
            running=$(ssh $NIX_SSHOPTS ${cfg.targetHost} /run/current-system/sw/bin/nixos-version --configuration-revision 2>/dev/null || true)
            installed=$(ssh $NIX_SSHOPTS ${cfg.targetHost} /nix/var/nix/profiles/system/sw/bin/nixos-version --configuration-revision 2>/dev/null || true)

            case "$(deploy_decision "$mirror" "$running" "$installed" "$target")" in
              current)
                echo "${cfg.targetHost} is already at $target."
                touch "$STATE_DIRECTORY/deployed-${cfg.hostAttr}"
                exit 0
                ;;
              manual)
                echo "${cfg.targetHost} runs ''${running:-an unknown revision} (profile: ''${installed:-unknown}), not on master's history: a manual deploy. Not replacing it; deploy it by hand to resume." >&2
                exit 1
                ;;
            esac

            ${lib.optionalString cfg.rebootIfKernelChanged ''
              kernel_before=$(ssh $NIX_SSHOPTS ${cfg.targetHost} readlink /run/current-system/kernel)
            ''}
            nixos-rebuild ${cfg.operation} \
              --flake "git+file://$mirror?rev=$target#${cfg.hostAttr}" \
              --target-host ${cfg.targetHost} \
              ${lib.optionalString (cfg.elevate == "sudo") "--sudo"}
            touch "$STATE_DIRECTORY/deployed-${cfg.hostAttr}"

            ${lib.optionalString cfg.rebootIfKernelChanged ''
              # reboot goes through the same sudo/run0 alias as the switch;
              # hosts/vps/configuration.nix's vps-deploy dispatcher matches
              # this exact string
              # only a kernel this switch brought in, not one a manual
              # switch left unbooted
              booted=$(ssh $NIX_SSHOPTS ${cfg.targetHost} readlink /run/booted-system/kernel)
              kernel_after=$(ssh $NIX_SSHOPTS ${cfg.targetHost} readlink /run/current-system/kernel)
              if [ "$kernel_after" != "$kernel_before" ] && [ "$kernel_after" != "$booted" ]; then
                echo "Kernel changed on ${cfg.targetHost}, rebooting."
                ssh $NIX_SSHOPTS ${cfg.targetHost} "sudo systemctl reboot"
              fi
            ''}
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            StateDirectory = "push-deploy";
            # sandbox VM-tested in tests/push-deploy-sandbox.nix. PrivateTmp:
            # nixos-rebuild-ng's ssh ControlMaster socket; /root/.cache: nix
            # eval scratch, created by tmpfiles below (ReadWritePaths won't)
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            PrivateTmp = true;
            ReadWritePaths = [
              "/root/.ssh" # known_hosts (StrictHostKeyChecking=accept-new)
              "/root/.cache" # nix's own eval/build scratch
            ];
          };
        };

        # ReadWritePaths targets must exist before the unit's mount namespace
        # is set up; the staleness marker exists from activation, so
        # health-alerts doesn't page "missing" before the first run
        systemd.tmpfiles.rules = [
          "d /root/.cache 0700 root root -"
          "d /root/.ssh 0700 root root -"
          "d /var/lib/push-deploy 0755 root root -"
          "f /var/lib/push-deploy/deployed-${cfg.hostAttr} 0644 root root -"
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

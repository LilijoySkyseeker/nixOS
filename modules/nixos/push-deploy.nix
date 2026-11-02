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

        dates = lib.mkOption {
          type = lib.types.str;
          description = "systemd OnCalendar spec for the push/switch job.";
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
            mirror_fetch "$mirror" https://github.com/LilijoySkyseeker/nixOS.git

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

            kernel_before=$(ssh $NIX_SSHOPTS ${cfg.targetHost} readlink /run/current-system/kernel)
            nixos-rebuild switch \
              --flake "git+file://$mirror?rev=$target#${cfg.hostAttr}" \
              --target-host ${cfg.targetHost} \
              --sudo
            touch "$STATE_DIRECTORY/deployed-${cfg.hostAttr}"

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
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            StateDirectory = "push-deploy";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            PrivateTmp = true;
            ReadWritePaths = [
              "/root/.ssh" # known_hosts (StrictHostKeyChecking=accept-new)
              "/root/.cache" # nix's own eval/build scratch
            ];
          };
        };

        # ReadWritePaths targets must exist before the unit starts, or it
        # fails to set up its mount namespace; the staleness marker exists
        # from activation, so health-alerts doesn't page "missing" before
        # the first run
        systemd.tmpfiles.rules = [
          "d /root/.cache 0700 root root -"
          "d /root/.ssh 0700 root root -"
          "d /var/lib/push-deploy 0755 root root -"
          "f /var/lib/push-deploy/deployed-${cfg.hostAttr} 0644 root root -"
        ];

        systemd.timers."push-deploy-${cfg.hostAttr}" = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.dates;
            Persistent = true;
          };
        };
      };
    };
}

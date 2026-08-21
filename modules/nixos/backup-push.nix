{ ... }:
{
  flake.modules.nixos."backup-push" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myBackupPush;
      hostName = config.networking.hostName;
    in
    {
      options.myBackupPush = {
        enable = lib.mkEnableOption "push zfs snapshots to a remote backup target on a schedule (syncoid over SSH)";

        targetHost = lib.mkOption {
          type = lib.types.str;
          description = "SSH destination for the backup receiver, e.g. \"backup-recv@homelab\".";
        };

        identityFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to the SSH private key authenticating to targetHost (e.g. a sops secret path).";
        };

        datasets = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          example = {
            "zroot/local/home" = "zbackup/backup/torrent/home";
            "zroot/local/root" = "zbackup/backup/torrent/root";
          };
          description = "Map of local source dataset to remote target dataset on targetHost.";
        };

        interval = lib.mkOption {
          type = lib.types.str;
          default = "hourly";
          description = "systemd OnCalendar spec for the push job.";
        };

        reachabilityCheckHost = lib.mkOption {
          type = lib.types.str;
          default = builtins.elemAt (lib.splitString "@" cfg.targetHost) 1;
          defaultText = lib.literalExpression ''the host part of targetHost'';
          description = ''
            Tailscale hostname/IP to probe before each run. On a well-connected
            always-on host this is mostly redundant, but it matters for a
            machine that sleeps/roams (e.g. a laptop): without it, every run
            while offline would fail syncoid's SSH connection and show up as a
            failed systemd unit. The ExecCondition below treats "not reachable"
            as a clean no-op instead.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Dedicated, unprivileged, single-purpose account (per
        # feedback_dedicated_service_users) — zfs send/bookmark/hold/release
        # are delegated to it below via `zfs allow` instead of running this
        # as root. It never accepts an inbound ssh connection (its key is
        # only ever used outbound, as a client), so no authorized_keys/shell
        # hardening is needed on this side the way backup-recv needs on the
        # homelab receive side.
        users.users.backup-push = {
          isSystemUser = true;
          group = "backup-push";
        };
        users.groups.backup-push = { };

        # zfs allow is idempotent — safe to re-run every boot. No "destroy"
        # or "snapshot" permission: sanoid (root) owns the local snapshot
        # lifecycle entirely; this account only ever reads and sends.
        systemd.services."backup-push-${hostName}-zfs-allow" = {
          description = "Delegate zfs send permissions on backup-push source datasets to backup-push";
          wantedBy = [ "multi-user.target" ];
          before = [ "backup-push-${hostName}.service" ];
          path = [ pkgs.zfs ];
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          script = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (source: _: ''
              zfs allow backup-push send,bookmark,hold,release ${lib.escapeShellArg source}
            '') cfg.datasets
          );
        };

        systemd.services."backup-push-${hostName}" = {
          description = "Push zfs snapshots to ${cfg.targetHost}";
          after = [ "backup-push-${hostName}-zfs-allow.service" ];
          requires = [ "backup-push-${hostName}-zfs-allow.service" ];
          path = with pkgs; [
            sanoid # provides syncoid
            openssh
            iputils
          ];
          serviceConfig = {
            Type = "oneshot";
            User = "backup-push";
            NoNewPrivileges = true;
            # backup-push is a system user with no real $HOME — without a
            # writable, persistent place to keep known_hosts,
            # StrictHostKeyChecking=accept-new has nowhere to record the
            # accepted key and fails verification even on the very first
            # connection (confirmed live: "Host key verification failed").
            StateDirectory = "backup-push-${hostName}";
            # tailscale ping actually exercises the tunnel (not just ARP/ICMP
            # to a routed IP), so this also fails closed if tailscaled itself
            # is down (e.g. right after boot, before it's come up) — either
            # way ExecCondition failing just skips this run cleanly instead
            # of counting as a failed unit.
            ExecCondition = pkgs.writeShellScript "backup-push-${hostName}-reachable" ''
              set -uo pipefail
              exec ${pkgs.tailscale}/bin/tailscale ping -c 1 --timeout 5s ${lib.escapeShellArg cfg.reachabilityCheckHost}
            '';
          };
          script = ''
            set -euo pipefail
            export SYNCOID_SSHOPTION="-i ${cfg.identityFile} -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/var/lib/backup-push-${hostName}/known_hosts"

            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (source: target: ''
                syncoid \
                  --no-privilege-elevation \
                  --no-sync-snap \
                  --create-bookmark \
                  --sshkey=${cfg.identityFile} \
                  --identifier=${lib.escapeShellArg (builtins.replaceStrings [ "/" ] [ "_" ] source)} \
                  ${lib.escapeShellArg source} \
                  ${lib.escapeShellArg "${cfg.targetHost}:${target}"}
              '') cfg.datasets
            )}
          '';
        };

        systemd.timers."backup-push-${hostName}" = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.interval;
            Persistent = true;
          };
        };
      };
    };
}

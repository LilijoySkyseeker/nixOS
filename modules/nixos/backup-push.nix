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
    systemd.services."backup-push-${hostName}" = {
      description = "Push zfs snapshots to ${cfg.targetHost}";
      path = with pkgs; [
        sanoid # provides syncoid
        openssh
        iputils
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        NoNewPrivileges = true;
        # bookmarks + zfs send/receive both need root on the source side
        # (reading arbitrary datasets, managing snapshots/bookmarks) —
        # matches how sanoid's own service is pinned to root elsewhere in
        # this repo (see systemd.services.sanoid.serviceConfig.User).
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
        export SYNCOID_SSHOPTION="-i ${cfg.identityFile} -o StrictHostKeyChecking=accept-new"

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
}

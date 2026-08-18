{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myZfsSpaceGuard;
in
{
  options.myZfsSpaceGuard = {
    enable = lib.mkEnableOption "auto-prune oldest zfs snapshots when a dataset's pool runs low on free space, plus a manual emergency-prune escape hatch";

    datasets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [
        "zroot/local/home"
        "zroot/local/root"
      ];
      description = ''
        Datasets to watch and prune. Only their own zfs-list-t-snapshot
        history is touched — sanoid's autoprune elsewhere still owns
        normal retention; this only kicks in when free space actually
        gets tight, or when the manual emergency service is run.

        Safe to prune aggressively even below what a future incremental
        backup needs: if myBackupPush.datasets covers the same dataset
        with --create-bookmark enabled, the bookmark left behind after
        each successful push preserves the incremental base regardless
        of which snapshots get destroyed locally afterward. Pruning
        before any backup has ever succeeded loses that safety net and
        forces the next push to fall back to a full send.
      '';
    };

    pool = lib.mkOption {
      type = lib.types.str;
      example = "zroot";
      description = "Pool to check free space on (usually the pool datasets live under).";
    };

    freeThresholdPercent = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Auto-prune triggers when the pool's free space capacity drops below this percentage.";
    };

    keepMin = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Auto-prune never destroys the newest N snapshots per dataset, even under pressure — always leaves at least a minimal local rollback point.";
    };

    checkInterval = lib.mkOption {
      type = lib.types.str;
      default = "*:0/15";
      description = "systemd OnCalendar spec for how often to check free space.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.zfs-space-guard = {
      description = "Auto-prune oldest zfs snapshots when ${cfg.pool} is low on space";
      path = [ pkgs.zfs ];
      serviceConfig = {
        Type = "oneshot";
        User = "root"; # zfs destroy needs the same authority sanoid's own autoprune already runs with
      };
      script = ''
        set -uo pipefail
        cap=$(zpool list -Hpo capacity ${lib.escapeShellArg cfg.pool})
        if [ "$cap" -lt $(( 100 - ${toString cfg.freeThresholdPercent} )) ]; then
          exit 0
        fi
        echo "zfs-space-guard: ${cfg.pool} at $cap% capacity, over the ${toString cfg.freeThresholdPercent}% free threshold — pruning oldest snapshots"
        ${lib.concatMapStringsSep "\n" (dataset: ''
          snaps=$(zfs list -Hp -t snapshot -o name -s creation -r ${lib.escapeShellArg dataset} | grep '^${lib.escapeShellArg dataset}@')
          count=$(echo "$snaps" | grep -c . || true)
          drop=$(( count - ${toString cfg.keepMin} ))
          if [ "$drop" -gt 0 ]; then
            echo "$snaps" | head -n "$drop" | while read -r snap; do
              echo "zfs-space-guard: destroying $snap"
              zfs destroy "$snap" || true
            done
          fi
        '') cfg.datasets}
      '';
    };

    systemd.timers.zfs-space-guard = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.checkInterval;
        Persistent = true;
      };
    };

    # Manual escape hatch: `systemctl start zfs-emergency-prune.service`.
    # Ignores the freeThresholdPercent gate and keepMin floor entirely —
    # destroys every local snapshot except the single newest one on each
    # configured dataset, immediately. For a "game update needs 40GB
    # right now" situation, not routine use.
    systemd.services.zfs-emergency-prune = {
      description = "Immediately destroy all but the newest local snapshot on ${lib.concatStringsSep ", " cfg.datasets}";
      path = [ pkgs.zfs ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -uo pipefail
        ${lib.concatMapStringsSep "\n" (dataset: ''
          snaps=$(zfs list -Hp -t snapshot -o name -s creation -r ${lib.escapeShellArg dataset} | grep '^${lib.escapeShellArg dataset}@')
          echo "$snaps" | head -n -1 | while read -r snap; do
            echo "zfs-emergency-prune: destroying $snap"
            zfs destroy "$snap" || true
          done
        '') cfg.datasets}
      '';
    };
  };
}

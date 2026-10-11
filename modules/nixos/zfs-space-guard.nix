_: {
  flake.modules.nixos."zfs-space-guard" =
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
        enable = lib.mkEnableOption "a manual emergency-prune escape hatch: reclaim real disk space right now by destroying every local snapshot except the impermanence @blank rollback point";

        datasets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          example = [
            "zroot/local/home"
            "zroot/local/root"
          ];
          description = ''
            Datasets `zfs-emergency-prune.service` destroys snapshots on.
            Only their own zfs-list-t-snapshot history is touched — zrepl's
            keep rules still own normal retention; this only runs when you
            invoke it.

            Destroys every snapshot that could be holding a deleted file's
            blocks, immediately, on demand: ZFS only frees them once no
            snapshot references them, and the newest snapshot usually
            predates the delete.

            Safe to prune aggressively: zrepl's replication cursor
            preserves the incremental base regardless of which snapshots
            get destroyed locally afterward. Pruning before any replication
            has ever succeeded loses that safety net and forces a full
            send.

            Note this cannot free space held by zrepl's own holds. Under
            the default guarantee_resumability protection zrepl holds the
            snapshots an interrupted transfer would need to resume from, so
            `zfs destroy` on those fails (the script tolerates that and
            moves on). That is a small, bounded set — the replication
            cursor plus any in-flight step — so it does not meaningfully
            limit what this can reclaim, but it does mean a dataset with an
            actively-stalled replication keeps a floor of held snapshots.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # manual escape hatch: `systemctl start zfs-emergency-prune.service`.
        # keeps only `@blank` (impermanence rollback point); a dataset
        # without one loses every snapshot
        systemd.services.zfs-emergency-prune = {
          description = "Immediately destroy every local snapshot except @blank on ${lib.concatStringsSep ", " cfg.datasets}";
          path = [ pkgs.zfs ];
          serviceConfig = {
            Type = "oneshot";

            # docs/hardening.md sandboxing baseline; stays root (zfs destroy
            # isn't delegable). no PrivateDevices: needs /dev/zfs
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            PrivateTmp = true;
          };
          script = ''
            set -uo pipefail
            ${lib.concatMapStringsSep "\n" (dataset: ''
              snaps=$(zfs list -Hp -t snapshot -o name -s creation -r ${lib.escapeShellArg dataset} | grep '^${lib.escapeShellArg dataset}@' || true)
              if [ -n "$snaps" ]; then
                echo "$snaps" | grep -v '@blank$' | while read -r snap; do
                  echo "zfs-emergency-prune: destroying $snap"
                  zfs destroy "$snap" || true
                done
              fi
            '') cfg.datasets}
          '';
        };
      };
    };
}

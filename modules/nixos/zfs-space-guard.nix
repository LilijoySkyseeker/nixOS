{ ... }:
{
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

            An earlier version of this module also auto-pruned on a timer
            when free space got tight. Removed: capacity-threshold pruning
            trims the *oldest* snapshots down to a floor, but the actual
            problem it needs to solve — "I deleted a large file and want
            that space back right now" — isn't fixed by that. ZFS doesn't
            free a deleted file's blocks until every snapshot referencing
            them is gone, and whatever snapshot is newest at delete time
            was almost always taken *before* the delete (snapshots run on
            their own schedule), so a floor that keeps N newest snapshots
            routinely keeps exactly the one holding the space you wanted
            back. The only thing that reliably reclaims it is destroying
            every snapshot that could be holding it, immediately, on
            demand — which is what this does now.

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
        # Manual escape hatch: `systemctl start zfs-emergency-prune.service`.
        # Destroys every local snapshot except one named exactly `@blank` on
        # each configured dataset, immediately. `@blank` is the impermanence
        # rollback point disko creates once at install time (see
        # docs/backups.md and zrepl's own protectRegexes) -- every host is
        # expected to end up on impermanence, so that's the one snapshot
        # that must never go. On a dataset with no `@blank` (a host not yet
        # migrated), this destroys everything. For a "game update needs
        # 40GB right now" situation, not routine use.
        systemd.services.zfs-emergency-prune = {
          description = "Immediately destroy every local snapshot except @blank on ${lib.concatStringsSep ", " cfg.datasets}";
          path = [ pkgs.zfs ];
          serviceConfig.Type = "oneshot";
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

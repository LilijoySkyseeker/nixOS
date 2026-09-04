_: {
  flake.modules.nixos."backup-canary" =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.myBackupCanary;
    in
    {
      options.myBackupCanary = {
        relPath = lib.mkOption {
          type = lib.types.str;
          default = ".backup-canary/canary.txt";
          description = ''
            The path convention, relative to a dataset's own root, every
            canary in `paths` below must sit at (i.e. each `paths` key is
            some `<mountpoint>/''${relPath}`). Exposed as a real option,
            rather than left as a convention two modules have to agree on
            by comment, so modules/nixos/backup-restore-test.nix reads this
            same value instead of hardcoding its own copy.
          '';
        };

        paths = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            "/home/.backup-canary/canary.txt" = "backup-canary torrent zroot/local/home v1";
          };
          description = ''
            Absolute path -> fixed file content. Each path must sit inside a
            dataset that's actually backed up (zrepl and/or restic), so a
            restore-test elsewhere in the fleet can restore it and compare
            content, proving the whole snapshot -> replicate/upload ->
            restore chain without touching real data.

            Deliberately static rather than refreshed on a timer: content
            drifting is not what this catches (myHealthAlerts.backupStaleness
            already answers "is new data arriving" via snapshot age) -- this
            only needs to prove "can I still get correct bytes back out".

            Seeded via systemd.tmpfiles.rules (`f+`, re-asserted every boot)
            rather than a one-time write. That matters on an impermanence
            host: homelab's `/` and thinkpad's `/` and `/home` are rolled
            back to `@blank` on boot (docs/backups.md), so a plain write
            would vanish before ever being snapshotted. tmpfiles re-creates
            it after the rollback, before zrepl's next 5m snapshot.
          '';
        };
      };

      config = lib.mkIf (cfg.paths != { }) {
        systemd.tmpfiles.rules = lib.flatten (
          lib.mapAttrsToList (path: content: [
            "d ${builtins.dirOf path} 0755 root root -"
            "f+ ${path} 0644 root root - ${content}"
          ]) cfg.paths
        );
      };
    };
}

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

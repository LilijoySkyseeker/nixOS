_: {
  flake.modules.nixos."backup-restore-test" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myBackupRestoreTest;
      # The shared convention modules/nixos/backup-canary.nix seeds at --
      # read from there rather than duplicating it as a second hardcoded
      # copy the two modules have to agree on by comment.
      canaryRelPath = config.myBackupCanary.relPath;
      canaryBaseName = builtins.baseNameOf canaryRelPath;

      # Shared by both zbackup.targets and restic.targets -- both are just
      # "dataset name -> the content its canary must contain".
      canaryTargetType = lib.types.attrsOf (
        lib.types.submodule {
          options.expectedContent = lib.mkOption {
            type = lib.types.str;
            description = "Exact content the canary at <dataset>/${canaryRelPath} must contain, matching what modules/nixos/backup-canary.nix seeded on the source host.";
          };
        }
      );

      # Shared epilogue: touch a per-check success marker (picked up by
      # myHealthAlerts.staleMarkerFiles) iff every target in this run
      # passed, then propagate failure to systemd (picked up by the
      # existing failed-units check) either way.
      successEpilogue = markerName: ''
        if [ "$fail" -eq 0 ]; then
          touch "$STATE_DIRECTORY/${markerName}-last-success"
        fi
        exit "$fail"
      '';

      hardeningBase = {
        # Root stays root here (docs/hardening.md's zfs-space-guard/
        # health-alerts precedent): `zfs clone`/`mount`/`destroy` and
        # reading restic's root-owned password file are not delegable to a
        # service user. Deliberately no PrivateDevices -- the zbackup path
        # needs /dev/zfs.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        PrivateTmp = true;
        StateDirectory = "backup-restore-test";
      };
    in
    {
      options.myBackupRestoreTest = {
        zbackup = {
          enable = lib.mkEnableOption "daily canary-file restore-and-verify against zbackup (zrepl) targets";

          scratchDataset = lib.mkOption {
            type = lib.types.str;
            default = "zbackup/restore-test-scratch";
            description = "Ephemeral zfs clone destination, cloned and destroyed every run.";
          };

          interval = lib.mkOption {
            type = lib.types.str;
            default = "*-*-* 04:30:00";
            description = "systemd OnCalendar spec for the daily restore-test run.";
          };

          targets = lib.mkOption {
            type = canaryTargetType;
            default = { };
            example = {
              "zbackup/backup/torrent/zroot/local/home".expectedContent =
                "backup-canary torrent zroot/local/home v1";
            };
            description = "zbackup datasets to restore-test, keyed by full dataset name (as in myHealthAlerts.backupStaleness).";
          };
        };

        restic = {
          enable = lib.mkEnableOption "restic-restore canary-file verify, triggered after a successful backup run";

          wrapperCommand = lib.mkOption {
            type = lib.types.str;
            description = "Name of the restic wrapper (services.restic.backups.<name>.createWrapper) to invoke, e.g. \"restic-backblazeWeekly\".";
          };

          mountPrefix = lib.mkOption {
            type = lib.types.str;
            description = "The backupPrepareCommand RuntimeDirectory the backup job mounts snapshots under, e.g. \"/run/restic-backups-backblazeWeekly\" -- this is the path prefix restic actually archived, so it's what the restore include-pattern has to match.";
          };

          triggerUnit = lib.mkOption {
            type = lib.types.str;
            description = ''
              systemd unit to hook via OnSuccess= so this runs right after a
              successful backup -- not chained into that unit's own
              ExecStartPost, which would make a broken verify step look like
              a broken backup. Accepted with or without the trailing
              ".service" -- systemd.services.<name> already appends it, so
              it's stripped before use (see modules/nixos/iso-autobuild.nix's
              triggeredBy for the same normalization and the bug it fixes:
              passing the suffixed form silently creates a phantom
              "<name>.service.service" unit whose OnSuccess= never attaches).
            '';
          };

          targets = lib.mkOption {
            type = canaryTargetType;
            default = { };
            example = {
              "zdata/storage/storage".expectedContent = "backup-canary homelab zdata/storage/storage v1";
            };
            description = ''
              restic-backed-up datasets to restore-test, keyed by the dataset
              name exactly as backupPrepareCommand lists it (the mounted
              snapshot directory is named "<key>@<zrepl-timestamp>" under
              mountPrefix -- restic archived that whole path).
            '';
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.zbackup.enable {
          systemd.services.backup-restore-test-zbackup = {
            description = "Restore-and-verify canary files out of zbackup, proving the zrepl restore path actually works";
            path = with pkgs; [
              zfs
              util-linux
              coreutils
              gnugrep
            ];
            serviceConfig = hardeningBase // {
              Type = "oneshot";
              RuntimeDirectory = "backup-restore-test";
            };
            script = ''
              set -uo pipefail
              scratch=${lib.escapeShellArg cfg.zbackup.scratchDataset}
              mnt="$RUNTIME_DIRECTORY/mnt"
              mkdir -p "$mnt"
              fail=0

              # Self-heal any leftover mount/clone from a run that crashed
              # mid-way, rather than every subsequent run failing on "clone
              # already exists".
              mountpoint -q "$mnt" && umount "$mnt"
              zfs destroy "$scratch" >/dev/null 2>&1 || true

              # Alternate newest/oldest still-retained snapshot by day of
              # year, computed once for the whole run (%-j is GNU date's
              # no-leading-zero form, so no base-10-forcing needed on it) --
              # always testing the newest would hide a retention/prune
              # regression that only shows up at the tail of the grid.
              day=$(date +%-j)

              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (dataset: target: ''
                  echo "backup-restore-test: checking ${dataset}"
                  dataset=${lib.escapeShellArg dataset}
                  expected=${lib.escapeShellArg target.expectedContent}

                  if [ $(( day % 2 )) -eq 0 ]; then
                    snap=$(zfs list -Hp -t snapshot -o name -s creation "$dataset" 2>/dev/null | grep '@zrepl_' | tail -n1)
                  else
                    snap=$(zfs list -Hp -t snapshot -o name -s creation "$dataset" 2>/dev/null | grep '@zrepl_' | head -n1)
                  fi

                  if [ -z "$snap" ]; then
                    echo "backup-restore-test: no zrepl snapshot found for $dataset"
                    fail=1
                  # Force mountpoint/canmount on the clone rather than trust
                  # whatever the received dataset's properties happen to be
                  # -- cheap defense against a hostile mountpoint/canmount
                  # arriving in a compromised source's send stream (still
                  # F-P6-03's fix to make on the receive side itself; this
                  # is a second, independent layer, not a substitute for it).
                  elif ! zfs clone -o mountpoint=legacy -o canmount=on "$snap" "$scratch"; then
                    echo "backup-restore-test: zfs clone failed for $snap"
                    fail=1
                  else
                    if mount -t zfs "$scratch" "$mnt"; then
                      actual=$(cat "$mnt/${canaryRelPath}" 2>/dev/null || echo "MISSING")
                      umount "$mnt"
                      if [ "$actual" != "$expected" ]; then
                        echo "backup-restore-test: MISMATCH $dataset ($snap): expected [$expected] got [$actual]"
                        fail=1
                      fi
                    else
                      echo "backup-restore-test: mount failed for clone of $snap"
                      fail=1
                    fi
                    zfs destroy "$scratch" || true
                  fi
                '') cfg.zbackup.targets
              )}

              ${successEpilogue "zbackup"}
            '';
          };

          systemd.timers.backup-restore-test-zbackup = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = cfg.zbackup.interval;
              Persistent = true;
            };
          };
        })

        (lib.mkIf cfg.restic.enable {
          systemd.services.backup-restore-test-restic = {
            description = "Restore-and-verify canary files out of the offsite restic repo, proving the restic restore path actually works";
            path = with pkgs; [
              coreutils
              findutils
            ];
            serviceConfig = hardeningBase // {
              Type = "oneshot";
            };
            script = ''
              set -uo pipefail
              scratch=$(mktemp -d)
              trap 'rm -rf "$scratch"' EXIT
              fail=0

              # One restic invocation covering every target rather than one
              # per dataset -- each restic call separately authenticates to
              # B2 and loads/decrypts the repo index, a real cost worth
              # paying once, not N times, for an offsite-bound job. Each
              # target's file lands under its own dataset@snapshot path
              # inside $scratch, so a single `--path`-scoped find still
              # disambiguates them below.
              if ! ${cfg.restic.wrapperCommand} restore latest --target "$scratch" \
                ${
                  lib.concatMapStringsSep " " (
                    dataset: "--include " + lib.escapeShellArg "${cfg.restic.mountPrefix}/${dataset}@*/${canaryRelPath}"
                  ) (lib.attrNames cfg.restic.targets)
                } \
                >&2
              then
                echo "backup-restore-test: restic restore failed"
                fail=1
              else
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (dataset: target: ''
                    echo "backup-restore-test: checking ${dataset} (restic)"
                    expected=${lib.escapeShellArg target.expectedContent}
                    actual_file=$(find "$scratch" -type f -name ${lib.escapeShellArg canaryBaseName} -path ${lib.escapeShellArg "*/${dataset}@*"} | head -n1)
                    if [ -z "$actual_file" ]; then
                      echo "backup-restore-test: canary missing from restic restore of ${dataset}"
                      fail=1
                    else
                      actual=$(cat "$actual_file")
                      if [ "$actual" != "$expected" ]; then
                        echo "backup-restore-test: MISMATCH ${dataset} (restic): expected [$expected] got [$actual]"
                        fail=1
                      fi
                    fi
                  '') cfg.restic.targets
                )}
              fi

              ${successEpilogue "restic"}
            '';
          };

          # Hooked off the backup unit's own success, not chained into its
          # ExecStartPost -- see plan: 2026-09-04-automated-canary-based-backup-restore-and-verify-tier-1.md#G4.
          # This overrides a unit generated by services.restic.backups,
          # which is a normal NixOS module-merge, not a redefinition.
          # removeSuffix: systemd.services.<name> already appends ".service"
          # -- see triggerUnit's own option doc above and
          # modules/nixos/iso-autobuild.nix's triggeredBy for the bug this
          # avoids (a caller-supplied name that already ends in ".service"
          # would otherwise silently target a phantom, never-matching unit).
          systemd.services.${lib.removeSuffix ".service" cfg.restic.triggerUnit}.unitConfig.OnSuccess = [
            "backup-restore-test-restic.service"
          ];
        })
      ];
    };
}

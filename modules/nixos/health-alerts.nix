{ ... }:
{
  flake.modules.nixos."health-alerts" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myHealthAlerts;
    in
    {
      options.myHealthAlerts = {
        enable = lib.mkEnableOption "periodic ZFS/SMART/systemd health checks with Discord alerts";

        webhookUrlFile = lib.mkOption {
          type = lib.types.path;
          description = ''
            Path to a file (e.g. a sops secret) containing a curl config snippet
            of the form `url = "https://discord.com/api/webhooks/..."`, newline
            terminated. Kept out of argv/process-list by using curl's -K flag
            instead of passing the URL as a command-line argument.
          '';
        };

        interval = lib.mkOption {
          type = lib.types.str;
          default = "*:0/15";
          description = "systemd OnCalendar spec for how often to run the health check.";
        };

        cooldownHours = lib.mkOption {
          type = lib.types.int;
          default = 6;
          description = "Minimum hours between repeat alerts for the same still-ongoing problem.";
        };

        stuckSwitchThresholdMinutes = lib.mkOption {
          type = lib.types.int;
          default = 20;
          description = "How long a nixos-rebuild switch can run before it's considered stuck.";
        };

        checkZfs = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to check ZFS pool health. Disable on hosts with no ZFS pools (e.g. cloud VMs) — otherwise `zpool status -x` reporting \"no pools available\" gets treated as unhealthy on every run.";
        };

        checkSmart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to check SMART health on scannable drives. Disable on hosts with no real block devices to check (e.g. cloud VMs on virtio disks).";
        };

        backupStaleness = lib.mkOption {
          type = lib.types.attrsOf lib.types.int;
          default = { };
          example = {
            "zbackup/backup/homelab/zdata/storage/storage" = 6;
            "zbackup/backup/torrent/zroot/local/home" = 336;
          };
          description = ''
            ZFS datasets to check for backup staleness, mapped to the maximum
            age in hours their newest snapshot may reach before alerting. Catches
            a replication target that's stuck (e.g. failing every run without
            making progress) even though each individual failed run is already
            covered by the failed-units check — this instead measures whether the
            backup data itself is actually advancing.

            This matters more under zrepl than it did under syncoid: zrepl is a
            single long-running daemon, so an individual job erroring does not
            put a systemd unit into the "failed" state the way a per-job oneshot
            unit did. Snapshot age is the reliable signal that replication has
            stopped advancing.

            Note zrepl receives into <root_fs>/<full source dataset path>, so
            these are deep paths, not the short target names syncoid used.
          '';
        };

        staleMarkerFiles = lib.mkOption {
          type = lib.types.attrsOf lib.types.int;
          default = { };
          example = {
            "/var/lib/restic-backups-backblazeWeekly/last-success" = 192;
          };
          description = ''
            Paths whose mtime is checked for staleness, mapped to the maximum
            age in hours before alerting. The mtime has to be proof that
            something actually completed — for a service, have it touch the
            file only on success (e.g. via ExecStartPost, which only runs
            after a successful ExecStart).

            Two distinct jobs, both catching failures that never reach
            systemd's "failed" state:

            - **A run that silently never finishes** (hung, retrying forever)
              — e.g. the offsite restic backup, which has no local ZFS
              dataset to measure via `backupStaleness`.
            - **A run that never happens at all.** Every guard in
              `deployGuardsScript` ends in `exit 0`, so a deploy that skips
              (dirty tree, wrong branch, min-interval, protected unit) is
              recorded as success and never enters `systemctl --failed`.
              Pointing this at `/nix/var/nix/profiles/system` measures the
              outcome instead of the attempt: that symlink's mtime is the
              last time the host was *actually* activated, by any route —
              scheduled, push-deployed or manual. That is F-P7-09's
              skipped-deploy half.

            Note the check below uses a non-dereferencing `stat`, which
            matters for the profile symlink specifically: it points into the
            nix store, and store paths all have mtime 1 (1970), so a
            dereferencing `stat -L` here would report every host as
            permanently stale. Verified live on homelab.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # The per-alert cooldown/clear state is keyed on each marker's
        # *basename*, so two markers whose paths differ only in their
        # directory would silently share one alert slot: the second would
        # clear the first's stamp and one of the two failures would stop
        # being reported. That is invisible at runtime, so catch it at eval.
        # Not hypothetical — "last-success" is the obvious name for exactly
        # this kind of file, and this host already has one.
        assertions = [
          {
            assertion =
              let
                names = map baseNameOf (lib.attrNames cfg.staleMarkerFiles);
              in
              names == lib.unique names;
            message = ''
              myHealthAlerts.staleMarkerFiles has two entries with the same
              file name, which would collide in the alert-state key:
              ${lib.concatStringsSep ", " (lib.attrNames cfg.staleMarkerFiles)}
            '';
          }
        ];

        # ZFS pool health, SMART health, failed systemd units, and stuck nixos-rebuild switches
        systemd.services.health-check = {
          description = "Check ZFS/SMART/systemd health and post to Discord on new problems";
          path = with pkgs; [
            zfs
            smartmontools
            systemd
            coreutils
            gnugrep
            gawk
            curl
            jq
          ];
          script = ''
            set -uo pipefail
            state="$STATE_DIRECTORY"
            cooldown=$(( ${toString cfg.cooldownHours} * 3600 ))
            now=$(date +%s)

            notify() {
              key="$1"; title="$2"; body="$3"
              stamp="$state/$key"
              if [ -f "$stamp" ]; then
                last=$(cat "$stamp")
                if [ $(( now - last )) -lt "$cooldown" ]; then
                  return
                fi
              fi
              echo "$now" > "$stamp"
              payload=$(jq -n --arg content "**[${config.networking.hostName}] $title**\n\`\`\`\n$body\n\`\`\`" '{content: $content}')
              echo "$payload" | curl -sS -K ${cfg.webhookUrlFile} -H "Content-Type: application/json" --data-binary @- >/dev/null
            }

            clear_alert() {
              rm -f "$state/$1"
            }

            ${lib.optionalString cfg.checkZfs ''
              # ZFS pool health
              if ! zpool_out=$(zpool status -x 2>&1); then
                notify zfs-error "ZFS check failed" "$zpool_out"
              elif [ "$zpool_out" != "all pools are healthy" ]; then
                notify zfs-unhealthy "ZFS pool unhealthy" "$zpool_out"
              else
                clear_alert zfs-unhealthy
                clear_alert zfs-error
              fi
            ''}

            ${lib.optionalString cfg.checkSmart ''
              # SMART health on every scannable drive
              smart_failed=""
              for dev in $(smartctl --scan | awk '{print $1}'); do
                if ! smartctl -H "$dev" >/dev/null 2>&1; then
                  smart_failed="$smart_failed$dev\n"
                fi
              done
              if [ -n "$smart_failed" ]; then
                notify smart-failed "SMART health check failed" "$smart_failed"
              else
                clear_alert smart-failed
              fi
            ''}

            ${lib.optionalString (cfg.backupStaleness != { }) ''
              # backup snapshot staleness (catches a replication target stuck
              # making no progress, distinct from an individual run failing)
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (dataset: maxHours: ''
                  stale_key="backup-stale-$(${pkgs.coreutils}/bin/basename ${lib.escapeShellArg dataset} | tr -c 'a-zA-Z0-9_-' '-')"
                  # `|| true`: under `set -e -o pipefail`, `zfs list` on a
                  # dataset that doesn't exist yet at all (not just empty of
                  # snapshots — e.g. a push-backup target before its first
                  # ever sync) exits non-zero and would abort this whole
                  # script instead of falling through to the "$newest" empty
                  # check below, which already handles that case correctly.
                  newest=$(zfs list -t snapshot -H -p -o creation -s creation ${lib.escapeShellArg dataset} 2>/dev/null | tail -1) || true
                  if [ -z "$newest" ]; then
                    notify "$stale_key" "Backup staleness check failed" "${dataset}: no snapshots found (dataset missing or empty)"
                  else
                    age_hours=$(( (now - newest) / 3600 ))
                    if [ "$age_hours" -ge ${toString maxHours} ]; then
                      notify "$stale_key" "Backup is stale" "${dataset}: newest snapshot is $age_hours hours old (threshold: ${toString maxHours}h)"
                    else
                      clear_alert "$stale_key"
                    fi
                  fi
                '') cfg.backupStaleness
              )}
            ''}

            ${lib.optionalString (cfg.staleMarkerFiles != { }) ''
              # marker-file staleness: catches both a run that hangs/retries
              # forever and one that never happens at all (a skipped deploy),
              # neither of which ever reaches systemd's "failed" state.
              #
              # `stat` without -L is load-bearing here, not incidental: the
              # /nix/var/nix/profiles/system marker is a symlink into the
              # store, every store path has mtime 1, so dereferencing would
              # make every host permanently "stale". Keep it non-dereferencing.
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (path: maxHours: ''
                  stale_key="marker-stale-$(${pkgs.coreutils}/bin/basename ${lib.escapeShellArg path} | tr -c 'a-zA-Z0-9_-' '-')"
                  if [ ! -e ${lib.escapeShellArg path} ]; then
                    notify "$stale_key" "Marker file missing" "${path}: file does not exist"
                  else
                    mtime=$(stat -c %Y ${lib.escapeShellArg path})
                    age_hours=$(( (now - mtime) / 3600 ))
                    if [ "$age_hours" -ge ${toString maxHours} ]; then
                      notify "$stale_key" "Marker is stale" "${path}: last success was $age_hours hours ago (threshold: ${toString maxHours}h)"
                    else
                      clear_alert "$stale_key"
                    fi
                  fi
                '') cfg.staleMarkerFiles
              )}
            ''}

            # failed systemd units
            failed=$(systemctl --failed --no-legend --plain)
            if [ -n "$failed" ]; then
              notify failed-units "systemd units failed" "$failed"
            else
              clear_alert failed-units
            fi

            # stuck nixos-rebuild switch
            stuck=""
            for unit in $(systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | grep -E '^nixos-rebuild-switch-to-configuration'); do
              started=$(systemctl show "$unit" -p ActiveEnterTimestamp --value)
              if [ -n "$started" ] && [ "$started" != "n/a" ]; then
                started_epoch=$(date -d "$started" +%s 2>/dev/null || echo 0)
                if [ "$started_epoch" -gt 0 ]; then
                  elapsed_min=$(( (now - started_epoch) / 60 ))
                  if [ "$elapsed_min" -ge ${toString cfg.stuckSwitchThresholdMinutes} ]; then
                    stuck="$stuck$unit has been running for $elapsed_min minutes\n"
                  fi
                fi
              fi
            done
            if [ -n "$stuck" ]; then
              notify stuck-switch "nixos-rebuild switch stuck" "$stuck"
            else
              clear_alert stuck-switch
            fi
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "health-check";
            Group = "health-check";
            StateDirectory = "health-alerts";
            # smartctl needs both the "disk" group and CAP_SYS_RAWIO for its
            # SG_IO ioctls. Both are granted here, on the unit, rather than on
            # users.users.health-check -- a group on the *user* applies to
            # everything that user ever runs, whereas SupplementaryGroups is
            # scoped to this one invocation. That matters more than it looks:
            # /dev/sd* is root:disk 0660, i.e. read *and write* on every raw
            # block device, which is root-equivalent (and on homelab is a
            # direct read of the age key that decrypts the whole secrets
            # file). The previous comment here claimed "read access"; the
            # grant was never read-only.
            #
            # Both are also gated on checkSmart, since nothing else in this
            # unit touches a block device -- vps runs with checkSmart = false
            # and was carrying the capability and the group for no reason.
            SupplementaryGroups = lib.optionals cfg.checkSmart [ "disk" ];
            AmbientCapabilities = lib.optionals cfg.checkSmart [ "CAP_SYS_RAWIO" ];
            CapabilityBoundingSet = lib.optionals cfg.checkSmart [ "CAP_SYS_RAWIO" ];
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
        };

        systemd.timers.health-check = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.interval;
            Persistent = true;
          };
        };

        # dedicated non-root user. It deliberately holds no supplementary
        # groups: the "disk" membership smartctl needs is granted on the unit
        # instead (serviceConfig.SupplementaryGroups above), so it applies to
        # that one invocation rather than to anything running as this user.
        # zpool status/systemctl status queries are unprivileged on their own.
        users.users.health-check = {
          isSystemUser = true;
          group = "health-check";
        };
        users.groups.health-check = { };
      };
    };
}

_: {
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

            zrepl is a single long-running daemon, so an individual job erroring
            does not put a systemd unit into the "failed" state. Snapshot age is
            the reliable signal that replication has stopped advancing.

            Note zrepl receives into <root_fs>/<full source dataset path>, so
            these are deep paths.
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
            - **A run that never happens at all**, or keeps deferring: e.g.
              pull-deploy's `deployed` marker, touched only when the host
              ends a run at master's revision, while a protected-unit
              deferral exits 0 without touching it.

            The check below uses a non-dereferencing `stat`, so a marker
            that is a symlink into the store (mtime 1, 1970) reports the
            link's own mtime rather than every host being permanently stale.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
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
            cooldown=$(( 6 * 3600 ))
            now=$(date +%s)

            # a failed post leaves no stamp, so the next run retries it, and
            # fails the unit so the journal and `systemctl --failed` show it
            post_failed=0
            notify() {
              key="$1"; title="$2"; body="$3"
              stamp="$state/$key"
              if [ -f "$stamp" ]; then
                last=$(cat "$stamp")
                if [ $(( now - last )) -lt "$cooldown" ]; then
                  return
                fi
              fi
              payload=$(jq -n --arg content "**[${config.networking.hostName}] $title**\n\`\`\`\n$body\n\`\`\`" '{content: $content}')
              if echo "$payload" | curl -sS --fail --retry 2 --max-time 30 -K ${cfg.webhookUrlFile} -H "Content-Type: application/json" --data-binary @- >/dev/null; then
                echo "$now" > "$stamp"
              else
                echo "health-check: could not post alert '$title': $body" >&2
                post_failed=1
              fi
            }

            clear_alert() {
              rm -f "$state/$1"
            }

            ${lib.optionalString cfg.checkZfs ''
              if ! zpool_out=$(zpool status -x 2>&1); then
                notify zfs-error "ZFS check failed" "$zpool_out"
              elif [ "$zpool_out" != "all pools are healthy" ]; then
                notify zfs-unhealthy "ZFS pool unhealthy" "$zpool_out"
              else
                clear_alert zfs-unhealthy
                clear_alert zfs-error
              fi

              # process substitution, not a pipe: notify must run in this shell
              while read -r pool cap; do
                pool_key=$(printf '%s' "$pool" | tr -c 'a-zA-Z0-9_-' '-')
                if [ "$cap" -ge 90 ]; then
                  notify "pool-critical-$pool_key" "ZFS pool nearly full" "$pool is $cap% full (critical at 90%)"
                elif [ "$cap" -ge 80 ]; then
                  notify "pool-warn-$pool_key" "ZFS pool filling up" "$pool is $cap% full (warning at 80%)"
                  clear_alert "pool-critical-$pool_key"
                else
                  clear_alert "pool-warn-$pool_key"
                  clear_alert "pool-critical-$pool_key"
                fi
              done < <(zpool list -H -p -o name,capacity 2>/dev/null)
            ''}

            ${lib.optionalString cfg.checkSmart ''
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
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (dataset: maxHours: ''
                  # keyed on the full dataset name: torrent's and thinkpad's
                  # .../home share a basename
                  stale_key="backup-stale-$(printf '%s' ${lib.escapeShellArg dataset} | tr -c 'a-zA-Z0-9_-' '-')"
                  # `|| true`: zfs list fails on a not-yet-created dataset;
                  # the empty "$newest" check below handles that case
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

            failed=$(systemctl --failed --no-legend --plain)
            if [ -n "$failed" ]; then
              notify failed-units "systemd units failed" "$failed"
            else
              clear_alert failed-units
            fi

            stuck=""
            for unit in $(systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | grep -E '^nixos-rebuild-switch-to-configuration'); do
              started=$(systemctl show "$unit" -p ActiveEnterTimestamp --value)
              if [ -n "$started" ] && [ "$started" != "n/a" ]; then
                started_epoch=$(date -d "$started" +%s 2>/dev/null || echo 0)
                if [ "$started_epoch" -gt 0 ]; then
                  elapsed_min=$(( (now - started_epoch) / 60 ))
                  if [ "$elapsed_min" -ge 20 ]; then
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

            exit "$post_failed"
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "health-check";
            Group = "health-check";
            StateDirectory = "health-alerts";
            # smartctl's SG_IO needs "disk" + CAP_SYS_RAWIO. security: disk is
            # read-write on raw block devices (root-equivalent), so grant it on
            # the unit, not the user, and only when checkSmart
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
            OnCalendar = "*:0/15";
            Persistent = true;
          };
        };

        # dedicated non-root user; deliberately no supplementary groups
        # ("disk" is granted on the unit above)
        users.users.health-check = {
          isSystemUser = true;
          group = "health-check";
        };
        users.groups.health-check = { };
      };
    };
}

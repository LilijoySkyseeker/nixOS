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
            "zbackup/backup/homelab/storage" = 6;
            "zbackup/backup-bulk/homelab/storage-bulk" = 6;
          };
          description = ''
            ZFS datasets to check for backup staleness, mapped to the maximum
            age in hours their newest snapshot may reach before alerting. Catches
            a syncoid target that's stuck (e.g. failing every run without making
            progress) even though each individual failed run is already covered
            by the failed-units check — this instead measures whether the backup
            data itself is actually advancing.
          '';
        };

        staleMarkerFiles = lib.mkOption {
          type = lib.types.attrsOf lib.types.int;
          default = { };
          example = {
            "/var/lib/restic-backups-backblazeWeekly/last-success" = 192;
          };
          description = ''
            Files to check for staleness by mtime, mapped to the maximum age in
            hours before alerting. Intended for services (like an offsite restic
            backup) that have no local ZFS dataset to measure via
            `backupStaleness`: have the service touch the file only on success
            (e.g. via ExecStartPost, which only runs after a successful
            ExecStart), so its mtime is proof of the last completed run — this
            catches the run silently never finishing (hung, retrying forever)
            even when it never reaches a "failed" systemd state.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
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
              # backup snapshot staleness (catches a syncoid target stuck making
              # no progress, distinct from an individual run failing)
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
              # marker-file staleness (catches a service hanging/retrying
              # forever without ever reaching systemd's "failed" state)
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (path: maxHours: ''
                  stale_key="marker-stale-$(${pkgs.coreutils}/bin/basename ${lib.escapeShellArg path} | tr -c 'a-zA-Z0-9_-' '-')"
                  if [ ! -e ${lib.escapeShellArg path} ]; then
                    notify "$stale_key" "Marker file missing" "${path}: file does not exist"
                  else
                    mtime=$(stat -c %Y ${lib.escapeShellArg path})
                    age_hours=$(( (now - mtime) / 3600 ))
                    if [ "$age_hours" -ge ${toString maxHours} ]; then
                      notify "$stale_key" "Backup is stale" "${path}: last success was $age_hours hours ago (threshold: ${toString maxHours}h)"
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
            # smartctl's SG_IO ioctls require CAP_SYS_RAWIO even with rw access
            # to the block device via the "disk" group; grant only that, not root.
            AmbientCapabilities = [ "CAP_SYS_RAWIO" ];
            CapabilityBoundingSet = [ "CAP_SYS_RAWIO" ];
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

        # dedicated non-root user: "disk" group gives read access to the raw
        # block devices smartctl needs; zpool status/systemctl status queries
        # are unprivileged on their own.
        users.users.health-check = {
          isSystemUser = true;
          group = "health-check";
          extraGroups = [ "disk" ];
        };
        users.groups.health-check = { };
      };
    };
}

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
}

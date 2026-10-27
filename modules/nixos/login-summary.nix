{ config, ... }:
let
  inherit (config.flake) theme;
in
{
  # a server's state at an ssh login: failed units, pools, stale backups and
  # deploys (by health-alerts' own thresholds), and what a reboot wipes
  flake.modules.nixos."login-summary" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      host = config.networking.hostName;
      ansi =
        name:
        let
          h = lib.removePrefix "#" theme.palette.${name};
          byte = i: toString (lib.fromHexString (builtins.substring i 2 h));
        in
        "\\e[0;38;2;${byte 0};${byte 2};${byte 4}m";
      markers = config.myHealthAlerts.staleMarkerFiles or { };
      datasets = config.myHealthAlerts.backupStaleness or { };
      persistRoots = lib.attrNames (config.environment.persistence or { });
      checks = lib.length (lib.attrNames markers ++ lib.attrNames datasets);

      summary = pkgs.writeShellApplication {
        name = "login-summary";
        runtimeInputs =
          with pkgs;
          [
            coreutils
            gawk
            systemd
          ]
          ++ lib.optional config.boot.zfs.enabled config.boot.zfs.package;
        text = ''
          dim=$'${ansi "bright-black"}' red=$'${ansi "red"}' green=$'${ansi "green"}' reset=$'\e[0m'
          row() { printf '  %s%-8s%s %s\n' "$dim" "$1" "$reset" "$2"; }
          # seconds as the largest whole unit
          ago() {
            local s=$1
            if ((s < 3600)); then echo "$((s / 60)) min"
            elif ((s < 172800)); then echo "$((s / 3600)) h"
            else echo "$((s / 86400)) days"; fi
          }

          # the installed generation and when it was built (no profile in a VM test)
          gen=
          if link=$(readlink /nix/var/nix/profiles/system 2>/dev/null); then
            n=''${link#system-}
            gen=" · generation ''${n%-link}, built $(date -d "@$(stat -c %Y "/nix/var/nix/profiles/$link")" +%F)"
          fi
          printf '${ansi (theme.hostColours.${host} or "yellow")}\e[1m%s%s %sNixOS %s · %s%s%s\n' \
            ${host} "$reset" "$dim" ${config.system.nixos.release} "$(${pkgs.procps}/bin/uptime -p)" "$gen" "$reset"

          mapfile -t failed < <(systemctl --failed --no-legend --plain | awk '{print $1}')
          if ((''${#failed[@]})); then
            list=$(printf '%s, ' "''${failed[@]}")
            row units "''${red}✘ ''${#failed[@]} failed:''${reset} ''${list%, }"
          else
            row units "''${green}✔''${reset} none failed"
          fi

          ${lib.optionalString config.boot.zfs.enabled ''
            row zfs "$(zpool list -H -o name,health,capacity | awk -v red="$red" -v reset="$reset" '
              { h = ($2 == "ONLINE") ? $2 : red $2 reset
                printf "%s%s %s %s", (NR > 1 ? " · " : ""), $1, h, $3 }')"
          ''}

          ${lib.optionalString (checks > 0) ''
            # backup and deploy markers, the same thresholds health-alerts alerts on
            now=$(date +%s)
            stale=()
            check() { # name age_seconds max_hours
              if [[ -z $2 ]]; then stale+=("$1 (missing)")
              elif (($2 >= $3 * 3600)); then stale+=("$1 ($(ago "$2") old, limit $(ago $(($3 * 3600))))"); fi
            }
            ${lib.concatStrings (
              lib.mapAttrsToList (path: hours: ''
                m=$(stat -c %Y -- ${lib.escapeShellArg path} 2>/dev/null) || m=
                check ${lib.escapeShellArg (lib.removePrefix "/var/lib/" path)} "''${m:+$((now - m))}" ${toString hours}
              '') markers
            )}
            ${lib.concatStrings (
              lib.mapAttrsToList (dataset: hours: ''
                m=$(zfs list -t snapshot -d 1 -H -p -o creation -s creation ${lib.escapeShellArg dataset} 2>/dev/null | tail -1) || m=
                check ${lib.escapeShellArg dataset} "''${m:+$((now - m))}" ${toString hours}
              '') datasets
            )}
            if ((''${#stale[@]})); then
              row backups "''${red}✘ ''${#stale[@]} of ${toString checks} stale:''${reset}"
              printf '           %s\n' "''${stale[@]}"
            else
              row backups "''${green}✔''${reset} all ${toString checks} backup and deploy markers fresh"
            fi
          ''}

          ${lib.optionalString (persistRoots != [ ]) ''
            row wiped "at boot, everything not persisted to ${lib.concatStringsSep ", " persistRoots} (the prompt marks it)"
          ''}
        '';
      };
    in
    {
      environment.systemPackages = [ summary ];
      # an interactive ssh login; not the forced commands deploys and zrepl run
      programs.bash.loginShellInit = ''
        if [[ $- == *i* && -n ''${SSH_TTY-} ]]; then
          login-summary
        fi
      '';
    };
}

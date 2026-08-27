{ ... }:
{
  # Claude Code's own config lives in ~/.claude. The CLI writes settings.json
  # itself (that's how /model and /effort persist), so a store symlink over it
  # would make those writes fail. Instead the keys this repo cares about are
  # declared below and merged into the mutable file on activation: declarative
  # keys win on every rebuild, CLI-owned keys survive untouched.
  #
  # The claude-code package itself comes from profile-pc's systemPackages.
  flake.modules.homeManager.claude-code =
    {
      config,
      lib,
      pkgs-unstable,
      ...
    }:
    let
      # statusLine is invoked as a bare command, inheriting whatever PATH the
      # terminal happens to have - jq otherwise only exists in this repo's
      # devshell, so the bar silently emptied out anywhere else. Packaging the
      # script pins its own deps instead.
      #
      # bashOptions is emptied deliberately: the script uses `cond && printf`
      # idioms for optional segments, whose non-zero exits would trip errexit.
      statusline = pkgs-unstable.writeShellApplication {
        name = "claude-statusline";
        runtimeInputs = with pkgs-unstable; [
          jq
          git
          coreutils
        ];
        bashOptions = [ ];
        # Tide-style statusLine, segments separated by plain spaces:
        # cwd (blue) -> git branch (green/yellow) -> model+effort (magenta)
        # -> context -> 5h usage -> 7d usage (green/yellow/red) -> time (grey)
        #
        # `${...}` bash expansions below are escaped as `''${...}` throughout
        # so Nix doesn't try to interpolate them itself.
        text = ''
          input=$(cat)

          cwd=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
          model=$(jq -r '.model.display_name // empty' <<<"$input")
          effort=$(jq -r '.effort.level // empty' <<<"$input")
          ctx_pct=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
          five_pct=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
          five_reset=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")
          week_pct=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")
          week_reset=$(jq -r '.rate_limits.seven_day.resets_at // empty' <<<"$input")

          short_dir="~"
          [ -n "$cwd" ] && short_dir="''${cwd/#"$HOME"/\~}"

          # Shared green/yellow/red scale: under half is fine, 50%+ warns, 80%+ is urgent.
          usage_bg() {
            if [ "$1" -ge 80 ]; then
              echo "204;0;0"       # red: nearly exhausted
            elif [ "$1" -ge 50 ]; then
              echo "196;160;0"     # yellow: over halfway
            else
              echo "78;154;6"      # green: plenty of room
            fi
          }

          # When the window frees up. "date" style spells out the calendar day for the
          # 7d window, which lands days out; "clock" keeps the 5h window narrow, only
          # naming a weekday when the reset spills past midnight.
          reset_time() {
            local ts=$1 style=$2
            [ "$ts" -le "$(date +%s)" ] && { echo "now"; return; }
            if [ "$style" = "date" ]; then
              date -d "@$ts" "+%b %-d %H:%M"
            elif [ "$(date -d "@$ts" +%F)" = "$(date +%F)" ]; then
              date -d "@$ts" +%H:%M
            else
              date -d "@$ts" "+%a %H:%M"
            fi
          }

          # Rate-limit windows only appear once the API has reported them, and the
          # percentages arrive as floats - round before comparing or printing.
          rate_segment() {
            local label=$1 pct=$2 reset=$3 style=$4
            [ -n "$pct" ] || return
            local n; n=$(printf '%.0f' "$pct")
            local text="''${label} ''${n}%"
            # Only spend the extra width on a reset time once the window is nearly spent.
            [ "$n" -ge 80 ] && [ -n "$reset" ] && text="''${text} ($(reset_time "$reset" "$style"))"
            printf "\033[48;2;%sm\033[38;2;0;0;0m  %s \033[0m" "$(usage_bg "$n")" "$text"
          }

          segments=()

          segments+=("$(printf "\033[48;2;52;101;164m\033[38;2;228;228;228m  %s \033[0m" "$short_dir")")

          if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
            if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then
              git_bg="196;160;0"   # dirty: yellow, matches tide
              dirty=" *"
            else
              git_bg="78;154;6"    # clean: green
              dirty=""
            fi
            segments+=("$(printf "\033[48;2;%sm\033[38;2;0;0;0m  %s%s \033[0m" "$git_bg" "$branch" "$dirty")")
          fi

          if [ -n "$model" ]; then
            model_text="$model"
            [ -n "$effort" ] && model_text="''${model_text} (''${effort})"
            segments+=("$(printf "\033[48;2;135;95;175m\033[38;2;228;228;228m  %s \033[0m" "$model_text")")
          fi

          if [ -n "$ctx_pct" ]; then
            ctx_n=$(printf '%.0f' "$ctx_pct")
            segments+=("$(printf "\033[48;2;%sm\033[38;2;0;0;0m  ctx %s%% \033[0m" "$(usage_bg "$ctx_n")" "$ctx_n")")
          fi

          five_segment=$(rate_segment "5h" "$five_pct" "$five_reset" clock)
          [ -n "$five_segment" ] && segments+=("$five_segment")

          week_segment=$(rate_segment "7d" "$week_pct" "$week_reset" date)
          [ -n "$week_segment" ] && segments+=("$week_segment")

          segments+=("$(printf "\033[48;2;68;68;68m\033[38;2;228;228;228m  %s \033[0m" "$(date +%H:%M)")")

          (IFS=' '; printf '%s\n' "''${segments[*]}")
        '';
      };

      # The tcr skill is a plain file tree, but its scripts run from whatever
      # PATH the invoking terminal has (same problem as statusline), so each
      # entry point is wrapped with its own deps. lib.sh is deliberately left
      # unwrapped: the scripts `source` it, and a wrapper is an exec shim that
      # cannot be sourced.
      tcrSkill =
        pkgs-unstable.runCommandLocal "claude-tcr-skill"
          {
            nativeBuildInputs = [ pkgs-unstable.makeWrapper ];
          }
          ''
            cp -r ${./tcr-skill} $out
            chmod -R u+w $out
            for script in $out/scripts/tcr-*; do
              wrapProgram "$script" --prefix PATH : ${
                lib.makeBinPath (
                  with pkgs-unstable;
                  [
                    bash
                    coreutils
                    git
                    jq
                    gnused
                    gnugrep
                    gawk
                  ]
                )
              }
            done
          '';

      claudeDir = "${config.home.homeDirectory}/.claude";

      # Keys this repo owns in ~/.claude/settings.json. Anything absent here
      # (model, effortLevel, theme, enabledPlugins, ...) stays CLI-owned.
      managedSettings = {
        statusLine = {
          type = "command";
          command = "${claudeDir}/statusline.sh";
          padding = 0;
        };
        # The tips shown next to the spinner.
        spinnerTipsEnabled = false;
        hooks.PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${claudeDir}/skills/tcr/scripts/tcr-guard-hook";
                timeout = 10;
              }
            ];
          }
        ];
      };

      jsonFormat = pkgs-unstable.formats.json { };
      managedSettingsFile = jsonFormat.generate "claude-settings-managed.json" managedSettings;
      # Recorded so that dropping a key from managedSettings actually removes it
      # from settings.json on the next activation, instead of stranding it there.
      managedKeysFile = jsonFormat.generate "claude-settings-managed-keys.json" (
        lib.attrNames managedSettings
      );
    in
    {
      home = {
        file.".claude/statusline.sh".source = "${statusline}/bin/claude-statusline";
        file.".claude/skills/tcr".source = tcrSkill;

        # Reads happen unconditionally, but every write goes through `run` so
        # that `home-manager build`/dry-run stays side-effect free - a bare
        # `run echo > file` would still truncate the file via the redirect.
        activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          settings="${claudeDir}/settings.json"
          keyrecord="${claudeDir}/.hm-managed-setting-keys.json"

          current='{}'
          [ -e "$settings" ] && current=$(cat "$settings")
          prevKeys='[]'
          [ -e "$keyrecord" ] && prevKeys=$(cat "$keyrecord")

          # Deep-merge (jq `*`) so unmanaged keys survive, with the declared
          # side winning. Keys we managed on a previous generation but no
          # longer declare are dropped, so deleting one here removes it.
          merged=$(${pkgs-unstable.jq}/bin/jq -n \
            --argjson current "$current" \
            --argjson prevKeys "$prevKeys" \
            --slurpfile managed ${managedSettingsFile} \
            --slurpfile curKeys ${managedKeysFile} \
            '($current | delpaths([ ($prevKeys - $curKeys[0])[] | [.] ])) * $managed[0]')

          merged_tmp=$(mktemp)
          printf '%s\n' "$merged" > "$merged_tmp"

          run mkdir -p ${claudeDir}
          run install -m 644 "$merged_tmp" "$settings"
          run install -m 644 ${managedKeysFile} "$keyrecord"
          rm -f "$merged_tmp"
        '';
      };
    };
}

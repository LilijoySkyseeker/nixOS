{ config, ... }:
let
  inherit (config.flake) theme;
in
{
  flake.modules.homeManager.tooling =
    {
      pkgs,
      pkgs-stable,
      pkgs-unstable,
      config,
      lib,
      options,
      osConfig,
      ...
    }:
    let
      shellAliases = {
        e = "eza --group-directories-first --header --git --git-ignore --icons --all --long --mounts";
        et = "eza --tree --group-directories-first --header --git --git-ignore --icons --all --long --mounts";
        etl = "eza --tree --group-directories-first --header --git --git-ignore --icons --all --long --mounts --level";
      };
      # nerd font glyphs for the prompt, by codepoint
      g = lib.mapAttrs (_: cp: builtins.fromJSON ''"\u${cp}"'') {
        right = "e0b0"; # powerline arrow pointing right
        left = "e0b2"; # powerline arrow pointing left
        nixos = "f313";
        branch = "f418";
        lock = "f023";
        gear = "f013";
        thin-left = "e0b3";
        recycle = "f1b8";
      };
      host = osConfig.networking.hostName;
      hostColour = theme.hostColours.${host} or "yellow";
      isRoot = config.home.username == "root";
      # root's directory wiped at boot (impermanence): marked in the prompt
      wipedRoot = osConfig.environment.persistence or { } != { };
      # bash prompt escape for a palette colour, for the lines ble.sh draws itself
      sgr =
        name:
        let
          h = lib.removePrefix "#" theme.palette.${name};
          byte = i: toString (lib.fromHexString (builtins.substring i 2 h));
        in
        "\\[\\e[0;38;2;${byte 0};${byte 2};${byte 4}m\\]";
      # the same colour as a plain escape, for printf
      ansi =
        name:
        let
          h = lib.removePrefix "#" theme.palette.${name};
          byte = i: toString (lib.fromHexString (builtins.substring i 2 h));
        in
        "\\e[0;38;2;${byte 0};${byte 2};${byte 4}m";
      bold = "\\[\\e[1m\\]";
      reset = "\\[\\e[0m\\]";
      # a run prompt collapses to this one plain line, the shape of a shell transcript
      finalPrompt = lib.concatStrings [
        "${sgr "bright-black"}[\\t] "
        "${sgr (if isRoot then "red" else "white")}\\u"
        "${sgr "white"}@"
        "${sgr hostColour}${bold}\\h"
        "${sgr "white"}:"
        "${sgr "blue"}\\w"
        "${sgr "green"}\${_prompt_branch:+ (\$_prompt_branch)}"
        "${sgr "white"}\\$ "
        reset
      ];
    in
    {

      # Git
      programs.git = {
        enable = true;
        # sops template rendered here by profiles/PC.nix / profiles/server.nix
        includes = [ { path = "${config.home.homeDirectory}/.config/git/identity"; } ];
      };

      # fzf
      programs.fzf = {
        enable = true;
        enableFishIntegration = true;
      }
      # not declared on the home-manager release tracking nixpkgs-stable
      // lib.optionalAttrs (lib.hasAttrByPath [ "programs" "fzf" "enableNushellIntegration" ] options) {
        enableNushellIntegration = false; # nushell isn't used; avoids a min-fzf-version assertion
      }
      # atuin owns Ctrl-R in bash; fish keeps fzf's
      // lib.optionalAttrs (lib.hasAttrByPath [ "programs" "fzf" "historyWidget" "bash" ] options) {
        historyWidget.bash.command = "";
      };

      # zoxide
      programs.zoxide = {
        enable = true;
        enableFishIntegration = true;
      };

      # BTOP
      programs.btop = {
        enable = true;
        settings = {
          color_theme = lib.mkDefault "night-owl";
          update_ms = 1000;
          cpu_single_graph = true;
          proc_per_core = true;
          proc_sorting = "cpu direct";
        };
      };

      # bash: the interactive shell
      programs.bash = {
        enable = true;
        inherit shellAliases;
        historyControl = [
          "ignoreboth"
          "erasedups"
        ];
        historySize = 100000;
        historyFileSize = 100000;
        shellOptions = [
          "histappend"
          "checkwinsize"
          "extglob"
          "globstar"
          "checkjobs"
          "autocd"
        ];
        initExtra = lib.mkMerge [
          # home.sessionVariables for non-login shells too (terminal emulators)
          (lib.mkOrder 10 ''
            . "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh"
          '')
          # ble.sh: autosuggestions, syntax highlighting, abbreviations, vi mode;
          # only on a real terminal, so Claude Code's and other tools' bash stays plain
          (lib.mkOrder 50 ''
            if [[ -t 0 && -t 1 && $TERM != dumb && -z ''${CLAUDECODE-} ]]; then
              # without ~/.cache, ble.sh tries to cache in its read-only store path
              mkdir -p "''${XDG_CACHE_HOME:-$HOME/.cache}"
              # unstable on every host, so the stable servers get the same hooks and options
              source -- ${pkgs-unstable.blesh}/share/blesh/ble.sh --attach=none
            fi
          '')
          ''
            set -o vi

            # grc: colourise ping, df, ps, ...
            GRC_ALIASES=true . ${pkgs.grc}/etc/profile.d/grc.sh
          ''
          # prompt hooks, ahead of starship's so its modules see what they export
          (lib.mkOrder 900 ''
            if [[ ''${BLE_VERSION-} ]]; then
              # tmux passes an escape on to the terminal only wrapped (allow-passthrough)
              _prompt_osc() {
                if [[ ''${TMUX-} ]]; then
                  printf '\ePtmux;\e\e]%s\a\e\\' "$1"
                else
                  printf '\e]%s\a' "$1"
                fi
              }
              _prompt_preexec() {
                _prompt_start=$EPOCHREALTIME _prompt_cmd=$1
                # prompt marks: command output starts
                printf '\e]133;C\a'
              }
              _prompt_precmd() {
                local st=$? ps=("''${BLE_PIPESTATUS[@]}")
                _prompt_status=$st
                # result line, only after a command ran (not an empty Enter or Ctrl-C)
                if [[ ''${_prompt_start-} ]]; then
                  local ms=$(((''${EPOCHREALTIME/[.,]/} - ''${_prompt_start/[.,]/}) / 1000)) t res= c
                  _prompt_start=
                  if ((ms < 60000)); then
                    printf -v t '%d.%ds' $((ms / 1000)) $((ms % 1000 / 100))
                  elif ((ms < 3600000)); then
                    printf -v t '%dm%02ds' $((ms / 60000)) $((ms / 1000 % 60))
                  else
                    printf -v t '%dh%02dm' $((ms / 3600000)) $((ms / 60000 % 60))
                  fi
                  if ((st)); then
                    # every exit code of the pipeline, a signal's name after its code
                    for c in "''${ps[@]}"; do
                      ((c > 128 && c < 160)) && c+=" SIG$(kill -l $((c - 128)) 2>/dev/null)"
                      res+=''${res:+|}$c
                    done
                    printf '${ansi "red"}[exit %s · %s]\e[0m\n' "$res" "$t"
                    res="exit $res"
                  elif ((ms >= 3000)); then
                    printf '${ansi "bright-black"}[done · %s]\e[0m\n' "$t"
                    res=done
                  fi
                  # Konsole pops this up only when its window isn't focused
                  if ((ms >= 30000)); then
                    local cmd=''${_prompt_cmd//[;$'\n\a\e']/ }
                    _prompt_osc "777;notify;''${HOSTNAME%%.*}: $res · $t;''${cmd:0:200}"
                  fi
                fi
                ${lib.optionalString wipedRoot ''
                  # wiped at boot: on the root filesystem, or on a tmpfs
                  if [[ $PWD != "''${_prompt_pwd-}" ]]; then
                    _prompt_pwd=$PWD
                    local -a fs
                    mapfile -t fs < <(stat -c %d -- . / 2>/dev/null; stat -f -c %T -- . 2>/dev/null)
                    if [[ ''${fs[0]-} == "''${fs[1]-}" || ''${fs[2]-} == tmpfs ]]; then
                      export PROMPT_WIPED=1
                    else
                      unset PROMPT_WIPED
                    fi
                  fi
                ''}
                # for the collapsed prompt
                _prompt_branch=$(git symbolic-ref --short -q HEAD 2>/dev/null)
              }
              blehook PREEXEC!=_prompt_preexec
              blehook PRECMD!=_prompt_precmd
            fi
          '')
          # prompt marks around starship's prompt, so it runs after starship's hook
          (lib.mkOrder 2999 ''
            if [[ ''${BLE_VERSION-} ]]; then
              _prompt_marks() {
                PS1='\[\e]133;D;'$_prompt_status'\a\e]133;A\a\]'$PS1'\[\e]133;B\a\]'
              }
              blehook PRECMD!=_prompt_marks
            fi
          '')
          # ble.sh attaches after every other integration has set up its hooks
          (lib.mkOrder 3000 ''
            [[ ! ''${BLE_VERSION-} ]] || ble-attach
          '')
        ];
      };

      # ble.sh settings
      xdg.configFile."blesh/init.sh".text = ''
        bleopt history_share=1
        # the prompt's result line reports exit codes and durations instead
        bleopt exec_errexit_mark=
        bleopt exec_elapsed_enabled=0
        # a run prompt collapses to a blank line and one plain line, without the frame's right corner
        bleopt prompt_ps1_final='\n\[\e]133;A\a\]${finalPrompt}\[\e]133;B\a\]'
        bleopt prompt_rps1_transient=1
        bind 'set completion-ignore-case on'

        ble-sabbrev rsync='rsync --verbose --recursive --progress --human-readable'

        function blerc/vim-mode-hook {
          # no "-- INSERT --" line; the cursor shape shows the mode
          bleopt keymap_vi_mode_show=
          # cursor shape per vi mode: block in normal, bar in insert
          ble-bind -m vi_nmap --cursor 2
          ble-bind -m vi_imap --cursor 5
          ble-bind -m vi_omap --cursor 4
          ble-bind -m vi_xmap --cursor 2
          ble-bind -m vi_cmap --cursor 0
          # up/down search history for what's already typed, like fish
          ble-bind -m vi_imap -f up 'history-substring-search-backward hide-status:immediate-accept:point=end:empty=history-move'
          ble-bind -m vi_imap -f down 'history-substring-search-forward hide-status:immediate-accept:point=end:empty=history-move'
        }
        blehook/eval-after-load keymap_vi blerc/vim-mode-hook

        # enter runs a complete command even when it spans lines (a paste); otherwise adds a line
        function ble/widget/blerc/accept-if-complete {
          ble-edit/content/update-syntax
          if ble/syntax:bash/is-complete; then
            ble/widget/accept-line
          else
            ble/widget/newline
          fi
        }
        ble-bind -m vi_imap -f 'RET' blerc/accept-if-complete
        ble-bind -m vi_imap -f 'C-m' blerc/accept-if-complete
      '';

      # starship: two-line powerline prompt, modelled on fish's tide; left is
      # where you are, right is only what's true now (environment, jobs, user@host)
      programs.starship = {
        enable = true;
        enableFishIntegration = false;
        settings = {
          add_newline = true;
          palette = "theme";
          palettes.theme = theme.palette;
          format = lib.concatStrings [
            "[╭─](bright-black)"
            "$os"
            "\${env_var.PROMPT_WIPED}"
            "$directory"
            "($git_branch$git_commit$git_state$git_status[ ](bg:green)[${g.right}](fg:green))"
            " $fill "
            # one block: starship can't join segments whose neighbours come and go
            "([${g.left}](fg:base02)$direnv$nix_shell$jobs$username$hostname[ ](bg:base02))"
            "[─╮](bright-black)"
            "$line_break"
            "[╰─](bright-black)"
            "$character"
          ];
          # needs ble.sh in bash
          right_format = "[─╯](bright-black)";

          fill = {
            symbol = "·";
            style = "bright-black";
          };
          os = {
            disabled = false;
            style = "fg:black bg:white";
            format = "[ $symbol ]($style)";
            symbols.NixOS = g.nixos;
          };
          # set by the prompt hook where the directory is wiped at boot
          env_var.PROMPT_WIPED = {
            style = "fg:brown bg:white";
            format = "[${g.recycle} ]($style)";
          };
          # repo_root_format is used inside a git repo, where the git segment closes the arrow
          directory = {
            style = "fg:bright-white bg:blue";
            read_only_style = "fg:bright-white bg:blue";
            before_repo_root_style = "fg:bright-white bg:blue";
            repo_root_style = "bold fg:bright-white bg:blue";
            read_only = " ${g.lock}";
            truncate_to_repo = false;
            truncation_length = 6;
            format = "[${g.right}](fg:white bg:blue)[ $path]($style)[$read_only]($read_only_style)[ ](bg:blue)[${g.right}](fg:blue)";
            repo_root_format = "[${g.right}](fg:white bg:blue)[ $before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style)[ ](bg:blue)";
          };
          git_branch = {
            only_attached = true;
            symbol = "${g.branch} ";
            style = "fg:black bg:green";
            format = "[${g.right}](fg:blue bg:green)[ $symbol$branch]($style)";
          };
          git_commit = {
            style = "fg:black bg:green";
            format = "[${g.right}](fg:blue bg:green)[ $hash$tag]($style)";
          };
          git_state = {
            style = "fg:black bg:green";
            format = "[ \\($state( $progress_current/$progress_total)\\)]($style)";
          };
          git_status = {
            style = "fg:black bg:green";
            format = "([$ahead_behind$all_status]($style))";
            ahead = " ⇡\${count}";
            behind = " ⇣\${count}";
            diverged = " ⇡\${ahead_count}⇣\${behind_count}";
            conflicted = " ~\${count}";
            stashed = " *\${count}";
            deleted = " ✘\${count}";
            renamed = " »\${count}";
            modified = " !\${count}";
            typechanged = "";
            staged = " +\${count}";
            untracked = " ?\${count}";
          };

          # the right block: one dark pill, each item told apart by its colour
          # just the ▼ while loaded and allowed, like tide
          direnv = {
            disabled = false;
            symbol = "▼";
            style = "fg:yellow bg:base02";
            loaded_msg = "";
            unloaded_msg = " not loaded";
            allowed_msg = "";
            not_allowed_msg = " not allowed";
            denied_msg = " denied";
            format = "[ $symbol$loaded$allowed]($style)";
          };
          nix_shell = {
            symbol = "${g.nixos} ";
            style = "fg:blue bg:base02";
            format = "[ $symbol$state( \\($name\\))]($style)";
          };
          jobs = {
            symbol = g.gear;
            style = "fg:green bg:base02";
            format = "[ $symbol( $number)]($style)";
          };
          # shown over ssh or as root
          username = {
            style_user = "fg:white bg:base02";
            style_root = "bold fg:red bg:base02";
            format = "[ $user]($style)";
          };
          hostname = {
            style = "bold fg:${hostColour} bg:base02";
            format = "[@](fg:white bg:base02)[$hostname]($style)";
          };
          character = {
            success_symbol = "[❯](bold green)";
            error_symbol = "[❯](bold red)";
          };
        };
      };

      # atuin: searchable shell history on Ctrl-R, local only (no account, no sync)
      programs.atuin = {
        enable = true;
        enableFishIntegration = false;
        # up arrow stays ble.sh's history search
        flags = [ "--disable-up-arrow" ];
        settings.update_check = false;
      };

      # direnv: load a repo's .envrc dev shell on cd
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        config.global.hide_env_diff = true;
      };

      # fish: kept as a fallback shell until it's removed
      programs.fish = {
        enable = true;
        interactiveShellInit = ''
          set fish_greeting # Disable greeting
          tide configure --auto --style=Rainbow --prompt_colors='16 colors' --show_time='24-hour format' --rainbow_prompt_separators=Angled --powerline_prompt_heads=Sharp --powerline_prompt_tails=Flat --powerline_prompt_style='Two lines, character and frame' --prompt_connection=Dotted --powerline_right_prompt_frame=Yes --prompt_spacing=Sparse --icons='Many icons' --transient=No
          set -g fish_key_bindings fish_vi_key_bindings
          clear
        '';
        plugins = [
          {
            name = "grc";
            src = pkgs-stable.fishPlugins.grc.src;
          }
          {
            name = "tide";
            src = pkgs-stable.fishPlugins.tide.src;
          }
        ];
        functions = {
          __fish_command_not_found_handler.body = ''
            comma $argv[1]
          '';

        };
        inherit shellAliases;
        shellAbbrs = {
          rsync = "rsync --verbose --recursive --progress --human-readable";
        };
      };

      # bat
      programs.bat = {
        enable = true;
        config = {
          pager = "never";
        };
      };

      # eza
      programs.eza = {
        enable = true;
        enableBashIntegration = false;
        enableFishIntegration = false;
      };
    };
}

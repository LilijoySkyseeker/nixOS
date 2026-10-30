_: {
  flake.modules.homeManager.tooling =
    {
      pkgs,
      pkgs-stable,
      config,
      lib,
      options,
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
        hourglass = "f252";
      };
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
              # without ~/.cache, ble.sh 0.4.0-devel3 (stable) tries to cache in its read-only store path
              mkdir -p "''${XDG_CACHE_HOME:-$HOME/.cache}"
              source -- ${pkgs.blesh}/share/blesh/ble.sh --attach=none
            fi
          '')
          ''
            set -o vi

            # grc colours output for commands that have no colour of their own;
            # not grc's full alias list, which also wraps journalctl, ip, diff,
            # head, tail and docker and loses their own colours, pager or tty
            for c in blkid df dig du findmnt free id lsblk lsof lspci mount netstat ping ps ss traceroute traceroute6; do
              alias "$c=${pkgs.grc}/bin/grc -es $c"
            done
          ''
          # ble.sh attaches after every other integration has set up its hooks
          (lib.mkOrder 3000 ''
            [[ ! ''${BLE_VERSION-} ]] || ble-attach
          '')
        ];
      };

      # ble.sh settings
      xdg.configFile."blesh/init.sh".text = ''
        bleopt history_share=1
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

      # starship: two-line rainbow powerline prompt, modelled on fish's tide
      programs.starship = {
        enable = true;
        enableFishIntegration = false;
        settings = {
          add_newline = true;
          format = lib.concatStrings [
            "[╭─](bright-black)"
            "$os"
            "$directory"
            "($git_branch$git_commit$git_state$git_status[ ](bg:green)[${g.right}](fg:green))"
            " $fill "
            "$status"
            "$cmd_duration"
            "$username"
            "$hostname"
            "$jobs"
            "$direnv"
            "$nix_shell"
            "$time"
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

          status = {
            disabled = false;
            style = "fg:bright-yellow bg:red";
            format = "[${g.left}](fg:red)[ ✘ $status ]($style)";
          };
          cmd_duration = {
            min_time = 3000;
            style = "fg:black bg:yellow";
            format = "[${g.left}](fg:yellow)[ $duration ${g.hourglass} ]($style)";
          };
          username = {
            style_user = "fg:yellow bg:black";
            style_root = "fg:red bg:black";
            format = "[${g.left}](fg:black)[ $user ]($style)";
          };
          hostname = {
            style = "fg:yellow bg:black";
            format = "[@$hostname ]($style)";
          };
          jobs = {
            symbol = g.gear;
            style = "fg:black bg:green";
            format = "[${g.left}](fg:green)[ $symbol( $number) ]($style)";
          };
          # just the ▼ while loaded and allowed, like tide
          direnv = {
            disabled = false;
            symbol = "▼";
            style = "fg:black bg:bright-yellow";
            loaded_msg = "";
            unloaded_msg = " not loaded";
            allowed_msg = "";
            not_allowed_msg = " not allowed";
            denied_msg = " denied";
            format = "[${g.left}](fg:bright-yellow)[ $symbol$loaded$allowed ]($style)";
          };
          nix_shell = {
            symbol = "${g.nixos} ";
            style = "fg:black bg:bright-blue";
            format = "[${g.left}](fg:bright-blue)[ $symbol$state( \\($name\\)) ]($style)";
          };
          time = {
            disabled = false;
            time_format = "%T";
            style = "fg:black bg:white";
            format = "[${g.left}](fg:white)[ $time ]($style)";
          };
          character = {
            success_symbol = "[❯](bold bright-green)";
            error_symbol = "[❯](bold bright-red)";
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

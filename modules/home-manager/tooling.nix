{
  pkgs-stable,
  pkgs-unstable,
  config,
  lib,
  options,
  ...
}:
{

  # Helix text editor
  programs.helix = {
    enable = true;
    defaultEditor = false;
    settings = {
      theme = lib.mkForce "gruvbox_dark_soft";
      editor = {
        inline-diagnostics = {
          cursor-line = "error";
        };
        end-of-line-diagnostics = "hint";
        statusline = {
          left = [
            "mode"
            "spinner"
            "version-control"
            "file-absolute-path"
          ];
        };
        lsp = {
          display-inlay-hints = true;
        };
        indent-guides = {
          character = "╎";
          render = true;
        };
        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "underline";
        };
        bufferline = "multiple";
        cursorline = true;
      };
      keys = {
        normal = {
          A-x = "extend_to_line_bounds";
          X = "select_line_above";
        };
        select = {
          A-x = "extend_to_line_bounds";
          X = "select_line_above";
        };
      };
    };
    languages = {
      language = [
        {
          name = "nix";
          scope = "source.nix";
          injection-regex = "nix";
          file-types = [ "nix" ];
          shebangs = [ ];
          roots = [ "flake.lock" ];
          auto-format = true;
          comment-token = "#";
          language-servers = [
            "nil"
            "nixd"
          ];
          formatter.command = "${pkgs-stable.nixfmt}/bin/nixfmt";
        }
      ];
      language-server = {
        nil = {
          command = "${pkgs-stable.nil}/bin/nil";
          args = [ "--stdio" ];
        };
        nixd = {
          command = "${pkgs-stable.nixd}/bin/nixd";
        };
      };
    };
  };

  # Git
  programs.git = {
    enable = true;
    includes = [ { path = "/home/lilijoy/.config/git/identity"; } ];
  };

  # fzf
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  }
  # not declared on the home-manager release tracking nixpkgs-stable
  // lib.optionalAttrs (lib.hasAttrByPath [ "programs" "fzf" "enableNushellIntegration" ] options) {
    enableNushellIntegration = false; # nushell isn't used; avoids a min-fzf-version assertion
  };

  # KDE Connect
  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  # zoxide
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # OBS Studio
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs-stable.obs-studio-plugins; [ obs-pipewire-audio-capture ];
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

  # Obsidian
  programs.obsidian = {
    enable = true;
    package = pkgs-unstable.obsidian;
    cli.enable = true;
  };

  # Firefox
  programs.firefox = {
    enable = true;
    configPath = "${config.xdg.configHome}/mozilla/firefox";

  };

  # fish
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
      ns.body = ''
        export NIXPKGS_ALLOW_UNFREE=1 && nix shell 'nixpkgs/nixos-unstable#'{$argv} --impure
      '';
      nhu.body = ''
        git add --all && nix flake update && git add --all
      '';
      nht.body = ''
        git add --all && nh os test
      '';
      nhb.body = ''
        git add --all && nh os boot && git diff --staged | bat --paging always --pager less && git commit -a && git push
      '';
      nhs.body = ''
        git add --all && nh os switch && git diff --staged | bat --paging always --pager less && git commit -a && git push
      '';
      gds.body = ''
        git add --all && git diff --staged | bat --paging always --pager less
      '';
      deploy-homelab.body = ''
        ssh root@homelab systemctl start --wait nixos-upgrade.service
      '';
      __fish_command_not_found_handler.body = ''
        comma $argv[1]
      '';

    };
    shellAliases = {
      e = "eza --group-directories-first --header --git --git-ignore --icons --all --long --mounts";
      et = "eza --tree --group-directories-first --header --git --git-ignore --icons --all --long --mounts";
      etl = "eza --tree --group-directories-first --header --git --git-ignore --icons --all --long --mounts --level";
    };
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
}

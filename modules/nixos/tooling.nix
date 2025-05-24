{ pkgs, lib, ... }:
{
  # Git
  programs.git = {
    enable = true;
    config = {
      push.autoSetupRemote = true;
    };
  };

  # fish
  programs.fish = {
    enable = true;
    vendor.completions.enable = true;
  };
  programs.bash = {
    # switch to fish in interactive shell
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };
  environment.shellAliases = lib.mkForce { }; # clear all shell aliases, using fish functions instead

  # neovim
  programs.neovim = {
    enable = true;
    defaultEditor = lib.mkForce true;
  };
  programs.nvf = {
    enable = true;
    settings = {
      vim = {
        clipboard = {
          enable = true;
          providers = {
            wl-copy.enable = true;
            xclip.enable = true;
            xsel.enable = true;
          };
          registers = [
            "unnamed"
            "unnamedplus"
          ];
        };
        viAlias = true;
        vimAlias = true;
        undoFile = {
          enable = true;
        };
        binds.whichKey.enable = true;
        searchCase = "smart";
        lsp.enable = true;
        languages = {
          enableDAP = true;
          enableExtraDiagnostics = true;
          enableFormat = true;
          enableTreesitter = true;
          nix = {
            enable = true;
            format.type = "nixfmt";
            extraDiagnostics.enable = false;
          };
          markdown.enable = true;
          bash.enable = true;
        };
        lsp.formatOnSave = true;
        maps = {
          normal = {
            "j".action = "gj";
            "k".action = "gk";
            "p".action = "pgvy";
          };
        };
        options = {
          shiftwidth = 2;
          tabstop = 2;
          scrolloff = 8;
        };
        statusline.lualine = {
          enable = true;
          theme = lib.mkForce "gruvbox_dark"; # TEMP
        };
        visuals = {
          highlight-undo = {
            enable = true;
            setupOpts.duration = 1000;
          };
        };
        git = {
          enable = true;
        };
        telescope.enable = true;
        autocomplete.nvim-cmp.enable = true;
        autopairs.nvim-autopairs.enable = true;
        theme = {
          enable = true;
           name = lib.mkForce "gruvbox";
          style = "dark";
          transparent = lib.mkForce true;
        };
      };
    };
  };
}

_: {
  flake.modules.nixos.tooling =
    { lib, ... }:
    {
      # Git
      programs.git = {
        enable = true;
        config = {
          push.autoSetupRemote = true;
        };
      };

      # fish: fallback shell; bash is the interactive shell (home-manager tooling.nix)
      programs.fish = {
        enable = true;
      };
      environment.shellAliases = lib.mkForce { }; # clear NixOS's default aliases; ours live in home-manager

      # neovim
      programs.neovim = {
        enable = true;
        defaultEditor = lib.mkForce true;
      };
      programs.nvf = {
        enable = true;
        enableManpages = true;
        settings = {
          vim = {
            clipboard = {
              enable = true;
              providers = {
                wl-copy.enable = true;
                xclip.enable = true;
                xsel.enable = true;
              };
              registers = "unnamedplus";
            };
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
                format.type = [ "nixfmt" ];
                extraDiagnostics.enable = false;
              };
              markdown.enable = true;
              bash.enable = true;
              python.enable = true;
              typescript.enable = true;
              rust.enable = true;
              go.enable = true;
              lua.enable = true;
              json.enable = true;
              yaml.enable = true;
              html.enable = true;
              css.enable = true;
              docker.enable = true;
            };
            lsp.formatOnSave = true;
            lsp.trouble.enable = true;
            debugger = {
              nvim-dap = {
                enable = true;
                ui.enable = true;
              };
            };
            maps = {
              normal = {
                "j".action = "gj";
                "k".action = "gk";
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
              neogit.enable = true;
            };
            filetree.neo-tree.enable = true;
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
    };
}

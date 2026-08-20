{ pkgs-unstable, inputs, ... }:
{
  imports = [ inputs.plasma-manager.homeModules.plasma-manager ];

  # tmux: vi keybinds throughout, sessions persisted/restored across reboots
  programs.tmux = {
    enable = true;
    keyMode = "vi";
    prefix = "C-a";
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    plugins = with pkgs-unstable.tmuxPlugins; [
      vim-tmux-navigator # C-h/j/k/l moves seamlessly between tmux panes and vim splits
      sensible
      {
        plugin = resurrect;
        extraConfig = "set -g @resurrect-strategy-nvim 'session'";
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
    ];
    extraConfig = ''
      # vi-style pane navigation (also handled by vim-tmux-navigator across nvim splits)
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-selection-and-cancel
    '';
  };

  # kitty: GPU terminal emulator hosting tmux; kitty itself stays unconfigured
  # beyond shell integration since tmux owns multiplexing/keybinds
  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    settings = {
      confirm_os_window_close = 0;
      shell = "${pkgs-unstable.tmux}/bin/tmux new-session -A -s main";
    };
  };

  # register kitty as the freedesktop default terminal (xdg-terminal-exec,
  # file managers, "Open Terminal Here", etc.)
  xdg.terminal-exec = {
    enable = true;
    settings.default = [ "kitty.desktop" ];
  };

  # KDE-specific: default terminal app + Meta+Return global shortcut,
  # kept declarative via plasma-manager rather than a manual System Settings step
  programs.plasma = {
    enable = true;
    configFile."kdeglobals"."General" = {
      TerminalApplication = "kitty";
      TerminalService = "kitty.desktop";
    };
    hotkeys.commands."launch-terminal" = {
      key = "Meta+Return";
      command = "${pkgs-unstable.kitty}/bin/kitty";
      comment = "Launch kitty (tmux) terminal";
    };
  };
}

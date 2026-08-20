{ pkgs-unstable, inputs, ... }:
{
  imports = [
    ./tmux.nix
    inputs.plasma-manager.homeModules.plasma-manager
  ];

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

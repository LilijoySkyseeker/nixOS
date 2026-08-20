{ pkgs-unstable, ... }:
{
  # tmux: vi keybinds throughout, sessions persisted/restored across reboots.
  # Shared by every host (root on servers, lilijoy on PCs) so a tmux session
  # behaves the same whether it's a local terminal or an SSH session.
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
}

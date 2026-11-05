_: {
  flake.modules.homeManager.tmux =
    { pkgs-unstable, ... }:
    {
      programs.tmux = {
        enable = true;
        keyMode = "vi";
        prefix = "C-a";
        mouse = true;
        baseIndex = 1;
        escapeTime = 0;
        plugins = with pkgs-unstable.tmuxPlugins; [
          vim-tmux-navigator
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
          bind -T copy-mode-vi v send -X begin-selection
          bind -T copy-mode-vi y send -X copy-selection-and-cancel
        '';
      };
    };
}

_: {
  flake.modules.homeManager."tooling-desktop" =
    {
      pkgs-stable,
      pkgs-unstable,
      config,
      ...
    }:
    {
      programs.bash.initExtra = ''
        command_not_found_handle() { comma "$@"; }
      '';

      programs.obs-studio = {
        enable = true;
        plugins = with pkgs-stable.obs-studio-plugins; [ obs-pipewire-audio-capture ];
      };

      programs.obsidian = {
        enable = true;
        package = pkgs-unstable.obsidian;
        cli.enable = true;
      };

      programs.firefox = {
        enable = true;
        configPath = "${config.xdg.configHome}/mozilla/firefox";
      };
    };
}

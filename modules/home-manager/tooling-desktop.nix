_: {
  flake.modules.homeManager."tooling-desktop" =
    {
      pkgs-stable,
      pkgs-unstable,
      config,
      ...
    }:
    {
      # bash: unknown command fetches and runs it from nixpkgs; desktop only (docs/accepted-risks.md AR-4)
      programs.bash.initExtra = ''
        command_not_found_handle() { comma "$@"; }
      '';

      # KDE Connect
      services.kdeconnect = {
        enable = true;
        indicator = true;
      };

      # OBS Studio
      programs.obs-studio = {
        enable = true;
        plugins = with pkgs-stable.obs-studio-plugins; [ obs-pipewire-audio-capture ];
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
    };
}

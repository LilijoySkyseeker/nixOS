{ ... }:
{
  flake.modules.homeManager."tooling-desktop" =
    {
      pkgs-stable,
      pkgs-unstable,
      config,
      ...
    }:
    {
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

_: {
  flake.modules.homeManager."tooling-desktop" =
    {
      pkgs-stable,
      pkgs-unstable,
      config,
      lib,
      ...
    }:
    {
      # Konsole: a selection is copied to the clipboard too, as plain text without
      # trailing spaces; written into whichever profile is the default, keeping
      # its other settings (or into a new one if only the built-in exists)
      home.activation.konsoleCopyOnSelect = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        kwrite=${pkgs-unstable.kdePackages.kconfig}/bin/kwriteconfig6
        rc=${config.xdg.configHome}/konsolerc
        profile=$(${pkgs-unstable.kdePackages.kconfig}/bin/kreadconfig6 --file "$rc" --group "Desktop Entry" --key DefaultProfile)
        if [[ -z $profile ]]; then
          profile="Profile 1.profile"
          run $kwrite --file "$rc" --group "Desktop Entry" --key DefaultProfile "$profile"
        fi
        file=${config.xdg.dataHome}/konsole/$profile
        if [[ ! -e $file ]]; then
          run mkdir -p "$(dirname "$file")"
          run $kwrite --file "$file" --group General --key Name "''${profile%.profile}"
          run $kwrite --file "$file" --group General --key Parent FALLBACK/
        fi
        run $kwrite --file "$file" --group "Interaction Options" --key AutoCopySelectedText true
        run $kwrite --file "$file" --group "Interaction Options" --key CopyTextAsHTML false
        run $kwrite --file "$file" --group "Interaction Options" --key TrimTrailingSpacesInSelectedText true
      '';

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

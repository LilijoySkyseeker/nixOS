{pkgs-unstable, ...}: {

  # System installed pkgs
  environment.systemPackages = with pkgs-unstable; [
      beets
    ];

  # beets config
  environment = {
    variables = {
      BEETSDIR = "/etc/beets";
    };
    etc."beetsConfig" = {
      text = ''
        threaded: yes
        directory: /storage/Music
        library: /srv/beets/musiclibrary.db
        plugins: info rewrite chroma fromfilename edit fetchart lyrics scrub albumtypes missing

        paths:
            comp: Compilations/$label/$year - $album%aunique{}/$track $title
            default: Artists/$albumartist/$atypes/$year - $album%aunique{}/$track $title
            singleton: Non-Album/$artist/$title/$title

        albumtypes:
            types:
                - single: 'Singles'
        import:
            copy: no
            write: no
            move: no
      '';
      target = "/beets/config.yaml";
    };
  };

  # persistence
  environment.persistence."/nix/state" = {
    # https://github.com/nix-community/impermanence?tab=readme-ov-file#module-usage
    enable = true;
    hideMounts = true;
    directories = [
      "/etc/beets" # beets
    ];
    files = [
      "/srv/beets/musiclibrary.db" # beets
    ];
  };
}

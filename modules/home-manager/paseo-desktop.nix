_: {
  flake.modules.homeManager."paseo-desktop" =
    {
      config,
      lib,
      pkgs-unstable,
      ...
    }:
    let
      # the app rewrites this file itself, so the declared keys are merged in
      # rather than linked
      settingsFile = "${config.xdg.configHome}/Paseo/desktop-settings.json";
      managed = pkgs-unstable.writeText "paseo-desktop-settings.json" (
        builtins.toJSON {
          settings.daemon.manageBuiltInDaemon = false;
        }
      );
    in
    {
      # the daemon's patches, for their limit callout and credit spend in the UI
      home.packages = [
        (pkgs-unstable.paseo-desktop.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            # TODO: drop when getpaseo/paseo#7193 is in the packaged Paseo
            ../nixos/paseo/usage-limit-resume.patch
            ../nixos/paseo/limit-fallback.patch
          ];
        }))
      ];

      # every write goes through `run` to keep dry-run side-effect free
      home.activation.paseoDesktopSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        current='{}'
        [ -e "${settingsFile}" ] && current=$(cat "${settingsFile}")
        merged=$(${pkgs-unstable.jq}/bin/jq -n --argjson current "$current" \
          --slurpfile managed ${managed} '$current * $managed[0]')
        merged_tmp=$(mktemp)
        printf '%s\n' "$merged" > "$merged_tmp"
        run mkdir -p "$(dirname "${settingsFile}")"
        run install -m 644 "$merged_tmp" "${settingsFile}"
        rm -f "$merged_tmp"
      '';
    };
}

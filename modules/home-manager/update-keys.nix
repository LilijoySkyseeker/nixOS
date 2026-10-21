_: {
  flake.modules.homeManager."update-keys" =
    { pkgs-unstable, ... }:
    let
      # check out and pull master in the nh flake dir, then `nh os <switch|boot>`
      nixosUpdate = pkgs-unstable.writeShellApplication {
        name = "nixos-update";
        runtimeInputs = with pkgs-unstable; [
          git
          nh
        ];
        text = ''
          op="$1"
          cd "''${NH_FLAKE:?NH_FLAKE is not set}"
          if [ -n "$(git status --porcelain)" ]; then
            echo "nixos-update: $NH_FLAKE has uncommitted changes, not touching it" >&2
            exit 1
          fi
          git checkout master
          git pull --ff-only origin master
          nh os "$op"
        '';
      };
    in
    {
      # needs programs.plasma from plasma-manager, imported by audio-switch
      # (importing it twice redeclares its options)
      programs.plasma.hotkeys.commands = {
        # konsole --hold: the window stays open to show the result or error
        "nixos-update-switch" = {
          key = "Meta+Ctrl+Alt+Shift+U";
          command = "konsole --hold -e ${nixosUpdate}/bin/nixos-update switch";
          comment = "Pull master and nh os switch";
        };
        "nixos-update-boot" = {
          key = "Meta+Ctrl+Alt+Shift+B";
          command = "konsole --hold -e ${nixosUpdate}/bin/nixos-update boot";
          comment = "Pull master and nh os boot";
        };
      };
    };
}

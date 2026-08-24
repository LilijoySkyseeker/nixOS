{ ... }:
{
  # Claude Code's own config lives in ~/.claude and the CLI writes to
  # settings.json itself (that's how /model and /effort persist), so only the
  # statusLine script is managed here - a store symlink over settings.json
  # would make those writes fail.
  #
  # The claude-code package itself comes from profile-pc's systemPackages.
  flake.modules.homeManager.claude-code =
    { pkgs-unstable, ... }:
    let
      # statusLine is invoked as a bare command, inheriting whatever PATH the
      # terminal happens to have - jq otherwise only exists in this repo's
      # devshell, so the bar silently emptied out anywhere else. Packaging the
      # script pins its own deps instead.
      #
      # bashOptions is emptied deliberately: the script uses `cond && printf`
      # idioms for optional segments, whose non-zero exits would trip errexit.
      statusline = pkgs-unstable.writeShellApplication {
        name = "claude-statusline";
        runtimeInputs = with pkgs-unstable; [
          jq
          git
          coreutils
        ];
        bashOptions = [ ];
        text = builtins.readFile ../../files/claude-statusline.sh;
      };
    in
    {
      home.file.".claude/statusline.sh".source = "${statusline}/bin/claude-statusline";
    };
}

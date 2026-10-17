# agent-tools: CLI tools agent sessions reach for, on every PC so the user's
# own agent sessions get them too (the agent's PATH includes the system's)
_: {
  flake.modules.nixos."agent-tools" =
    { pkgs-unstable, ... }:
    {
      # each was a "command not found" or `nix shell` in agent transcripts;
      # add one when it keeps showing up there, not in case
      environment.systemPackages = with pkgs-unstable; [
        python3
        poppler-utils # pdftotext, pdfinfo
        file
        unzip
        perl
        bc
        binutils # strings
        xxd
      ];
    };
}

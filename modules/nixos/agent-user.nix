# The agent's place: a separate Unix user on torrent where all
# non-sensitive agent work runs with no prompts. It never holds root, the
# user's keys or private data, so the boundary is this user, not a rule.
# plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md
{
  flake.modules.nixos."agent-user" =
    { pkgs, ... }:
    {
      # own group, not the isNormalUser default `users` (lilijoy's group)
      # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#G2
      users.groups.agent = { };
      users.users.agent = {
        isNormalUser = true;
        group = "agent";
        homeMode = "700";
        description = "Claude agent (non-sensitive work)";
        packages = with pkgs; [
          git
          gh
        ];
      };

      # may use the nix daemon to build; never trusted-users
      nix.settings.allowed-users = [ "agent" ];

      systemd.tmpfiles.rules = [
        "d /home/agent/work 0700 agent agent -"
        "d /home/agent/repos 0700 agent agent -"
      ];
    };
}

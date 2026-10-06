# The agent's place: a separate Unix user on torrent where all
# non-sensitive agent work runs with no prompts. It never holds root, the
# user's keys or private data, so the boundary is this user, not a rule.
# plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md
{
  flake.modules.nixos."agent-user" =
    { lib, pkgs, ... }:
    let
      egress = [
        {
          cmd = "iptables";
          nets = [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "100.64.0.0/10" # tailnet
            "169.254.0.0/16"
          ];
        }
        {
          cmd = "ip6tables";
          nets = [
            "fc00::/7" # includes the tailnet's fd7a:115c:a1e0::/48
            "fe80::/10"
          ];
        }
      ];
    in
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

      # agent-egress: the agent uid can't reach the LAN or tailnet (the
      # tailnet ACL is flat); the rest of the internet stays open, and
      # loopback stays reachable for DNS via resolved
      networking.firewall.extraCommands = ''
        ${lib.concatMapStrings (
          { cmd, nets }:
          ''
            ${cmd} -N agent-egress 2>/dev/null || ${cmd} -F agent-egress
            ${lib.concatMapStrings (net: ''
              ${cmd} -A agent-egress -d ${net} -j REJECT
            '') nets}
            ${cmd} -C OUTPUT -m owner --uid-owner agent -j agent-egress 2>/dev/null \
              || ${cmd} -A OUTPUT -m owner --uid-owner agent -j agent-egress
          ''
        ) egress}
      '';
      networking.firewall.extraStopCommands = ''
        ${lib.concatMapStrings (
          { cmd, ... }:
          ''
            ${cmd} -D OUTPUT -m owner --uid-owner agent -j agent-egress 2>/dev/null || true
            ${cmd} -F agent-egress 2>/dev/null || true
            ${cmd} -X agent-egress 2>/dev/null || true
          ''
        ) egress}
      '';

      # bindfs: only Vault/Research, shown to the agent as its own; anything
      # it creates lands lilijoy:users in the real folder Obsidian syncs.
      # automount, not boot-time: /home is a late ZFS mount, and the source is
      # user data (created once by the user), never by root inside their home
      # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#G1
      system.fsPackages = [ pkgs.bindfs ];
      systemd = {
        tmpfiles.rules = [
          "d /home/agent/work 0700 agent agent -"
          "d /home/agent/repos 0700 agent agent -"
        ];

        # systemd units, not fileSystems: NixOS VM tests replace fileSystems
        # wholesale (qemu-vm mkVMOverride), which would leave the mount untested
        # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#G3
        mounts = [
          {
            what = "/home/lilijoy/Documents/Vault/Research";
            where = "/home/agent/research";
            type = "fuse.bindfs";
            options = "force-user=agent,force-group=agent,create-for-user=lilijoy,create-for-group=users";
          }
        ];
        automounts = [
          {
            where = "/home/agent/research";
            wantedBy = [ "multi-user.target" ];
          }
        ];
      };
    };
}

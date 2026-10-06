# The agent's place: a separate Unix user on torrent where all
# non-sensitive agent work runs with no prompts. It never holds root, the
# user's keys or private data, so the boundary is this user, not a rule.
# plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md
{
  flake.modules.nixos."agent-user" =
    { lib, pkgs, ... }:
    let
      # agent-egress rules per family. IPv6 refuses everything but loopback:
      # the LAN's v6 is a dynamic ISP global prefix that can't be listed,
      # and the internet still works over IPv4
      # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F1
      egress = [
        {
          cmd = "iptables";
          rules = map (net: "-d ${net} -j REJECT") [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "100.64.0.0/10" # tailnet
            "169.254.0.0/16"
            "224.0.0.0/4" # multicast
            "255.255.255.255/32" # broadcast
          ];
        }
        {
          cmd = "ip6tables";
          rules = [
            "-o lo -j RETURN"
            "-j REJECT"
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

      # no inbound ssh: it can write its own authorized_keys, and a login
      # shell would sit outside the service sandbox
      # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F8
      services.openssh.settings.DenyUsers = [ "agent" ];

      # may use the nix daemon to build; never trusted-users
      nix.settings.allowed-users = [ "agent" ];

      # agent-egress: the agent uid can't reach the LAN or tailnet (the
      # tailnet ACL is flat); the rest of the internet stays open, and
      # loopback stays reachable for DNS via resolved
      networking.firewall.extraCommands = ''
        ${lib.concatMapStrings (
          { cmd, rules }:
          ''
            ${cmd} -N agent-egress 2>/dev/null || ${cmd} -F agent-egress
            ${lib.concatMapStrings (rule: ''
              ${cmd} -A agent-egress ${rule}
            '') rules}
            ${cmd} -C OUTPUT -m owner --uid-owner agent -j agent-egress 2>/dev/null \
              || ${cmd} -A OUTPUT -m owner --uid-owner agent -j agent-egress
            ${cmd} -C OUTPUT -m owner --gid-owner nixbld -j agent-egress 2>/dev/null \
              || ${cmd} -A OUTPUT -m owner --gid-owner nixbld -j agent-egress
          ''
        ) egress}
      '';
      networking.firewall.extraStopCommands = ''
        ${lib.concatMapStrings (
          { cmd, ... }:
          ''
            ${cmd} -D OUTPUT -m owner --uid-owner agent -j agent-egress 2>/dev/null || true
            ${cmd} -D OUTPUT -m owner --gid-owner nixbld -j agent-egress 2>/dev/null || true
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
        # the phone reaches the agent through this: Remote Control server
        # mode, sessions spawned in ~/work with no permission prompts (the
        # walls are this user, agent-egress and the Research-only mount).
        # ~ itself can't be the cwd: Claude never saves trust for a home dir.
        # Skipped until the one-time `claude auth login` writes credentials
        services.claude-remote-control = {
          description = "Claude Code Remote Control server for the agent user";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          # stop with the firewall: a stopped or failed firewall drops agent-egress
          # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F9
          bindsTo = [ "firewall.service" ];
          after = [
            "network-online.target"
            "firewall.service"
          ];
          unitConfig.ConditionPathExists = "/home/agent/.claude/.credentials.json";
          environment = {
            HOME = "/home/agent";
            # keep the account's claude.ai connectors (and their data) out
            ENABLE_CLAUDEAI_MCP_SERVERS = "false";
            PATH = lib.mkForce "/run/wrappers/bin:/etc/profiles/per-user/agent/bin:/run/current-system/sw/bin";
          };
          serviceConfig = {
            User = "agent";
            Group = "agent";
            WorkingDirectory = "/home/agent/work";
            ExecStart = "${pkgs.claude-code}/bin/claude remote-control --spawn same-dir --name torrent-agent --permission-mode bypassPermissions";
            Restart = "always";
            RestartSec = 30;

            # sandbox: every agent session is a child of this unit
            # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F3
            NoNewPrivileges = true; # no setuid helpers (qemu-bridge-helper, F4)
            PrivateTmp = true;
            PrivateDevices = true; # no /dev/kvm or /dev/net/tun (F4)
            ProtectSystem = "strict";
            ReadWritePaths = [ "/home/agent" ];
            # world-writable daemon sockets: VPN, tailnet and VM control (F5)
            InaccessiblePaths = [
              "-/run/mullvad-vpn"
              "-/run/tailscale"
              "-/run/libvirt"
            ];
            # a runaway agent can't take the desktop down with it
            MemoryMax = "24G";
            TasksMax = 4096;
            CPUWeight = 50;
          };
        };

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
            # a missing source fails each access; never let that hit the start
            # limit and wedge the automount until reboot
            unitConfig.StartLimitIntervalSec = 0;
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

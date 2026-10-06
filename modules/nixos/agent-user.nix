# agent-user: unprivileged `agent` user on torrent for prompt-free agent work
# plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F11
{
  flake.modules.nixos."agent-user" =
    { lib, pkgs, ... }:
    let
      # agent-egress rules per family; IPv6 rejects all but loopback
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
      # own group, not isNormalUser's default `users`
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

      # no inbound ssh
      # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F8
      services.openssh.settings.DenyUsers = [ "agent" ];

      # nix daemon access, not trusted-users
      nix.settings.allowed-users = [ "agent" ];

      # agent-egress: jumped from OUTPUT for uid agent and gid nixbld (every
      # user's sandboxed builds, lilijoy's included)
      # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F2
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

      # bindfs: Vault/Research only, agent-owned on its side, lilijoy:users on disk
      # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#G1
      system.fsPackages = [ pkgs.bindfs ];
      systemd = {
        # claude remote-control server: prompt-free sessions spawned in ~/work
        # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F11
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
          # skipped until the one-time `claude auth login`
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

        # systemd mount + automount, not fileSystems
        # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#G3
        mounts = [
          {
            what = "/home/lilijoy/Documents/Vault/Research";
            where = "/home/agent/research";
            type = "fuse.bindfs";
            options = "force-user=agent,force-group=agent,create-for-user=lilijoy,create-for-group=users";
            # no start limit: a missing source must not wedge the automount
            # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F10
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

# agent-user: unprivileged `agent` user on torrent for prompt-free agent work
{
  flake.modules.nixos."agent-user" =
    { lib, pkgs, ... }:
    let
      bot = "LilijoySkyseeker-agent";
      # orientation + the user's working rule (the same file as their own
      # user-level CLAUDE.md, so there's no copy to drift); Claude and Codex
      # both read it
      agentInstructions = pkgs.writeText "agent-AGENTS.md" (
        builtins.readFile ./agent-user-AGENTS.md
        + "\n"
        + builtins.readFile ../home-manager/claude-code/user-claude.md
      );
      sharedSkills = ../home-manager/claude-code/skills;
      # web-fetch: pages and feeds past bot walls (curl, curl-impersonate,
      # then real Chromium through nodriver in a virtual display)
      fetchPython = pkgs.python3.withPackages (ps: [
        ps.feedparser
        ps.nodriver
        ps.trafilatura
        ps.html2text
      ]);
      webFetch = pkgs.writeShellApplication {
        name = "web-fetch";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.curl
          pkgs.curl-impersonate
          pkgs.xvfb-run
          (pkgs.writeShellScriptBin "browser-fetch" ''
            exec ${fetchPython}/bin/python3 ${./agent-tools/browser-fetch.py} "$1" ${pkgs.chromium}/bin/chromium
          '')
          (pkgs.writeShellScriptBin "extract-text" ''
            exec ${fetchPython}/bin/python3 ${./agent-tools/extract-text.py} "$@"
          '')
          (pkgs.writeShellScriptBin "read-feed" ''
            exec ${fetchPython}/bin/python3 ${./agent-tools/read-feed.py} "$@"
          '')
        ];
        text = builtins.readFile ./agent-tools/web-fetch.sh;
      };
      # git identity: the bot's noreply address (its public GitHub id)
      gitIdentity = pkgs.writeText "agent-git-identity" ''
        [user]
          name = ${bot}
          email = 338765425+${bot}@users.noreply.github.com
      '';
      # git's user-wide ignore file: local notes stay out of every repo
      gitIgnore = pkgs.writeText "agent-git-ignore" ''
        AGENTS.local.md
      '';
      # check-and-fix for the parts that can't be declared
      agentSetup = pkgs.writeShellApplication {
        name = "agent-setup";
        runtimeInputs = with pkgs; [
          coreutils
          gh
          jq
          util-linux
        ];
        text = ''
          BOT=${bot}
          OWNER=LilijoySkyseeker
          BOT_REPOS="nixOS project-elysian"
          NAME=torrent-agent
        ''
        + builtins.readFile ./agent-setup.sh;
      };
      # torrent's RX 7900 XTX, by PCI path: DRM numbering follows probe order
      agentGpu = "/dev/dri/by-path/pci-0000:03:00.0-render";
      # sandbox shared by both agents' units: every agent
      # session is a child of one of them
      # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F3
      agentSandbox = {
        User = "agent";
        Group = "agent";
        WorkingDirectory = "/home/agent/work";
        Restart = "always";
        RestartSec = 30;
        Slice = "agent.slice";
        NoNewPrivileges = true; # no setuid helpers (qemu-bridge-helper, F4)
        PrivateTmp = true;
        # a private /dev with only the pseudo devices, plus the GPU and KVM
        # bound in; /dev/net/tun stays out (F4), and the device cgroup
        # refuses the display (card*) and iGPU nodes /dev/dri also carries
        PrivateDevices = true;
        BindPaths = [
          "-/dev/kvm"
          "-/dev/kfd" # ROCm compute
          "-/dev/dri"
        ];
        DeviceAllow = [
          "/dev/kvm rw"
          "/dev/kfd rw"
          "${agentGpu} rw"
        ];
        SupplementaryGroups = [
          "kvm"
          "render"
        ];
        ProtectSystem = "strict";
        ReadWritePaths = [ "/home/agent" ];
        # world-writable daemon sockets: VPN, tailnet and VM control (F5)
        InaccessiblePaths = [
          "-/run/mullvad-vpn"
          "-/run/tailscale"
          "-/run/libvirt"
        ];
      };
      agentEnvironment = {
        HOME = "/home/agent";
        PATH = lib.mkForce "/run/wrappers/bin:/etc/profiles/per-user/agent/bin:/run/current-system/sw/bin";
      };
      # stop with the firewall: a stopped or failed firewall drops agent-egress
      agentUnitDeps = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        bindsTo = [ "firewall.service" ];
        after = [
          "network-online.target"
          "firewall.service"
        ];
      };
      claudeEnvironment = agentEnvironment // {
        # keep the account's claude.ai connectors (and their data) out
        ENABLE_CLAUDEAI_MCP_SERVERS = "false";
      };
      # an unattended Claude run in the agent sandbox; the prompt is a file
      # in ./agent-jobs, so a job changes only through a reviewed PR
      agentJob = description: prompt: {
        inherit description;
        inherit (agentUnitDeps) wants bindsTo after;
        unitConfig.ConditionPathExists = "/home/agent/.claude/.credentials.json";
        environment = claudeEnvironment;
        serviceConfig =
          builtins.removeAttrs agentSandbox [
            "Restart"
            "RestartSec"
          ]
          // {
            Type = "oneshot";
            StandardInput = "file:${prompt}";
            # one job at a time: they share the vault reports and the nixOS
            # checkout, and two timers can fire together after downtime
            ExecStart = "${pkgs.util-linux}/bin/flock /home/agent/.agent-jobs.lock ${pkgs.claude-code}/bin/claude -p --permission-mode bypassPermissions";
            # includes waiting on the lock behind the other jobs
            TimeoutStartSec = "18h";
          };
      };
      # codex app-server is the remote-control host; the managed daemon
      # (`codex remote-control start`) refuses a nix-packaged CLI
      codexRemote = pkgs.writeShellScript "codex-remote-control" ''
        exec ${pkgs.codex}/bin/codex app-server < <(
          printf '%s\n' \
            '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-remote-control","version":"1"},"capabilities":{"experimentalApi":true}}}' \
            '{"jsonrpc":"2.0","method":"initialized"}' \
            '{"jsonrpc":"2.0","id":2,"method":"remoteControl/enable","params":{"ephemeral":true}}'
          exec sleep infinity
        )
      '';
      # agent-egress rules per family; IPv6 rejects all but loopback
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
      # lilijoy opens and drops files in ~/work; the agent gains nothing from this
      users.users.lilijoy.extraGroups = [ "agent" ];
      users.users.agent = {
        isNormalUser = true;
        group = "agent";
        # traverse only: lilijoy reaches ~/work, nothing else here
        homeMode = "711";
        description = "Claude agent (non-sensitive work)";
        packages = with pkgs; [
          git
          gh
          webFetch
        ];
      };

      # no inbound ssh
      services.openssh.settings.DenyUsers = [ "agent" ];

      # nix daemon access, not trusted-users
      environment.systemPackages = [ agentSetup ];

      nix.settings.allowed-users = [ "agent" ];

      # agent-egress: jumped from OUTPUT for uid agent and gid nixbld (every
      # user's sandboxed builds, lilijoy's included)
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
      system.fsPackages = [ pkgs.bindfs ];
      systemd = {
        # claude remote-control server: prompt-free sessions spawned in ~/work
        # merge the keys this repo owns into the agent's CLI-owned settings.json
        services.claude-agent-settings = {
          description = "Merge repo-owned keys into the agent's Claude settings";
          wantedBy = [ "multi-user.target" ];
          before = [ "claude-remote-control.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "agent";
            Group = "agent";
          };
          script =
            let
              managed = pkgs.writeText "agent-claude-settings.json" (
                builtins.toJSON {
                  # account-level session and routine tools (cloud work with the
                  # user's GitHub App and connectors)
                  deniedMcpServers = [ { serverName = "claude-code-remote"; } ];
                  disableClaudeAiConnectors = true;
                  # no AI attribution in commits or PRs, as in the user's own settings
                  attribution = {
                    commit = "";
                    pr = "";
                    sessionUrl = false;
                  };
                  # OpenAI's codex plugin, as in the user's own settings
                  extraKnownMarketplaces.openai-codex.source = {
                    source = "github";
                    repo = "openai/codex-plugin-cc";
                  };
                  enabledPlugins."codex@openai-codex" = true;
                  # keep session transcripts ~forever (default deletes after 30 days; 0 is rejected)
                  cleanupPeriodDays = 36500;
                  # the built-in twins: routines and messages into the user's sessions
                  permissions.deny = [
                    "RemoteTrigger"
                    "SendMessage"
                  ];
                  # always bypass: the app can't offer it, and its "auto" pick is refused
                  permissions.defaultMode = "bypassPermissions";
                  permissions.disableAutoMode = "disable";
                  skipDangerousModePermissionPrompt = true;
                  # the machine's full resources, as the agents' instructions grant
                  workflowSizeGuideline = "unrestricted";
                  # unattended sessions wait out a usage limit instead of stalling
                  autoContinueAtUsageLimit = true;
                }
              );
            in
            ''
              f=/home/agent/.claude/settings.json
              mkdir -p /home/agent/.claude
              [ -s "$f" ] || echo '{}' > "$f"
              ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$f" ${managed} > "$f.tmp"
              mv "$f.tmp" "$f"
            '';
        };

        services.claude-remote-control = agentUnitDeps // {
          description = "Claude Code Remote Control server for the agent user";
          # skipped until the one-time `claude auth login`
          unitConfig.ConditionPathExists = "/home/agent/.claude/.credentials.json";
          environment = claudeEnvironment;
          serviceConfig = agentSandbox // {
            ExecStart = "${pkgs.claude-code}/bin/claude remote-control --spawn same-dir --name torrent-agent --permission-mode bypassPermissions";
          };
        };

        # merge the keys this repo owns into the agent's CLI-owned config.toml
        services.codex-agent-config = {
          description = "Merge repo-owned keys into the agent's Codex config";
          wantedBy = [ "multi-user.target" ];
          before = [ "codex-remote-control.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "agent";
            Group = "agent";
          };
          script =
            let
              managed = pkgs.writeText "agent-codex-config.json" (
                builtins.toJSON {
                  # no prompts and no inner sandbox, as Claude's bypassPermissions;
                  # the Unix user and its units are the boundary
                  sandbox_mode = "danger-full-access";
                  approval_policy = "never";
                }
              );
            in
            ''
              f=/home/agent/.codex/config.toml
              mkdir -p /home/agent/.codex
              cur=$(mktemp)
              if [ -s "$f" ]; then
                ${pkgs.remarshal}/bin/toml2json "$f" > "$cur"
              else
                echo '{}' > "$cur"
              fi
              ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$cur" ${managed} \
                | ${pkgs.remarshal}/bin/json2toml > "$f.tmp"
              rm -f "$cur"
              chmod 600 "$f.tmp"
              mv "$f.tmp" "$f"
            '';
        };

        services.codex-remote-control = agentUnitDeps // {
          description = "Codex remote control host for the agent user";
          # skipped until the one-time `codex login` (pairing: agent-setup)
          unitConfig.ConditionPathExists = "/home/agent/.codex/auth.json";
          environment = agentEnvironment;
          serviceConfig = agentSandbox // {
            ExecStart = codexRemote;
            # the app-server's JSON-RPC replies and notifications
            StandardOutput = "null";
          };
        };

        # scheduled jobs: Claude, by the owner's choice (more Claude usage),
        # one after another; each can also be started by hand
        services.agent-flake-update = agentJob "Weekly flake update and stable release move, as a PR" ./agent-jobs/flake-update.md;
        services.agent-security-watch = agentJob "Daily security research for the fleet, as a report and PRs" ./agent-jobs/security-watch.md;
        services.agent-maintenance =
          agentJob "Weekly maintenance: friction, to-dos, workarounds, forgotten work" ./agent-jobs/maintenance.md
          // {
            # last: sees the flake update's result and friction, and writes
            # the fleet status page
            after = agentUnitDeps.after ++ [ "agent-flake-update.service" ];
          };
        targets.agent-weekly = {
          description = "The agents' weekly scheduled jobs";
          # a target stays active otherwise, and the timer's next firing
          # would then start nothing
          unitConfig.StopWhenUnneeded = true;
          wants = [
            "agent-flake-update.service"
            "agent-maintenance.service"
          ];
        };
        # Monday just past midnight: the owner's weekly Claude usage resets
        # Sunday at 17:00, so the jobs spend the start of the week's limit;
        # Persistent catches up on a run missed while torrent was off
        timers.agent-weekly = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "Mon 00:15";
            Persistent = true;
            Unit = "agent-weekly.target";
          };
        };
        # security incidents move in hours (#140), so this one runs daily
        timers.agent-security-watch = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "06:00";
            Persistent = true;
          };
        };

        # one cap for both agents' sessions: a runaway agent can't take the
        # desktop down with it
        slices.agent.sliceConfig = {
          MemoryMax = "64G";
          TasksMax = 4096;
          CPUWeight = 50;
        };

        tmpfiles.rules = [
          # ~/work is shared with lilijoy (group agent); setgid + default acl keep
          # files group-writable whoever creates them, whatever their umask
          "d /home/agent/work 2770 agent agent -"
          "a+ /home/agent/work - - - - default:user::rwx,default:group::rwx,default:mask::rwx,default:other::---"
          # orientation for the agent; a store symlink, so edits go through the repo
          "d /home/agent/.claude 0700 agent agent -"
          # ~/.gitconfig stays writable: gh auth setup-git puts its helper there
          "d /home/agent/.config 0700 agent agent -"
          "d /home/agent/.config/git 0700 agent agent -"
          "L+ /home/agent/.config/git/config - - - - ${gitIdentity}"
          "L+ /home/agent/.config/git/ignore - - - - ${gitIgnore}"
          "L+ /home/agent/.claude/CLAUDE.md - - - - ${agentInstructions}"
          "d /home/agent/.codex 0700 agent agent -"
          "L+ /home/agent/.codex/AGENTS.md - - - - ${agentInstructions}"
          "d /home/agent/.claude/skills 0755 agent agent -"
          # codex's user skill directory
          "d /home/agent/.agents 0755 agent agent -"
          "d /home/agent/.agents/skills 0755 agent agent -"
        ]
        # the user's skills, from the same directory their home-manager links
        ++ lib.concatLists (
          lib.mapAttrsToList (name: _: [
            "L+ /home/agent/.claude/skills/${name} - - - - ${sharedSkills}/${name}"
            "L+ /home/agent/.agents/skills/${name} - - - - ${sharedSkills}/${name}"
          ]) (builtins.readDir sharedSkills)
        );

        # systemd mount + automount, not fileSystems
        # plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#G3
        mounts = [
          {
            what = "/home/lilijoy/Documents/Vault/Research";
            where = "/home/agent/research";
            type = "fuse.bindfs";
            options = "force-user=agent,force-group=agent,create-for-user=lilijoy,create-for-group=users";
            # no start limit: a missing source must not wedge the automount
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

# agent-user: unprivileged `agent` user on torrent for prompt-free agent work
{ config, ... }:
let
  # captured before the inner module's `config` shadows the flake-parts one
  agentInstructions = config.flake.agentInstructions;
  inherit (config.flake) agentHarnesses;
in
{
  # every agent harness: where it reads user-level instructions and skills,
  # and the few lines only it needs; adding or dropping an agent is one entry
  # here
  flake.agentHarnesses = {
    claude = {
      instructions = ".claude/CLAUDE.md";
      skills = ".claude/skills";
      tail = ''
        ## In Claude Code

        - Your shell's `grep` is ugrep and `find` is bfs; both reject some
          GNU syntax (see the `torrent-machine` skill).
      '';
    };
    codex = {
      instructions = ".codex/AGENTS.md";
      skills = ".agents/skills";
      tail = ''
        ## In Codex

        - You load a repo's `AGENTS.md` and `.agents/skills` only when your
          working directory is inside it: start there (`-C <repo>`), or
          read them yourself.
      '';
    };
    # also reads ~/.claude/skills and ~/.agents/skills; same-named skills load once
    opencode = {
      instructions = ".config/opencode/AGENTS.md";
      skills = ".config/opencode/skills";
      tail = ''
        ## In OpenCode

        - Your models come through the owner's OpenRouter key
          (`openrouter/<vendor>/<model>`, paid per token) or are OpenCode's own free
          `opencode/*` models, some of which may train on what you send:
          keep private material off those.
      '';
    };
    antigravity = {
      instructions = ".gemini/AGENTS.md";
      skills = ".gemini/config/skills";
      tail = ''
        ## In Antigravity

        - You run on a free Google account set aside for the agents, which
          has weekly limits; a long task can use up the week's quota.
      '';
    };
  };

  flake.modules.nixos."agent-user" =
    { lib, pkgs, ... }:
    let
      bot = "LilijoySkyseeker-agent";
      harnesses = agentHarnesses;
      # the goal, the user's working rule (the same file as their own
      # user-level instructions, so there's no copy to drift), the
      # orientation, then the harness's lines
      instructionsFor = agentInstructions.forHarness pkgs;
      # the user's skills (their own sessions link the same directory) and
      # the ones only about this sandbox
      skillDirs = [
        agentInstructions.ownerSkills
        agentInstructions.sandboxSkills
      ];
      # web-fetch: pages and feeds past bot walls (curl, curl-impersonate,
      # then real Chromium through nodriver in a virtual display)
      fetchPython = pkgs.python3.withPackages (ps: [
        ps.feedparser
        ps.nodriver
        ps.trafilatura
        ps.html2text
      ]);
      # web-fetch's curls decode whatever brotli a fetched server sends, and
      # brotli 1.2.0's decoder has an out-of-bounds write (CVE-2026-111497)
      # TODO: drop when NixOS/nixpkgs#577208 (brotli 1.2.1) is in nixos-unstable
      fetchCurl = pkgs.curl.override {
        brotli = pkgs.brotli.overrideAttrs {
          version = "1.2.1";
          src = pkgs.fetchFromGitHub {
            owner = "google";
            repo = "brotli";
            tag = "v1.2.1";
            hash = "sha256-llY72cYffDv0ugsH0p89xIPEbElV4L8u7U/Fe8hT3gI=";
          };
        };
      };
      # curl-impersonate builds its own static brotli from a tarball
      # TODO: drop when nixos-unstable's curl-impersonate is 2.3.1 or later (lexiforest/curl-impersonate#357)
      fetchCurlImpersonate = pkgs.curl-impersonate.overrideAttrs (old: {
        postPatch = old.postPatch + ''
          substituteInPlace CMakeLists.txt \
            --replace-fail '${old.passthru.deps."brotli-1.2.0.tar.gz"}' '${
              pkgs.fetchurl {
                url = "https://github.com/google/brotli/archive/refs/tags/v1.2.1.tar.gz";
                hash = "sha256-mNNdEaeNxFOuu30Qw3SPP3P/eMgmfA3Gl7hjH2e/fo8=";
              }
            }' \
            --replace-fail 816c96e8e8f193b40151dad7e8ff37b1221d019dbcb9c35cd3fadbfe6477dfec \
              98d35d11a78dc453aebb7d10c3748f3f73ff78c8267c0dc697b8631f67bf7e8f
        '';
      });
      webFetch = pkgs.writeShellApplication {
        name = "web-fetch";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          fetchCurl
          fetchCurlImpersonate
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
      # cloud media and model calls with the owner's OpenRouter key
      openrouterCurl = pkgs.writeShellApplication {
        name = "openrouter-curl";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
        ];
        text = builtins.readFile ./agent-tools/openrouter-curl.sh;
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
      # sandbox shared by every agent's units: every agent
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
      # how each harness runs an unattended job: its environment, the login
      # it needs, and its command reading the prompt on stdin
      jobHarnesses = {
        claude = {
          environment = claudeEnvironment;
          login = "/home/agent/.claude/.credentials.json";
          command = "${pkgs.claude-code}/bin/claude -p --permission-mode bypassPermissions";
        };
        codex = {
          environment = agentEnvironment;
          login = "/home/agent/.codex/auth.json";
          command = "${pkgs.codex}/bin/codex exec --skip-git-repo-check -C /home/agent/work -";
        };
      };
      # an unattended run in the agent sandbox; the prompt is a file in
      # ./agent-jobs, so a job changes only through a reviewed PR
      agentJobWith = harness: description: prompt: {
        inherit description;
        inherit (agentUnitDeps) wants bindsTo after;
        inherit (harness) environment;
        serviceConfig =
          builtins.removeAttrs agentSandbox [
            "Restart"
            "RestartSec"
          ]
          // {
            Type = "oneshot";
            StandardInput = "file:${prompt}";
            # fail, not skip, so a logged-out agent pages as a failed unit
            ExecStartPre = "${pkgs.coreutils}/bin/test -e ${harness.login}";
            # one job at a time: they share the vault reports and the nixOS
            # checkout, and two timers can fire together after downtime
            ExecStart = "${pkgs.util-linux}/bin/flock /home/agent/.agent-jobs.lock ${harness.command}";
            # includes waiting on the lock behind the other jobs
            TimeoutStartSec = "18h";
          };
      };
      # the scheduled jobs' default harness (see them below)
      agentJob = agentJobWith jobHarnesses.claude;
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
          openrouterCurl
          # the agent-only harnesses (claude and codex come with the PC profile)
          opencode
          antigravity-cli
        ];
      };

      # opencode runs on the bun it's built with, and bun 1.4.2 bundles the
      # brotli out-of-bounds write and trusts the eMudhra intermediates
      # (GHSA-663w-cv8g-jj2p, GHSA-26q8-h657-pf84); only the build's bun changes,
      # so the node_modules hash stays
      # TODO: drop when NixOS/nixpkgs#577354 (bun 1.4.4) is in nixos-unstable
      nixpkgs.overlays = [
        (_: prev: {
          opencode = prev.opencode.overrideAttrs (old: {
            nativeBuildInputs = lib.remove prev.bun old.nativeBuildInputs ++ [
              (prev.bun.overrideAttrs {
                version = "1.4.4";
                src = prev.fetchurl {
                  url = "https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-x64-baseline.zip";
                  hash = "sha256-4ERutVmVdy65iUvrrppr42jZhai5Jx7hJEhvmUbu3XY=";
                };
              })
            ];
          });
        })
      ];

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
                  # no codex plugin: the agents call each other's own CLIs
                  # (other-agents skill); off where it's still installed
                  enabledPlugins."codex@openai-codex" = false;
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
                  # notes go in AGENTS.local.md, where every agent reads them
                  autoMemoryEnabled = false;
                  # only skills that can't work here: no browser pane, desktop,
                  # docs connector or cloud routines (RemoteTrigger is denied),
                  # and /init writes the CLAUDE.md the agents must not have
                  skillOverrides = {
                    "built-in-browser" = "off";
                    "chrome-browser" = "off";
                    "computer-use" = "off";
                    docs = "off";
                    schedule = "off";
                    init = "off";
                  };
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
                  # notes go in AGENTS.local.md, where every agent reads them
                  features.memories = false;
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

        # merge the keys this repo owns into the agent's opencode.json
        services.opencode-agent-config = {
          description = "Merge repo-owned keys into the agent's OpenCode config";
          wantedBy = [ "multi-user.target" ];
          before = [ "paseo.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "agent";
            Group = "agent";
          };
          script =
            let
              managed = pkgs.writeText "agent-opencode-config.json" (
                builtins.toJSON {
                  "$schema" = "https://opencode.ai/config.json";
                  # no prompts, as the other harnesses; the Unix user is the boundary
                  permission = "allow";
                  # a share is a public opencode.ai link to the session
                  share = "disabled";
                  # nix owns the binary
                  update = "disable";
                  # the key agent-setup writes, shared with openrouter-curl;
                  # 2.0.32 ignores it in the newer `providers.*.settings` form
                  provider.openrouter.options.apiKey = "{file:/home/agent/.config/openrouter/key}";
                }
              );
            in
            ''
              f=/home/agent/.config/opencode/opencode.json
              mkdir -p /home/agent/.config/opencode
              [ -s "$f" ] || echo '{}' > "$f"
              ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$f" ${managed} > "$f.tmp"
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

        # one cap for every agent's sessions: a runaway agent can't take the
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
          "d /home/agent/.codex 0700 agent agent -"
          # codex's user skill directory lives under it
          "d /home/agent/.agents 0755 agent agent -"
          # parents of opencode's and antigravity's files, which tmpfiles
          # would otherwise create as root
          "d /home/agent/.config/opencode 0700 agent agent -"
          # the owner's OpenRouter key, written by agent-setup
          "d /home/agent/.config/openrouter 0700 agent agent -"
          "d /home/agent/.gemini 0700 agent agent -"
          "d /home/agent/.gemini/config 0700 agent agent -"
          # the owner's full policies, read where decisions are made; the
          # instruction files point here
          "d /home/agent/.config/agents 0755 agent agent -"
          "L+ /home/agent/${agentInstructions.policiesPath} - - - - ${agentInstructions.policies}"
        ]
        # each harness's instructions and skill links
        ++ lib.concatLists (
          lib.mapAttrsToList (
            name: harness:
            [
              "L+ /home/agent/${harness.instructions} - - - - ${instructionsFor name harness}"
              "d /home/agent/${harness.skills} 0755 agent agent -"
            ]
            ++ lib.concatMap (
              dir:
              lib.mapAttrsToList (skill: _: "L+ /home/agent/${harness.skills}/${skill} - - - - ${dir}/${skill}") (
                builtins.readDir dir
              )
            ) skillDirs
          ) harnesses
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

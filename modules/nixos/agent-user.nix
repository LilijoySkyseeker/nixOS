# agent-user: unprivileged `agent` user on torrent for prompt-free agent work
{
  flake.modules.nixos."agent-user" =
    { lib, pkgs, ... }:
    let
      bot = "LilijoySkyseeker-agent";
      # every agent harness: where it reads user-level instructions and
      # skills; adding or dropping an agent is one entry here
      harnesses = {
        claude = {
          instructions = ".claude/CLAUDE.md";
          skills = ".claude/skills";
        };
        codex = {
          instructions = ".codex/AGENTS.md";
          skills = ".agents/skills";
        };
      };
      # orientation, then the user's working rule (the
      # same file as their own user-level CLAUDE.md, so there's no copy to
      # drift)
      instructionsFor =
        name:
        pkgs.writeText "agent-${name}-AGENTS.md" (
          builtins.readFile ./agent-user-AGENTS.md
          + "\n"
          + builtins.readFile ../home-manager/claude-code/user-claude.md
        );
      # the user's skills (their own sessions link the same directory) and
      # the ones only about this sandbox
      skillDirs = [
        ../home-manager/claude-code/skills
        ./agent-skills
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
      # git identity: the bot's noreply address (its public GitHub id); gh
      # from PATH as the credential helper, since `gh auth setup-git` writes a
      # store path that the GC later removes
      gitIdentity = pkgs.writeText "agent-git-identity" ''
        [user]
          name = ${bot}
          email = 338765425+${bot}@users.noreply.github.com
        [credential "https://github.com"]
          helper =
          helper = !gh auth git-credential
      '';
      # trust the nixOS repo's .envrc in every clone and worktree of it
      # (a string prefix: nixOS-* matches too), so each new worktree has its
      # dev shell and hook tools without a `direnv allow`
      direnvConfig = pkgs.writeText "agent-direnv.toml" ''
        [whitelist]
        prefix = [ "/home/agent/work/repos/nixOS" ]
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
        ''
        + builtins.readFile ./agent-setup.sh;
      };
      # torrent's RX 7900 XTX, by PCI path: DRM numbering follows probe order
      agentGpu = "/dev/dri/by-path/pci-0000:03:00.0-render";
      # sandbox shared by every agent's units: every agent
      # session is a child of one of them
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
        PATH = lib.mkForce "/run/wrappers/bin:/etc/profiles/per-user/agent/bin:/run/current-system/sw/bin";
      };
      # stop with the firewall: a failed firewall start can leave agent-egress
      # half-built
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
      # the agents' unit sandbox, which Paseo's unit (local-ai) runs in
      _module.args.agentUnit = agentUnitDeps // {
        environment = claudeEnvironment;
        serviceConfig = agentSandbox;
      };

      # own group, not isNormalUser's default `users`
      users.groups.agent = { };
      # lilijoy opens and drops files in ~/work; the agent gains nothing from this
      users.users.lilijoy.extraGroups = [ "agent" ];
      users.users.agent = {
        isNormalUser = true;
        group = "agent";
        # traverse only: lilijoy reaches ~/work, nothing else here
        homeMode = "711";
        packages = [
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

      # bindfs: Vault/Research only, agent-owned on its side, lilijoy:users on disk
      system.fsPackages = [ pkgs.bindfs ];
      systemd = {
        # merge the keys this repo owns into the agent's CLI-owned settings.json
        services.claude-agent-settings = {
          description = "Merge repo-owned keys into the agent's Claude settings";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "agent";
            Group = "agent";
          };
          script =
            let
              # answers a permission prompt with allow, in bypass mode only;
              # other modes keep their prompts
              allowPermission = pkgs.writeShellScript "claude-allow-in-bypass" ''
                ${lib.getExe pkgs.jq} -e '.permission_mode == "bypassPermissions"' > /dev/null || exit 0
                echo ${
                  lib.escapeShellArg (
                    builtins.toJSON {
                      hookSpecificOutput = {
                        hookEventName = "PermissionRequest";
                        decision.behavior = "allow";
                      };
                    }
                  )
                }
              '';
              managed = pkgs.writeText "agent-claude-settings.json" (
                builtins.toJSON {
                  disableClaudeAiConnectors = true;
                  # no AI attribution in commits or PRs, as in the user's own settings
                  attribution = {
                    commit = "";
                    pr = "";
                    sessionUrl = false;
                  };
                  # keep session transcripts ~forever (default deletes after 30 days; 0 is rejected)
                  cleanupPeriodDays = 36500;
                  # the built-in twins: routines and messages into the user's sessions
                  permissions.deny = [
                    "RemoteTrigger"
                    "SendMessage"
                  ];
                  # the machine's full resources, as the agents' instructions grant
                  workflowSizeGuideline = "unrestricted";
                  # bypass mode still asks before an rm it can't rule out as
                  # dangerous; in Paseo that prompt stalls unattended work
                  hooks.PermissionRequest = [
                    {
                      matcher = "Bash|Monitor";
                      hooks = [
                        {
                          type = "command";
                          command = "${allowPermission}";
                        }
                      ];
                    }
                  ];
                  # notes go in AGENTS.local.md, where every agent reads them
                  autoMemoryEnabled = false;
                  # claude.ai skills that can't work here: no browser pane, desktop,
                  # docs connector or cloud routines, and /init writes the CLAUDE.md
                  # the agents must not have
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

        # merge the keys this repo owns into the agent's CLI-owned config.toml
        services.codex-agent-config = {
          description = "Merge repo-owned keys into the agent's Codex config";
          wantedBy = [ "multi-user.target" ];
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
                  # Codex is the cross-family reviewer: Sol for the Plus quota,
                  # high because correctness comes first
                  model = "gpt-6.1-sol";
                  model_reasoning_effort = "high";
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

        # one cap for every agent's sessions: a runaway agent can't take the
        # desktop down with it
        slices.agent.sliceConfig = {
          MemoryMax = "64G";
          CPUWeight = 50;
        };

        tmpfiles.rules = [
          # ~/work is shared with lilijoy (group agent); setgid + default acl keep
          # files group-writable whoever creates them, whatever their umask
          "d /home/agent/work 2770 agent agent -"
          "a+ /home/agent/work - - - - default:user::rwx,default:group::rwx,default:mask::rwx,default:other::---"
          # cold reads: Codex with no instructions, skills or config, only its own
          # login (see other-agents); it refuses a CODEX_HOME that doesn't exist
          "d /home/agent/.cold 0700 agent agent -"
          "d /home/agent/.cold/.codex 0700 agent agent -"
          # orientation for the agent; a store symlink, so edits go through the repo
          "d /home/agent/.claude 0700 agent agent -"
          "d /home/agent/.config 0700 agent agent -"
          "d /home/agent/.config/git 0700 agent agent -"
          "L+ /home/agent/.config/git/config - - - - ${gitIdentity}"
          "L+ /home/agent/.config/git/ignore - - - - ${gitIgnore}"
          "d /home/agent/.config/direnv 0700 agent agent -"
          "L+ /home/agent/.config/direnv/direnv.toml - - - - ${direnvConfig}"
          "d /home/agent/.codex 0700 agent agent -"
          # codex's user skill directory lives under it
          "d /home/agent/.agents 0755 agent agent -"
        ]
        # each harness's instructions and skill links
        ++ lib.concatLists (
          lib.mapAttrsToList (
            name: harness:
            [
              "L+ /home/agent/${harness.instructions} - - - - ${instructionsFor name}"
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

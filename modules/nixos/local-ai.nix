# local-ai: torrent's local models for every agent and the user
# - llama-swap on 127.0.0.1:8080 loads one model at a time on the RX 7900 XTX
#   and kills it after 5 idle minutes, so all its VRAM comes back
# - /srv/models: the model store (zroot/local/models, replicated to homelab)
# - gamemode hook: a game unloads every model and blocks loads until it exits
# - paseo: one remote way into the agent sandbox for Claude, Codex or a local
#   model, tailnet-only through tailscale serve
_: {
  flake.modules.nixos."local-ai" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # TODO: drop when Paseo supports provider default modes: https://github.com/getpaseo/paseo/blob/main/docs/custom-providers.md
      paseo = pkgs.paseo.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./paseo/default-permissions.patch ];
      });
      models = "/srv/models";
      llamaServer = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";
      swapUrl = "http://127.0.0.1:${toString config.services.llama-swap.port}";
      # same card as agent-user's agentGpu: DRM numbering follows probe order
      gpu = "/dev/dri/by-path/pci-0000:03:00.0-render";

      # qwen's template raises on a system message after the first, which
      # claude code sends mid-conversation; this one renders it as a system turn
      qwenTemplate = ./local-ai/qwen3.8-mid-system.jinja;

      modelIds = [
        "qwen3.8-27b"
      ];

      # gaming marker: survives a llama-swap restart mid-game, gone on reboot
      gamingMarker = "/run/local-ai/gaming";
      setGaming = pkgs.writeShellScript "local-ai-set-gaming" ''
        ${lib.getExe pkgs.curl} -s -m 4 -X PUT -H 'Content-Type: application/json' \
          -d '{"name":"gaming"}' ${swapUrl}/api/profiles/active
      '';

      # gamemode runs these as the user who started the game
      gamingStart = pkgs.writeShellScript "local-ai-gaming-start" ''
        touch ${gamingMarker} || true
        # block loads first, so nothing reloads behind the unload
        ${lib.getExe pkgs.curl} -s -m 4 -X PUT -H 'Content-Type: application/json' \
          -d '{"name":"gaming"}' ${swapUrl}/api/profiles/active || true
        ${lib.getExe pkgs.curl} -s -m 14 -X POST ${swapUrl}/api/models/unload || true
      '';
      gamingEnd = pkgs.writeShellScript "local-ai-gaming-end" ''
        rm -f ${gamingMarker}
        ${lib.getExe pkgs.curl} -s -m 4 -X PUT -H 'Content-Type: application/json' \
          -d '{"name":null}' ${swapUrl}/api/profiles/active || true
      '';

      # repo-owned keys merged into the agent's ~/.paseo/config.json; the
      # daemon password's bcrypt hash comes from the host's sops secret, never here
      paseoManaged = pkgs.writeText "paseo-managed.json" (
        builtins.toJSON {
          "$schema" = "https://paseo.sh/schemas/paseo.config.v1.json";
          version = 1;
          daemon = {
            listen = "127.0.0.1:6767";
            # tailscale serve forwards this Host; ip and localhost are allowed by default
            hostnames = [ "torrent.taila4ae6c.ts.net" ];
            # explicit: a config that omits it keeps the legacy relay-on behavior
            relay.enabled = false;
          };
          features.webUi.enabled = true;
          log.file.level = "info";
          agents.providers = {
            # the same binaries the other agent units run
            claude.command = [ (lib.getExe pkgs.claude-code) ];
            codex.command = [ (lib.getExe pkgs.codex) ];
            # enabled outright: the merge keeps an earlier `enabled = false`
            opencode = {
              enabled = true;
              command = [ (lib.getExe pkgs.opencode) ];
            };
            antigravity = {
              enabled = true;
              command = [ (lib.getExe pkgs.antigravity-cli) ];
            };
            local-codex = {
              extends = "codex";
              label = "Local";
              description = "A local model on torrent's GPU (llama-swap), in the Codex harness";
              env = {
                OPENAI_BASE_URL = swapUrl;
                OPENAI_API_KEY = "local";
              };
              models = [
                {
                  id = "qwen3.8-27b";
                  label = "Qwen3.8-27B (local)";
                  isDefault = true;
                }
              ];
            };
          }
          # bundled providers with no install here
          //
            lib.genAttrs
              [
                "copilot"
                "pi"
                "muse"
                "omp"
              ]
              (_: {
                enabled = false;
              });
        }
      );

      # the hash paseo-agent-config writes from the host's sops secret
      paseoHasPassword = pkgs.writeShellScript "paseo-has-password" ''
        exec ${lib.getExe pkgs.jq} -e '.daemon.auth.password | strings | startswith("$2")' /home/agent/.paseo/config.json
      '';

      # the agent's sessions write models; privilege on the units, not the user
      agentModelAccess = {
        ReadWritePaths = [ models ];
        SupplementaryGroups = [ "models" ];
      };
      # paseo copies this unit's sandbox
      crc = config.systemd.services.claude-remote-control;
    in
    {
      # model store: the agent and lilijoy download into it, llama-swap reads it
      users.groups.models = { };
      users.users.lilijoy.extraGroups = [ "models" ];
      systemd.tmpfiles.rules = [
        "d ${models} 2775 root models -"
        # group-writable whoever creates a file, world-readable for llama-swap's dynamic user
        "a+ ${models} - - - - default:user::rwx,default:group::rwx,default:mask::rwx,default:other::r-x"
        # the gamemode hooks run as whoever plays
        "d /run/local-ai 1777 root root -"
      ];

      systemd.services.claude-remote-control.serviceConfig = agentModelAccess;
      systemd.services.codex-remote-control.serviceConfig = agentModelAccess;

      services.llama-swap = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 8080;
        settings = {
          # no stored request/response bodies: private prompts stay out of its api
          captureBuffer = 0;
          # only llama-swap's own ui may read responses in a browser; the
          # permissive default lets any web page read loopback (firefox has
          # no private network access check)
          security.cors.allowedOrigins = [
            "http://127.0.0.1:8080"
            "http://localhost:8080"
          ];
          globalTTL = 300;
          models = {
            "qwen3.8-27b" = {
              description = "Qwen3.8-27B, fully on the GPU, vision on the CPU";
              cmd = lib.concatStringsSep " " [
                llamaServer
                "--port \${PORT}"
                "-m ${models}/qwen3.8-27b/Qwen3.8-27B-UD-Q4_K_M.gguf"
                "--mmproj ${models}/qwen3.8-27b/mmproj-F16.gguf --no-mmproj-offload"
                "-ngl 99 -fa on -c 131072"
                "--jinja --chat-template-file ${qwenTemplate}"
              ];
            };
          };
          # one model on the GPU at a time
          routing.router = {
            use = "group";
            settings.groups.gpu = {
              swap = true;
              exclusive = true;
              members = modelIds;
            };
          };
          # the gamemode hook's profile: every model answers 404, so nothing loads
          profiles.gaming = {
            description = "a game has the GPU: no model loads";
            pins = lib.genAttrs modelIds (_: null);
          };
        };
      };

      systemd.services.llama-swap = {
        # the module leaves all of /dev open for GPU access; narrow it to the render node
        serviceConfig = {
          PrivateDevices = lib.mkForce true;
          BindPaths = [ "-/dev/dri" ];
          DeviceAllow = [ "${gpu} rw" ];
          SupplementaryGroups = [ "render" ];
          # bound model loading and CPU vision memory alongside the desktop
          MemoryMax = "80G";
          # loopback only: models come from /srv/models, never the network
          IPAddressAllow = "localhost";
          IPAddressDeny = "any";
          # a restart mid-game starts with no profile: reapply the block
          ExecStartPost = pkgs.writeShellScript "local-ai-restore-gaming" ''
            [ -e ${gamingMarker} ] || exit 0
            for _ in $(${pkgs.coreutils}/bin/seq 50); do
              ${setGaming} >/dev/null && exit 0
              ${pkgs.coreutils}/bin/sleep 0.2
            done
            exit 1
          '';
        };
      };

      # games have the GPU first
      programs.gamemode.settings.custom = {
        start = "${gamingStart}";
        end = "${gamingEnd}";
        script_timeout = 20;
      };

      # paseo: merge the keys this repo owns into the agent's CLI-owned config
      systemd.services.paseo-agent-config = {
        description = "Merge repo-owned keys into the agent's Paseo config";
        wantedBy = [ "multi-user.target" ];
        before = [ "paseo.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "agent";
          Group = "agent";
        };
        script = ''
          f=/home/agent/.paseo/config.json
          mkdir -p -m 700 /home/agent/.paseo
          [ -s "$f" ] || echo '{}' > "$f"
          # the local model runs only in the codex harness: drop the old claude one
          ${lib.getExe pkgs.jq} -s '(.[0] | del(.agents.providers.local)) * .[1]' "$f" ${paseoManaged} > "$f.tmp"
          # the password hash, from a paseo-password-hash credential the host
          # loads from sops; without one the file keeps whatever it has
          hash="''${CREDENTIALS_DIRECTORY:-}/paseo-password-hash"
          if [ -r "$hash" ]; then
            ${lib.getExe pkgs.jq} --rawfile h "$hash" '.daemon.auth.password = ($h | rtrimstr("\n"))' "$f.tmp" > "$f.tmp2"
            mv "$f.tmp2" "$f.tmp"
          fi
          chmod 600 "$f.tmp"
          mv "$f.tmp" "$f"
        '';
      };

      # the paseo daemon, in the same sandbox as the agents' remote-control units
      systemd.services.paseo = {
        description = "Paseo daemon: Claude, Codex and local-model sessions in the agent sandbox";
        inherit (crc) wantedBy wants bindsTo;
        after = crc.after ++ [ "paseo-agent-config.service" ];
        requires = [ "paseo-agent-config.service" ];
        environment = {
          inherit (crc.environment) ENABLE_CLAUDEAI_MCP_SERVERS;
          PATH = lib.mkForce crc.environment.PATH;
        };
        serviceConfig = crc.serviceConfig // {
          # without a password paseo grants owner rights to any client, and a
          # web page's websocket to loopback needs no cors: no password, no daemon
          ExecCondition = "${paseoHasPassword}";
          ExecStart = "${lib.getExe paseo} daemon run";
        };
      };

      # sends "continue" to an agent stopped on a usage limit once its quota is back
      # TODO: drop when Paseo resumes Claude and Codex agents after a usage limit itself: https://github.com/getpaseo/paseo/pull/7193
      systemd.services.paseo-resume = {
        description = "Resume Paseo agents after their usage limit resets";
        wantedBy = [
          "multi-user.target"
          "paseo.service"
        ];
        after = [ "paseo.service" ];
        bindsTo = [ "paseo.service" ];
        environment.HOME = "/home/agent";
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.nodejs} ${./paseo/resume-after-limit.mjs} ${paseo}/lib/paseo";
          Restart = "always";
          RestartSec = 30;
          User = "agent";
          Group = "agent";
          Slice = "agent.slice";
          # the daemon's local credential and the cli's client id
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [ "/home/agent/.paseo" ];
          PrivateTmp = true;
          PrivateDevices = true;
          NoNewPrivileges = true;
        };
      };

      # tailnet-only https in front of paseo; tailscaled (root) proxies to loopback,
      # which the agent's egress rules never see. never funnel
      systemd.services.paseo-tailscale-serve = {
        description = "Expose Paseo on the tailnet (tailscale serve, not funnel)";
        # after the config step has written the password, or the condition below
        # fails on a first boot and nothing retries it
        after = [
          "tailscaled.service"
          "tailscaled-autoconnect.service"
          "paseo-agent-config.service"
          "paseo.service"
        ];
        requires = [ "paseo-agent-config.service" ];
        wants = [ "tailscaled.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # never publish a paseo without its password (a fresh ~/.paseo has none)
          ExecCondition = "${paseoHasPassword}";
          ExecStart = "${lib.getExe config.services.tailscale.package} serve --bg --https=6767 http://127.0.0.1:6767";
          ExecStop = "${lib.getExe config.services.tailscale.package} serve --https=6767 off";
        };
      };
    };
}

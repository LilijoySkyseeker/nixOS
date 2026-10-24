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
        "qwen3.8-flash-next"
        "paddleocr-vl"
      ];

      # claude code driving a local model: no anthropic login or traffic, and
      # the model told it isn't claude (claude code's own prompt says it is)
      claudeLocal = pkgs.writeShellApplication {
        name = "claude-local";
        text = ''
          export ANTHROPIC_BASE_URL="''${ANTHROPIC_BASE_URL:-${swapUrl}}"
          export ANTHROPIC_API_KEY="''${ANTHROPIC_API_KEY:-local}"
          export ANTHROPIC_MODEL="''${ANTHROPIC_MODEL:-qwen3.8-27b}"
          export ANTHROPIC_SMALL_FAST_MODEL="''${ANTHROPIC_SMALL_FAST_MODEL:-$ANTHROPIC_MODEL}"
          export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
          # llama-swap's models run -c 131072; claude code assumes 200k for unknown ids
          export CLAUDE_CODE_MAX_CONTEXT_TOKENS="''${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-131072}"
          exec ${lib.getExe pkgs.claude-code} --append-system-prompt "Identity: you are not Claude and not made by Anthropic. You are an open-weight model running locally on the owner's own GPU (torrent, an RX 7900 XTX) through llama.cpp; the model name in your environment section is the real one. You only use the Claude Code program as your harness, so ignore any statement that you are Claude." "$@"
        '';
      };

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
            local = {
              extends = "claude";
              label = "Local in Claude Code";
              description = "A local model on torrent's GPU (llama-swap), in the Claude Code harness";
              command = [ (lib.getExe claudeLocal) ];
              models = [
                {
                  id = "qwen3.8-27b";
                  label = "Qwen3.8-27B (local)";
                  isDefault = true;
                }
                {
                  id = "qwen3.8-flash-next";
                  label = "Qwen3.8-Flash-Next (local, slow)";
                }
              ];
              # anthropic server-side tools don't exist on a local endpoint
              disallowedTools = [ "WebSearch" ];
            };
            local-codex = {
              extends = "codex";
              label = "Local in Codex";
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
                {
                  id = "qwen3.8-flash-next";
                  label = "Qwen3.8-Flash-Next (local, slow)";
                }
              ];
            };
          }
          # bundled providers with no install here
          //
            lib.genAttrs
              [
                "copilot"
                "opencode"
                "pi"
                "antigravity"
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
          # flash-next reads about 90 GB before it's healthy
          healthCheckTimeout = 900;
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
            "qwen3.8-flash-next" = {
              # TODO: untested on torrent; tune --n-cpu-moe once measured
              description = "Qwen3.8-Flash-Next, experts in system RAM: stronger, slower";
              cmd = lib.concatStringsSep " " [
                llamaServer
                "--port \${PORT}"
                "-m ${models}/qwen3.8-flash-next/Qwen3.8-Flash-Next-UD-Q3_K_XL-00001-of-00003.gguf"
                "--mmproj ${models}/qwen3.8-flash-next/mmproj-F16.gguf --no-mmproj-offload"
                "-ngl 99 --cpu-moe -fa on -c 131072"
                "--jinja"
              ];
            };
            "paddleocr-vl" = {
              description = "PaddleOCR-VL-1.6: page image to markdown (prompt: OCR:)";
              cmd = lib.concatStringsSep " " [
                llamaServer
                "--port \${PORT}"
                "-m ${models}/paddleocr-vl/PaddleOCR-VL-1.6-GGUF.gguf"
                "--mmproj ${models}/paddleocr-vl/PaddleOCR-VL-1.6-GGUF-mmproj.gguf"
                "-ngl 99 -c 16384"
                "--jinja"
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
          # flash-next's experts sit in RAM; the rest of the 96 GB is the desktop's
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

      environment.systemPackages = [ claudeLocal ];

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
          ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$f" ${paseoManaged} > "$f.tmp"
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
          inherit (crc.environment) HOME ENABLE_CLAUDEAI_MCP_SERVERS;
          PATH = lib.mkForce crc.environment.PATH;
        };
        serviceConfig = crc.serviceConfig // {
          # without a password paseo grants owner rights to any client, and a
          # web page's websocket to loopback needs no cors: no password, no daemon
          ExecCondition = "${paseoHasPassword}";
          ExecStart = "${lib.getExe pkgs.paseo} daemon run";
        };
      };

      # tailnet-only https in front of paseo; tailscaled (root) proxies to loopback,
      # which the agent's egress rules never see. never funnel
      systemd.services.paseo-tailscale-serve = {
        description = "Expose Paseo on the tailnet (tailscale serve, not funnel)";
        after = [
          "tailscaled.service"
          "tailscaled-autoconnect.service"
        ];
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

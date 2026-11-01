# local-ai: torrent's local models for every agent and the user
# - llama-swap on 127.0.0.1:8080 loads one model at a time on the RX 7900 XTX
#   and kills it after 5 idle minutes, so all its VRAM comes back
# - /srv/models: the model store (zroot/local/models, replicated to homelab)
# - gamemode hook: a game unloads every model and blocks loads until it exits
# - paseo: one remote way into the agent sandbox for Claude, Codex or a local
#   model, tailnet-only through tailscale serve; the agents' subagents and
#   scheduled jobs run in it too, so the owner sees them there
_: {
  flake.modules.nixos."local-ai" =
    {
      config,
      lib,
      pkgs,
      agentUnit,
      ...
    }:
    let
      # TODO: drop when Paseo supports provider default modes: https://github.com/getpaseo/paseo/blob/main/docs/custom-providers.md
      paseo = pkgs.paseo.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./paseo/default-permissions.patch
          # TODO: drop when getpaseo/paseo#7193 is in the packaged Paseo
          ./paseo/usage-limit-resume.patch
          # a limit-fallback profile (Claude API credits) while a provider is at its limit
          ./paseo/limit-fallback.patch
        ];
      });
      claudeApiCredits = pkgs.writeShellApplication {
        name = "claude-api-credits";
        runtimeInputs = [ pkgs.coreutils ];
        text = builtins.readFile ./paseo/claude-api-credits.sh;
      };
      paseoContinueOnCredits = pkgs.writeShellScriptBin "paseo-continue-on-credits" ''
        exec ${lib.getExe pkgs.nodejs} ${./paseo/continue-on-credits.mjs} ${paseo}/lib/paseo "$@"
      '';
      models = "/srv/models";
      llamaServer = lib.getExe' pkgs.llama-cpp-vulkan "llama-server";
      swapUrl = "http://127.0.0.1:${toString config.services.llama-swap.port}";

      # qwen's template raises on a system message after the first; this one
      # renders it as a system turn
      qwenTemplate = ./local-ai/qwen3.8-mid-system.jinja;

      gamingMarker = "/run/local-ai/gaming";

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
          daemon = {
            # tailscale serve forwards this Host; ip and localhost are allowed by default
            hostnames = [ "torrent.taila4ae6c.ts.net" ];
            # explicit: a config that omits it keeps the legacy relay-on behavior
            relay.enabled = false;
            # agents delegate with the `paseo` cli, one way for every harness
            mcp.injectIntoAgents = false;
          };
          features.webUi.enabled = false;
          agents.providers = {
            # the same binaries the other agent units run
            claude.command = [ (lib.getExe pkgs.claude-code) ];
            claude-api-credits = {
              extends = "claude";
              label = "Claude — API credits";
              description = "Use the included Console credits, separately from subscription usage";
              # Paseo patch limit-fallback.patch: used while the subscription is at
              # its limit, and its spend tracked against the plan's monthly credit
              limitFallback = true;
              creditBudget = {
                monthlyUsd = 100;
                # credits renew a day after the plan's billing date (owner, 2026-11-01)
                cycleDay = 2;
              };
              # Read only in the child process: no key in the Nix store or
              # Paseo's configuration, and no fallback to subscription login.
              command = [
                (lib.getExe claudeApiCredits)
                (lib.getExe pkgs.claude-code)
                # The service VM test has no sops module or host key.
                (config.sops.secrets.claude_api_key.path or "/run/secrets/claude_api_key")
              ];
            };
            codex.command = [ (lib.getExe pkgs.codex) ];
            local-codex = {
              extends = "codex";
              label = "Local";
              description = "A local model on torrent's GPU (llama-swap), in the Codex harness";
              # Scope these overrides to the local harness: cloud models keep
              # their own context budgets and timeouts. Compact well before
              # long image histories make prompt processing take minutes.
              # Allow 15 idle minutes for cold prefill instead of cancelling
              # and retrying it every five minutes.
              command = [
                (lib.getExe pkgs.codex)
                "-c"
                "model_context_window=131072"
                "-c"
                "model_auto_compact_token_limit=32768"
                "-c"
                "model_provider=local"
                "-c"
                "model_providers.local.name=Local"
                "-c"
                "model_providers.local.base_url=${swapUrl}/v1"
                "-c"
                "model_providers.local.wire_api=responses"
                "-c"
                "model_providers.local.env_key=OPENAI_API_KEY"
                "-c"
                "model_providers.local.stream_idle_timeout_ms=900000"
              ];
              env = {
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
          # providers removed from torrent: the merge keeps old keys, so their
          # live `enabled = true` must be overwritten
          //
            lib.genAttrs
              [
                "opencode"
                "antigravity"
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
      # the agents' scheduled jobs; a prompt changes only through a reviewed PR.
      # Mondays just past midnight: the owner's weekly Claude usage resets
      # Sunday at 17:00. Maintenance reads the flake update's result.
      agentJobs = [
        {
          name = "job:flake-update";
          cron = "15 0 * * 1";
          prompt = ./agent-jobs/flake-update.md;
        }
        {
          name = "job:maintenance";
          cron = "0 3 * * 1";
          prompt = ./agent-jobs/maintenance.md;
        }
        {
          # security incidents move in hours (#140)
          name = "job:security-watch";
          cron = "0 6 * * *";
          prompt = ./agent-jobs/security-watch.md;
        }
      ];
      agentJobsFile = pkgs.writeText "agent-jobs.json" (
        builtins.toJSON (map (j: j // { prompt = builtins.readFile j.prompt; }) agentJobs)
      );
      # makes the daemon's job:* schedules match agentJobs. It updates only
      # what differs, since a new cadence resets the next run and would drop
      # one missed while torrent was off. The owner's pause and archive switch
      # from the app stay; an edited prompt, time, provider or folder goes back
      agentSchedulesSync = pkgs.writeShellApplication {
        name = "agent-schedules-sync";
        runtimeInputs = [
          paseo
          pkgs.jq
        ];
        text = ''
          want=${agentJobsFile}
          tz=${config.time.timeZone}
          have=""
          for _ in $(seq 60); do
            have=$(paseo schedule ls --json 2>/dev/null) && break
            sleep 2
          done
          [ -n "$have" ] || { echo "paseo daemon not reachable" >&2; exit 1; }

          # job:* schedules no longer declared, and duplicates of declared ones
          jq -r --slurpfile want "$want" '
            [.[] | select((.name // "") | startswith("job:"))] | group_by(.name)[]
            | .[0].name as $n
            | if any($want[0][]; .name == $n) then .[1:][] else .[] end
            | .id' <<<"$have" | while read -r id; do
            paseo schedule delete "$id" >/dev/null
          done

          jq -c '.[]' "$want" | while read -r job; do
            name=$(jq -r .name <<<"$job")
            cron=$(jq -r .cron <<<"$job")
            prompt=$(jq -r .prompt <<<"$job")
            id=$(jq -r --arg n "$name" 'map(select(.name == $n))[0].id // empty' <<<"$have")
            if [ -z "$id" ]; then
              paseo schedule create --name "$name" --cron "$cron" --timezone "$tz" \
                --provider claude --cwd /home/agent/work "$prompt" >/dev/null
              continue
            fi
            cur=$(paseo schedule inspect "$id" --json)
            args=()
            [ "$(jq -r '.cadence.expression + " " + .cadence.timezone' <<<"$cur")" = "$cron $tz" ] \
              || args+=(--cron "$cron" --timezone "$tz")
            [ "$(jq -r .prompt <<<"$cur")" = "$prompt" ] || args+=(--prompt "$prompt")
            [ "$(jq -r '.target.config | .provider + " " + .cwd' <<<"$cur")" = "claude /home/agent/work" ] \
              || args+=(--provider claude --cwd /home/agent/work)
            [ ''${#args[@]} -eq 0 ] || paseo schedule update "$id" "''${args[@]}" >/dev/null
          done
        '';
      };
    in
    {
      # model store: the agent downloads into it, llama-swap reads it
      users.groups.models = { };
      systemd.tmpfiles.rules = [
        "d ${models} 0775 root models -"
        # the gamemode hooks run as whoever plays
        "d /run/local-ai 1777 root root -"
      ];

      services.llama-swap = {
        enable = true;
        settings = {
          # no stored request/response bodies: private prompts stay out of its api
          captureBuffer = 0;
          globalTTL = 300;
          models = {
            "qwen3.8-27b" = {
              cmd = lib.concatStringsSep " " [
                llamaServer
                "--port \${PORT}"
                "-m ${models}/qwen3.8-27b/Qwen3.8-27B-UD-Q4_K_M.gguf"
                "--mmproj ${models}/qwen3.8-27b/mmproj-F16.gguf"
                "-ngl 99 -c 131072"
                "--chat-template-file ${qwenTemplate}"
              ];
            };
          };
          # the gamemode hook's profile: every model answers 404, so nothing loads
          profiles.gaming = {
            pins = lib.genAttrs (lib.attrNames config.services.llama-swap.settings.models) (_: null);
          };
        };
      };

      systemd.services.llama-swap = {
        serviceConfig = {
          # loopback only: models come from /srv/models, never the network
          IPAddressAllow = "localhost";
          IPAddressDeny = "any";
        };
      };

      # games have the GPU first
      programs.gamemode.settings.custom = {
        start = "${gamingStart}";
        end = "${gamingEnd}";
      };

      # paseo: merge the keys this repo owns into the agent's CLI-owned config
      systemd.services.paseo-agent-config = {
        description = "Merge repo-owned keys into the agent's Paseo config";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "agent";
        };
        script = ''
          f=/home/agent/.paseo/config.json
          mkdir -p -m 700 /home/agent/.paseo
          [ -s "$f" ] || echo '{}' > "$f"
          ${lib.getExe pkgs.jq} -s '.[0] * .[1]' "$f" ${paseoManaged} > "$f.tmp"
          # the password hash, from a paseo-password-hash credential the host
          # loads from sops
          hash="''${CREDENTIALS_DIRECTORY:-}/paseo-password-hash"
          ${lib.getExe pkgs.jq} --rawfile h "$hash" '.daemon.auth.password = ($h | rtrimstr("\n"))' "$f.tmp" > "$f.tmp2"
          mv "$f.tmp2" "$f.tmp"
          mv "$f.tmp" "$f"
        '';
      };

      # the paseo daemon, in the same sandbox as the agents' units
      systemd.services.paseo = {
        description = "Paseo daemon: Claude, Codex and local-model sessions in the agent sandbox";
        inherit (agentUnit)
          wantedBy
          wants
          bindsTo
          environment
          ;
        after = agentUnit.after ++ [ "paseo-agent-config.service" ];
        requires = [ "paseo-agent-config.service" ];
        serviceConfig = lib.mkMerge [
          agentUnit.serviceConfig
          agentModelAccess
          {
            # without a password paseo grants owner rights to any client, and a
            # web page's websocket to loopback needs no cors: no password, no daemon
            ExecCondition = "${paseoHasPassword}";
            ExecStart = "${lib.getExe paseo} daemon run";
          }
        ];
      };

      # agents start subagents with `paseo run`
      users.users.agent.packages = [
        paseo
        paseoContinueOnCredits
      ];

      # the scheduled jobs live in the daemon, so each run shows in the app;
      # this unit declares them there again whenever they change
      systemd.services.agent-schedules = {
        description = "Declare the agents' scheduled jobs as Paseo schedules";
        wantedBy = [ "multi-user.target" ];
        wants = [ "paseo.service" ];
        after = [ "paseo.service" ];
        environment.HOME = "/home/agent";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "agent";
          Group = "agent";
          ExecStart = lib.getExe agentSchedulesSync;
        };
      };

      # sends "continue" to an agent stopped on a usage limit once its quota is back
      # TODO: drop when Paseo resumes Claude and Codex agents after a usage limit itself: https://github.com/getpaseo/paseo/pull/7193
      systemd.services.paseo-resume = {
        description = "Resume Paseo agents after their usage limit resets";
        # multi-user.target, so activation starts it while paseo is already running
        wantedBy = [ "multi-user.target" ];
        after = [ "paseo.service" ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.nodejs} ${./paseo/resume-after-limit.mjs} ${paseo}/lib/paseo";
          Restart = "always";
          RestartSec = 30;
          User = "agent";
        };
      };

      # tailnet-only https in front of paseo; tailscaled (root) proxies to loopback,
      # which the agent's egress rules never see. never funnel
      systemd.services.paseo-tailscale-serve = {
        description = "Expose Paseo on the tailnet (tailscale serve, not funnel)";
        # after the config step has written the password, or the condition below
        # fails on a first boot and nothing retries it
        after = [
          "tailscaled-autoconnect.service"
          "paseo-agent-config.service"
        ];
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

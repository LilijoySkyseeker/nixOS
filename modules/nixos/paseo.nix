# paseo: cloud agents in the shared sandbox, reached over the tailnet
_: {
  flake.modules.nixos."paseo" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
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

      # paseo copies this unit's sandbox
      crc = config.systemd.services.claude-remote-control;
    in
    {
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
          ${lib.getExe pkgs.jq} -s '(.[0] | del(.agents.providers.local, .agents.providers["local-codex"])) * .[1]' "$f" ${paseoManaged} > "$f.tmp"
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
        description = "Paseo daemon: Claude and Codex sessions in the agent sandbox";
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

{ ... }:
{
  flake.modules.nixos."tailscale-acl" =
    {
      config,
      lib,
      pkgs-unstable,
      ...
    }:
    let
      # OFF until the operator has done the three things only they can do:
      # created an OAuth client with the `policy_file` scope, put its
      # credentials in sops, and reconciled docs/tailscale-acl.json against
      # the live policy. Shipping this disabled is what lets the module land
      # and be reviewed before any of that happens -- and it has to be a
      # plain flag rather than "enable once the secret exists", because
      # sops-install-secrets validates every referenced key at *build* time,
      # so the secrets below cannot even be declared until they are real.
      # plan: 2026-09-15-manage-the-tailscale-acl-declaratively-and-unblock-vps-log-shipping.md#D1
      # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#G14
      enable = false;

      # The policy file is the repo's, in its native format. It stays under
      # docs/ rather than moving somewhere more config-shaped because the
      # 2026-08-26 audit reports and a rejected plan cite it by that path,
      # and everything under docs/audits/ and docs/plans/rejected/ is frozen
      # -- moving the file would mean editing frozen files to fix the
      # references, which ADR-0002 forbids outright.
      policyFile = ../../docs/tailscale-acl.json;

      # `-` resolves to the default tailnet of whoever the token belongs to,
      # so the tailnet's name never has to be hardcoded or kept in sync.
      api = "https://api.tailscale.com/api/v2";

      pushScript = pkgs-unstable.writeShellScript "tailscale-acl-push" ''
        set -euo pipefail

        curl=${pkgs-unstable.curl}/bin/curl
        jq=${pkgs-unstable.jq}/bin/jq

        # OAuth client credentials -> a one-hour token. Deliberately not an
        # API key: those expire every 90 days with no renewal, which for an
        # unattended unit means a silent failure a quarter after anyone last
        # looked at it.
        token=$("$curl" -sS --fail-with-body \
          -d "client_id=$TS_OAUTH_CLIENT_ID" \
          -d "client_secret=$TS_OAUTH_CLIENT_SECRET" \
          -d "grant_type=client_credentials" \
          "${api}/oauth/token" | "$jq" -er .access_token)

        # Read the live policy purely for its ETag. This is the interlock:
        # If-Match below makes the write fail if the live policy moved
        # between here and there, so a console edit made while this was
        # running is refused rather than silently overwritten.
        etag=$("$curl" -sS --fail-with-body -D - -o /dev/null \
          -H "Authorization: Bearer $token" \
          -H "Accept: application/hujson" \
          "${api}/tailnet/-/acl" \
          | tr -d '\r' | awk 'tolower($1) == "etag:" { print $2 }')

        if [ -z "$etag" ]; then
          echo "tailscale-acl: no ETag returned; refusing to push blind" >&2
          exit 1
        fi

        # Dry run first. This checks syntax *and* runs any `tests` /
        # `sshTests` blocks in the file server-side, so a policy that would
        # lock us out of our own hosts is rejected before it is applied
        # rather than after.
        "$curl" -sS --fail-with-body -X POST \
          -H "Authorization: Bearer $token" \
          -H "Content-Type: application/hujson" \
          --data-binary "@${policyFile}" \
          "${api}/tailnet/-/acl/validate" > /dev/null

        "$curl" -sS --fail-with-body -X POST \
          -H "Authorization: Bearer $token" \
          -H "Content-Type: application/hujson" \
          -H "If-Match: $etag" \
          --data-binary "@${policyFile}" \
          "${api}/tailnet/-/acl" > /dev/null

        echo "tailscale-acl: policy applied"
      '';
    in
    {
      config = lib.mkIf enable {
        users.users.tailscale-acl = {
          isSystemUser = true;
          group = "tailscale-acl";
        };
        users.groups.tailscale-acl = { };

        sops.secrets.tailscale_acl_oauth_client_id = {
          owner = "tailscale-acl";
          group = "tailscale-acl";
        };
        sops.secrets.tailscale_acl_oauth_client_secret = {
          owner = "tailscale-acl";
          group = "tailscale-acl";
        };
        sops.templates."tailscale-acl-env" = {
          owner = "tailscale-acl";
          group = "tailscale-acl";
          content = ''
            TS_OAUTH_CLIENT_ID=${config.sops.placeholder.tailscale_acl_oauth_client_id}
            TS_OAUTH_CLIENT_SECRET=${config.sops.placeholder.tailscale_acl_oauth_client_secret}
          '';
        };

        systemd.services.tailscale-acl-push = {
          description = "Push the declared tailnet policy file to the Tailscale API";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          # On change only, not on a clock. restartTriggers makes the unit's
          # definition depend on the policy file's store path, so switch-to-
          # configuration re-runs it exactly when the file's content differs
          # -- which means the tailnet's access policy moves when a reviewed
          # commit is deployed, the same way every other config in this repo
          # reaches the fleet, and never on its own in the background.
          # plan: 2026-09-15-manage-the-tailscale-acl-declaratively-and-unblock-vps-log-shipping.md#D1
          restartTriggers = [ "${policyFile}" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "tailscale-acl";
            Group = "tailscale-acl";
            EnvironmentFile = config.sops.templates."tailscale-acl-env".path;
            ExecStart = "${pushScript}";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            RestrictSUIDSGID = true;
            RemoveIPC = true;
            PrivateTmp = true;
          };
        };
      };
    };
}

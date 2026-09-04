{ ... }:
{
  flake.modules.nixos.couchdb =
    {
      config,
      lib,
      pkgs,
      vars,
      ...
    }:
    let
      enable = true;
      port = 5984;
      adminUser = "admin";
      # non-admin account the Obsidian LiveSync plugin actually authenticates
      # as on every client device -- kept separate from adminUser so a
      # leaked/rotated sync credential doesn't carry server-admin rights.
      syncUser = "obsidian-sync";
      vaultDb = "obsidian";

      # required server-side config, verified directly against the
      # Self-hosted LiveSync project's own setup docs, not assumption --
      # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#G3
      corsOrigins = "app://obsidian.md,capacitor://localhost,http://localhost";

      tailscaleBin = lib.getExe' config.services.tailscale.package "tailscale";
    in
    {
      config = lib.mkIf enable {
        # no wg0/vps involvement -- Tailscale-only per
        # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#D1
        # bind broad, restrict at the firewall (same shape as
        # modules/services/immich.nix's G3), not bindAddress = "127.0.0.1"
        # (the option's default), which would be unreachable from tailscale0
        services.couchdb = {
          enable = true;
          bindAddress = "0.0.0.0";
          inherit port adminUser;
          extraConfig = {
            chttpd = {
              require_valid_user = "true";
              enable_cors = "true";
              max_http_request_size = "4294967296"; # 4GiB, LiveSync's documented setting for large attachments
            };
            chttpd_auth.require_valid_user = "true";
            httpd = {
              enable_cors = "true";
              "WWW-Authenticate" = ''Basic realm="couchdb"'';
            };
            cors = {
              credentials = "true";
              origins = corsOrigins;
              headers = "accept, authorization, content-type, origin, referer";
            };
            couchdb.max_document_size = "50000000"; # 50MB, LiveSync's documented setting for large attachments
          };
          # keeps the admin password out of the Nix store entirely -- see
          # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#G1
          extraConfigFiles = [ config.sops.templates."couchdb-admins-ini".path ];
          # tmpfs, starts blank every boot -- CouchDB persists [admins]
          # hash changes into whatever configFile points at, which would
          # otherwise permanently shadow sops-rotated passwords
          # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#F1
          configFile = "/run/couchdb/local.ini";
        };

        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];

        environment.persistence.${vars.persistRoot}.directories = [
          # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#G4
          {
            directory = config.services.couchdb.databaseDir;
            user = "couchdb";
            group = "couchdb";
          }
        ];

        # upstream module hardens couchdb-provision-obsidian but not this
        # unit -- match its stack
        # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#F4
        systemd.services.couchdb.serviceConfig = {
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RestrictNamespaces = true;
          SystemCallArchitectures = "native";
          ReadWritePaths = [
            config.services.couchdb.databaseDir
            "/run/couchdb"
            "/var/log"
          ];
          # upstream never chmods local.ini (holds the admin hash, F1) --
          # tighten create mode for every file couchdb.service writes
          # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#F2
          UMask = "0077";
        };

        sops.secrets.homelab_couchdb_admin_password = {
          owner = "couchdb";
          group = "couchdb";
          restartUnits = [ "couchdb.service" ];
        };
        sops.templates."couchdb-admins-ini" = {
          owner = "couchdb";
          group = "couchdb";
          content = ''
            [admins]
            ${adminUser} = ${config.sops.placeholder.homelab_couchdb_admin_password}
          '';
        };

        sops.secrets.homelab_couchdb_sync_password = {
          owner = "couchdb";
          group = "couchdb";
          restartUnits = [ "couchdb-provision-obsidian.service" ];
        };

        # idempotent declarative bootstrap, run at every boot/switch, in
        # place of a one-time manual Fauxton-wizard step -- same shape as
        # modules/services/samba.nix's samba-user-provision. Creates
        # CouchDB's own system databases (not auto-created by the plain
        # module outside the Docker entrypoint's cluster-setup step -- see
        # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#G2),
        # the vault database, and a database-scoped sync user so client
        # devices never hold admin credentials.
        systemd.services.couchdb-provision-obsidian = {
          description = "CouchDB: bootstrap system/vault databases and the obsidian-sync user";
          after = [ "couchdb.service" ];
          requires = [ "couchdb.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "couchdb";
            Group = "couchdb";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            RestrictNamespaces = true;
            SystemCallArchitectures = "native";
          };
          script = ''
            set -euo pipefail
            base="http://127.0.0.1:${toString port}"
            admin_pass=$(cat ${lib.escapeShellArg config.sops.secrets.homelab_couchdb_admin_password.path})
            sync_pass=$(cat ${lib.escapeShellArg config.sops.secrets.homelab_couchdb_sync_password.path})
            auth="${adminUser}:$admin_pass"
            curl=${lib.getExe pkgs.curl}
            jq=${lib.getExe pkgs.jq}

            until "$curl" -sf -u "$auth" "$base/" >/dev/null; do sleep 1; done

            for db in _users _replicator _global_changes ${lib.escapeShellArg vaultDb}; do
              "$curl" -sf -u "$auth" -X PUT "$base/$db" >/dev/null || true
            done

            existing_rev=$("$curl" -sf -u "$auth" "$base/_users/org.couchdb.user:${syncUser}" 2>/dev/null | "$jq" -r '._rev // empty' || true)
            # jq-built, not string interpolation, so sync_pass can't corrupt/inject JSON
            # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#F3
            payload=$("$jq" -n --arg name ${lib.escapeShellArg syncUser} --arg pass "$sync_pass" --arg rev "$existing_rev" \
              '{name: $name, password: $pass, roles: [], type: "user"} + (if $rev == "" then {} else {_rev: $rev} end)')
            "$curl" -sf -u "$auth" -X PUT "$base/_users/org.couchdb.user:${syncUser}" \
              -H "Content-Type: application/json" \
              -d "$payload" >/dev/null

            # syncUser is a *database* admin of just this one db (not a
            # members.names entry) -- CouchDB restricts writing design
            # documents (_design/*) to database admins even for a db they're
            # otherwise a member of, and Self-hosted LiveSync writes design
            # documents during its own setup/rebuild flow. Confirmed live:
            # member-level access produced a 403 on exactly that step.
            # Still not a *server* admin -- can't touch other databases,
            # _users, or server config.
            "$curl" -sf -u "$auth" -X PUT "$base/${vaultDb}/_security" \
              -H "Content-Type: application/json" \
              -d "{\"admins\":{\"names\":[\"${syncUser}\"],\"roles\":[]},\"members\":{\"names\":[],\"roles\":[]}}" >/dev/null
          '';
        };

        # HTTPS for the LiveSync mobile client, tailnet-only (never
        # `tailscale funnel`, which goes public) -- terminates TLS inside
        # tailscaled itself using this tailnet's own HTTPS Certificates
        # feature and reverse-proxies to CouchDB's existing plain HTTP.
        # No firewall change: confirmed live that serve traffic never
        # touches the kernel netfilter path networking.firewall governs.
        # Runs as root: tailscaled's LocalAPI only grants a non-root caller
        # write access via a configured --operator=, which this fleet has
        # none of -- CapabilityBoundingSet below still pares root down to
        # just what a control-socket RPC needs.
        # plan: 2026-09-03-serve-couchdb-over-https-via-tailscale-serve-for-obsidian-mobile.md#F1,F2
        systemd.services.couchdb-tailscale-serve = {
          description = "CouchDB: expose over HTTPS via tailscale serve (tailnet-only)";
          # tailscaled-autoconnect ordering matches the upstream tailscale
          # module's own documented idiom for anything binding to a
          # Tailscale IP (see its tailscaled-set unit) -- nixos/modules/
          # services/networking/tailscale.nix, pinned nixpkgs-stable
          after = [
            "tailscaled.service"
            "tailscaled-autoconnect.service"
            "couchdb.service"
          ];
          requires = [
            "tailscaled.service"
            "couchdb.service"
          ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${tailscaleBin} serve --bg --https=443 http://127.0.0.1:${toString port}";
            ExecStop = "${tailscaleBin} serve --https=443 off";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            # root is required (see comment above), but a control-socket
            # RPC needs no Linux capability beyond ordinary DAC access --
            # plan: 2026-09-03-serve-couchdb-over-https-via-tailscale-serve-for-obsidian-mobile.md#F1
            CapabilityBoundingSet = [ "" ];
            RestrictNamespaces = true;
            SystemCallArchitectures = "native";
          };
        };
      };
    };
}

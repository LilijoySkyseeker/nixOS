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
    in
    {
      config = lib.mkIf enable {
        # no wg0/vps involvement -- Tailscale-only per
        # plan: 2026-09-03-self-host-obsidian-sync-via-couchdb-on-homelab.md#D1.
        # Bind broad, restrict at the firewall: same shape as
        # modules/services/immich.nix (G3 there), not
        # services.couchdb.bindAddress = "127.0.0.1" (its default), which
        # would make it unreachable from tailscale0 at all.
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
          # CouchDB always treats configFile (the last -couch_ini file) as
          # its one writable config target, and unconditionally re-hashes
          # + persists whatever [admins] password is currently active into
          # it on every boot -- which then permanently shadows
          # extraConfigFiles on every subsequent boot regardless of what
          # sops renders, silently defeating password rotation. Pointing
          # configFile at /run (tmpfs, never persisted -- already created
          # by this same module's own uriFile tmpfiles rule) means it
          # starts blank every boot, so the sops-templated password is
          # always what gets (re)hashed and takes effect. Trades away
          # CouchDB's own "persist runtime/Fauxton config changes" feature
          # for this database, which is fine here: this deployment is
          # Nix-declared already, so nothing is meant to be configured
          # through it.
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

        # couchdb.service itself has no hardening from the upstream module
        # beyond User/Group -- add the same stack couchdb-provision-obsidian
        # already gets below. Every path it writes is known: databaseDir/
        # viewIndexDir (both = databaseDir here), /run/couchdb (uriFile +
        # the now-ephemeral configFile, see F1), and logFile, already
        # covered by the plain /var/log persistence entry (G4).
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
          # local.ini persists the admin password's PBKDF2 hash (see F1) and
          # upstream never chmods it beyond a bare `touch` -- tighten the
          # default create mode for every file couchdb.service writes
          # rather than relying on the (world-executable-by-default)
          # directory mode alone.
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
            # built via jq (not manual "\"..\"" string interpolation) so a
            # sync_pass containing a `"` or `\` can't produce malformed or
            # attacker-shaped JSON.
            payload=$("$jq" -n --arg name ${lib.escapeShellArg syncUser} --arg pass "$sync_pass" --arg rev "$existing_rev" \
              '{name: $name, password: $pass, roles: [], type: "user"} + (if $rev == "" then {} else {_rev: $rev} end)')
            "$curl" -sf -u "$auth" -X PUT "$base/_users/org.couchdb.user:${syncUser}" \
              -H "Content-Type: application/json" \
              -d "$payload" >/dev/null

            "$curl" -sf -u "$auth" -X PUT "$base/${vaultDb}/_security" \
              -H "Content-Type: application/json" \
              -d "{\"admins\":{\"names\":[],\"roles\":[]},\"members\":{\"names\":[\"${syncUser}\"],\"roles\":[]}}" >/dev/null
          '';
        };
      };
    };
}

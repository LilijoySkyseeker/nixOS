_: {
  flake.modules.nixos.samba =
    { config, lib, ... }:
    {

      # SMB password from sops, applied to tdbsam by samba-user-provision below
      # so a rebuild-from-scratch needs no manual `smbpasswd -a`
      sops.secrets.homelab_samba_android_smb_password = {
        restartUnits = [ "samba-user-provision.service" ];
      };

      # samba: tailnet-only share of /storage and /storage-bulk for android (no
      # usable native NFS client); linux clients use nfs.nix

      # SMB-auth-only account, no shell/SSH; "multimedia" membership (jellyfin.nix)
      # grants filesystem access, matching NFS's gid-based auth
      users.users.android-smb = {
        isSystemUser = true;
        group = "multimedia";
        description = "SMB auth account for Android tailnet file access (no shell/SSH login)";
      };

      services.samba = {
        enable = true;
        # scoped to tailscale0 below; openFirewall would open every interface
        openFirewall = false;
        # no NetBIOS: android connects by tailnet hostname/IP; keeps 137-139 closed
        nmbd.enable = false;
        winbindd.enable = false; # no AD/domain integration

        settings = {
          global = {
            security = "user";
            "server min protocol" = "SMB3";
            "map to guest" = "never";
            "invalid users" = [ "root" ];
            "log level" = "1";
            # second layer on top of the tailscale0 firewall scoping below
            "hosts allow" = "100.64.0.0/10";
            "hosts deny" = "0.0.0.0/0";
            # defense-in-depth against a compromised tailnet peer or a
            # protocol downgrade, on top of WireGuard
            "server signing" = "mandatory";
            "smb encrypt" = "mandatory";
            "ntlm auth" = "ntlmv2-only";
            # no printer sharing; shrinks RPC attack surface
            "load printers" = false;
            "printing" = "bsd";
            "printcap name" = "/dev/null";
            "disable spoolss" = true;
          };
          storage = {
            path = "/storage";
            "valid users" = "android-smb";
            "read only" = false;
            "force group" = "multimedia";
            "create mask" = "0660";
            "directory mask" = "0770";
            browseable = true;
            # symlinks must not let a client escape the share
            "wide links" = false;
            "follow symlinks" = false;
          };
          "storage-bulk" = {
            path = "/storage-bulk";
            "valid users" = "android-smb";
            "read only" = false;
            "force group" = "multimedia";
            "create mask" = "0660";
            "directory mask" = "0770";
            browseable = true;
            "wide links" = false;
            "follow symlinks" = false;
          };
        };
      };

      # syncs android-smb's password from sops into passdb.tdb (add or update);
      # idempotent, rerun by restartUnits above when the secret changes
      systemd.services.samba-user-provision = {
        description = "Provision the android-smb Samba user's password from sops";
        after = [ "sops-nix.service" ];
        wants = [ "sops-nix.service" ];
        before = [ "samba-smbd.service" ];
        wantedBy = [ "samba.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # only reads a secret and calls two binaries, so full hardening
          # (unlike samba-smbd)
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
          # the only paths this script writes to
          ReadWritePaths = [
            "/var/lib/samba"
            "/var/cache/samba"
            "/var/log/samba"
            "/var/lock/samba"
          ];
        };
        script = ''
          pw=$(cat ${lib.escapeShellArg config.sops.secrets.homelab_samba_android_smb_password.path})
          if ${lib.getExe' config.services.samba.package "pdbedit"} -L 2>/dev/null | cut -d: -f1 | grep -qx android-smb; then
            printf '%s\n%s\n' "$pw" "$pw" | ${lib.getExe' config.services.samba.package "smbpasswd"} -s android-smb
          else
            printf '%s\n%s\n' "$pw" "$pw" | ${lib.getExe' config.services.samba.package "smbpasswd"} -s -a android-smb
          fi
        '';
      };
      systemd.services.samba-smbd = {
        after = [ "samba-user-provision.service" ];
        wants = [ "samba-user-provision.service" ];
      };

      # smbd must run as root (setuids to the authenticated user per operation);
      # no ProtectSystem=strict: a missed /var/*/samba path silently breaks
      # auth or logging
      systemd.services.samba-smbd.serviceConfig = {
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true; # no /home directories are served over SMB
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true; # blocks *creating* new suid/sgid files, not smbd's own setuid() calls
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
      };

      # tailnet only; just 445 since nmbd is disabled
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 445 ];

      # holds passdb.tdb, otherwise wiped by the impermanence rollback
      environment.persistence."/nix/state".directories = [
        "/var/lib/samba"
      ];
    };
}

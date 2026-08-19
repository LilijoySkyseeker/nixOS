{ config, lib, ... }:
{

  # declarative SMB password: sops-managed secret, applied into Samba's
  # own user db (tdbsam) idempotently at activation/boot by
  # samba-user-provision below, rather than a one-time manual
  # `smbpasswd -a` that impermanence would otherwise force you to redo
  # by hand on every host rebuild-from-scratch.
  sops.secrets.homelab_samba_android_smb_password = {
    restartUnits = [ "samba-user-provision.service" ];
  };

  # samba (SMB) — tailnet-only file share so Android (which has no usable
  # native NFS client) can reach /storage and /storage-bulk, the same
  # datasets exported over NFS for Linux clients in services/nfs.nix.
  # Linux clients are untouched; this is purely additive.

  # dedicated account used only for SMB auth — not a login/service user,
  # no shell, no SSH key. Membership in the existing "multimedia" group
  # (gid 999, defined in services/jellyfin.nix) is what actually grants
  # filesystem access, matching how NFS clients are authorized by gid.
  users.users.android-smb = {
    isSystemUser = true;
    group = "multimedia";
    description = "SMB auth account for Android tailnet file access (no shell/SSH login)";
  };

  services.samba = {
    enable = true;
    # scoped to tailscale0 below instead, matching nfs.nix's pattern —
    # openFirewall would open on every interface, including the LAN NIC.
    openFirewall = false;
    # NetBIOS browsing isn't needed — Android connects by tailnet
    # hostname/IP directly — and disabling it keeps 137/138/139 closed,
    # same "minimize the port surface" reasoning as nfs.nix going NFSv4-only.
    nmbd.enable = false;
    winbindd.enable = false; # no AD/domain integration

    settings = {
      global = {
        security = "user";
        "server min protocol" = "SMB3";
        "map to guest" = "never";
        "invalid users" = [ "root" ];
        "log level" = "1";
        # defense-in-depth on top of the tailscale0 firewall interface
        # scoping below — same belt-and-suspenders pattern as nfs.nix's
        # 100.64.0.0/10 export CIDR.
        "hosts allow" = "100.64.0.0/10";
        "hosts deny" = "0.0.0.0/0";
      };
      storage = {
        path = "/storage";
        "valid users" = "android-smb";
        "read only" = false;
        "force group" = "multimedia";
        "create mask" = "0660";
        "directory mask" = "0770";
        browseable = true;
      };
      "storage-bulk" = {
        path = "/storage-bulk";
        "valid users" = "android-smb";
        "read only" = false;
        "force group" = "multimedia";
        "create mask" = "0660";
        "directory mask" = "0770";
        browseable = true;
      };
    };
  };

  # idempotently syncs android-smb's Samba password from the sops secret
  # into passdb.tdb — add-if-missing, set-if-present, so it's safe to run
  # on every boot and every activation, and sops-nix's restartUnits above
  # re-runs it automatically whenever the secret's content changes.
  systemd.services.samba-user-provision = {
    description = "Provision the android-smb Samba user's password from sops";
    after = [ "sops-nix.service" ];
    wants = [ "sops-nix.service" ];
    before = [ "samba-smbd.service" ];
    wantedBy = [ "samba.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
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

  # smbd itself must keep running as root — it setuid/setgids to the
  # authenticated Unix user on every filesystem operation, which needs
  # real root privilege at the kernel level, not just group membership.
  # The upstream module gives it no user/group option (unlike jellyfin's),
  # so "dedicated service user, not root" isn't achievable here; trimming
  # what root-as-smbd is *allowed* to do is the available substitute.
  # These flags mirror the "always-safe, no filesystem-path guessing"
  # subset used for restic-backups-backblazeWeekly in this same file's
  # host config — no ProtectSystem=strict, since that would require
  # enumerating every /var/{lib,cache,log,lock}/samba path smbd touches
  # and getting one wrong silently breaks auth or logging.
  systemd.services.samba-smbd.serviceConfig = {
    NoNewPrivileges = true;
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

  # tailnet-only, same interface-scoping pattern as nfs.nix's port 2049
  # rule. Only 445 is needed since nmbd (137/138 udp, 139 tcp) is disabled.
  # (the "hosts allow"/"hosts deny" pair above is the second, smb.conf-level
  # layer of the same restriction.)
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 445 ];

  # /var/lib/samba holds the smbpasswd user database (private/passdb.tdb).
  # Without persisting it, android-smb's SMB password would be wiped by
  # the impermanence rollback and need re-adding after every boot.
  environment.persistence."/nix/state".directories = [
    "/var/lib/samba"
  ];
}

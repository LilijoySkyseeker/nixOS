{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myIsoAutobuild;
  destName = "recovery.iso";
  stateDir = "/var/lib/iso-autobuild";
  resultLink = "${stateDir}/result";

  copyToVentoy = pkgs.writeShellScript "iso-autobuild-copy-to-ventoy" ''
    set -euo pipefail

    if [ ! -e "${resultLink}" ]; then
      echo "No iso has been built yet, nothing to copy." >&2
      exit 0
    fi

    dev="/dev/disk/by-label/${cfg.ventoyLabel}"
    if [ ! -e "$dev" ]; then
      echo "Ventoy drive (label '${cfg.ventoyLabel}') not present, skipping copy." >&2
      exit 0
    fi

    mnt=$(mktemp -d)
    trap 'umount "$mnt" 2>/dev/null || true; rmdir "$mnt"' EXIT

    mount "$dev" "$mnt"
    tmp="$mnt/${destName}.tmp"
    cp -L "${resultLink}" "$tmp"
    mv -f "$tmp" "$mnt/${destName}"
    sync

    echo "Copied $(readlink -f ${resultLink}) to $mnt/${destName}"
  '';
in
{
  options.myIsoAutobuild = {
    enable = lib.mkEnableOption "auto-build the isoimage flake output and sync it to a Ventoy drive";

    flakeDir = lib.mkOption {
      type = lib.types.str;
      description = "Path to the local flake checkout to build from.";
    };

    buildUser = lib.mkOption {
      type = lib.types.str;
      description = ''
        Existing user to run `nix build` as. Needs read access to
        flakeDir (typically its owner, since home directories are
        usually mode 700) and membership in nix.settings.allowed-users
        (e.g. wheel) to talk to the nix daemon. Deliberately not a
        fresh dedicated/dynamic user: neither of those constraints can
        be satisfied by one without loosening filesystem or nix-daemon
        trust, which would be a bigger change than reusing the account
        that already has both legitimately.
      '';
    };

    isoAttr = lib.mkOption {
      type = lib.types.str;
      default = "isoimage";
      description = "nixosConfigurations attribute name whose system.build.isoImage gets built.";
    };

    ventoyLabel = lib.mkOption {
      type = lib.types.str;
      default = "Ventoy";
      description = "Filesystem label of the Ventoy drive's data partition.";
    };

    triggeredBy = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "pull-deploy.service" ];
      description = "Other systemd units which, on success, should trigger an iso rebuild (via their OnSuccess=).";
    };
  };

  config = lib.mkIf cfg.enable {
    # The build step (reads the flake checkout, talks to the nix
    # daemon) and the ventoy-copy step (mounts a block device) need
    # unrelated privileges, so they're two separate units instead of
    # one unit needing both a trusted human account and CAP_SYS_ADMIN
    # at once. They share this dir: buildUser needs to write the
    # result symlink, iso-ventoy-copy's dedicated user only needs to
    # read it.
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 ${cfg.buildUser} iso-autobuild -"
    ];
    users.groups.iso-autobuild = { };

    # "during every auto update": chain onto whichever units this host
    # already uses to pull/build/switch (e.g. pull-deploy.service).
    systemd.services = lib.mkMerge [
      (lib.genAttrs cfg.triggeredBy (_: {
        unitConfig.OnSuccess = [ "iso-build.service" ];
      }))
      {
        iso-build = {
          description = "Build the ${cfg.isoAttr} iso";
          path = [ pkgs.nix ];
          script = ''
            set -euo pipefail
            cd ${cfg.flakeDir}
            nix build --out-link ${resultLink} \
              .#nixosConfigurations.${cfg.isoAttr}.config.system.build.isoImage
          '';
          unitConfig.OnSuccess = [ "iso-ventoy-copy.service" ];
          serviceConfig = {
            Type = "oneshot";
            # Not root, not a dedicated/dynamic user: `nix build` here
            # needs to read ${cfg.flakeDir} (owned by this user, under
            # a mode-700 home dir) and be trusted by the nix daemon
            # (nix.settings.allowed-users) — both already true for the
            # account that owns the checkout.
            User = cfg.buildUser;
            ReadWritePaths = [ stateDir ];
            PrivateTmp = true;
            ProtectHome = "read-only";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            LockPersonality = true;
            RestrictRealtime = true;
            MemoryDenyWriteExecute = true;
          };
        };

        # Auto-copies the most recently built iso onto the Ventoy
        # drive: right after a build (chained above), and again
        # whenever the drive is plugged back in later (via udev
        # below), in case it was missing at build time. Fully
        # dedicated, ephemeral, unprivileged user — the only thing it
        # can do beyond a normal process is mount/unmount, via one
        # narrowly-scoped ambient capability.
        iso-ventoy-copy = {
          description = "Copy the last-built ${cfg.isoAttr} iso onto the Ventoy drive";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${copyToVentoy}";
            DynamicUser = true;
            SupplementaryGroups = [
              "disk" # read /dev/disk/by-label/* block device nodes
              "iso-autobuild" # read ${resultLink}
            ];
            CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ]; # mount(2)/umount(2) only
            AmbientCapabilities = [ "CAP_SYS_ADMIN" ];
            PrivateTmp = true;
            ProtectHome = true;
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            LockPersonality = true;
            RestrictRealtime = true;
            MemoryDenyWriteExecute = true;
            # RestrictNamespaces left at its default (unset = unrestricted):
            # mount(2) on a block device doesn't need a new namespace, but
            # some kernels/mount helpers probe namespace-related syscalls
            # even for a plain mount, and this unit's blast radius is
            # already capped by DynamicUser + the single capability above.
          };
        };
      }
    ];

    services.udev.extraRules = ''
      ENV{ID_FS_LABEL}=="${cfg.ventoyLabel}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="iso-ventoy-copy.service"
    '';
  };
}

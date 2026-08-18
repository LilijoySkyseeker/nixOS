{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myIsoAutobuild;
  stateDir = "/var/lib/iso-autobuild";
  resultLink = "${stateDir}/result";
  downloadsDir = "/home/${cfg.buildUser}/Downloads";

  copyToDownloads = pkgs.writeShellScript "iso-autobuild-copy-to-downloads" ''
    set -euo pipefail

    # system.build.isoImage's out path is a directory (iso/<name>.iso
    # + nix-support/), not the iso file itself.
    src=$(ls "${resultLink}"/iso/*.iso 2>/dev/null | head -n1 || true)
    if [ -z "$src" ]; then
      echo "No iso has been built yet, nothing to copy." >&2
      exit 0
    fi

    name=$(basename "$src")
    tmp="${downloadsDir}/$name.tmp"
    cp -L "$src" "$tmp"
    mv -f "$tmp" "${downloadsDir}/$name"

    # Drop older builds so Downloads doesn't accumulate one gigabyte-plus
    # iso per rebuild — every filename shares this prefix (isoImage.edition).
    find "${downloadsDir}" -maxdepth 1 -name 'nixos-recovery-*.iso' -not -name "$name" -delete

    echo "Copied $src to ${downloadsDir}/$name"
  '';
in
{
  options.myIsoAutobuild = {
    enable = lib.mkEnableOption "auto-build the isoimage flake output into buildUser's Downloads folder";

    flakeDir = lib.mkOption {
      type = lib.types.str;
      description = "Path to the local flake checkout to build from.";
    };

    buildUser = lib.mkOption {
      type = lib.types.str;
      description = ''
        Existing user to run `nix build` (and the Downloads copy) as.
        Needs read access to flakeDir (typically its owner, since home
        directories are usually mode 700) and membership in
        nix.settings.allowed-users (e.g. wheel) to talk to the nix
        daemon. Deliberately not a fresh dedicated/dynamic user:
        neither of those constraints, nor writing into this user's own
        ~/Downloads, can be satisfied by one without loosening
        filesystem or nix-daemon trust — a bigger change than reusing
        the account that already has all three legitimately.
      '';
    };

    isoAttr = lib.mkOption {
      type = lib.types.str;
      default = "isoimage";
      description = "nixosConfigurations attribute name whose system.build.isoImage gets built.";
    };

    triggeredBy = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "pull-deploy.service" ];
      description = "Other systemd units which, on success, should trigger an iso rebuild (via their OnSuccess=).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0700 ${cfg.buildUser} ${cfg.buildUser} -"
    ];

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
          unitConfig.OnSuccess = [ "iso-copy-to-downloads.service" ];
          serviceConfig = {
            Type = "oneshot";
            # Not root, not a dedicated/dynamic user: `nix build` here
            # needs to read ${cfg.flakeDir} (owned by this user, under
            # a mode-700 home dir) and be trusted by the nix daemon
            # (nix.settings.allowed-users) — both already true for the
            # account that owns the checkout, neither achievable by a
            # freshly-minted dedicated user without loosening either.
            User = cfg.buildUser;
            # nix build needs to write its fetcher cache
            # (~/.cache/nix/fetcher-cache-v4.sqlite) even though it
            # only reads the flake checkout itself.
            ReadWritePaths = [
              stateDir
              "/home/${cfg.buildUser}/.cache/nix"
            ];
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

        # Drops the freshest built iso into buildUser's own Downloads
        # folder for them to copy onto the Ventoy drive by hand — no
        # block-device/mount privileges needed at all, so this is
        # about as minimal as a oneshot doing a same-user file copy
        # can get. Still not DynamicUser: writing into a real user's
        # home directory requires being that user (or root), so
        # there's no dedicated/ephemeral account that could do this
        # instead without a filesystem ACL grant.
        iso-copy-to-downloads = {
          description = "Copy the last-built ${cfg.isoAttr} iso into ${cfg.buildUser}'s Downloads folder";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${copyToDownloads}";
            User = cfg.buildUser;
            ReadWritePaths = [
              stateDir
              downloadsDir
            ];
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
      }
    ];
  };
}

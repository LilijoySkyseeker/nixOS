{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myAutoUpdate;
  flakeDir = "/etc/nixos";
in
{
  options.myAutoUpdate = {
    enable = lib.mkEnableOption "automated flake.lock update, build test, and switch";

    hostAttr = lib.mkOption {
      type = lib.types.str;
      description = "nixosConfigurations attribute name to build/test/switch (e.g. \"homelab\").";
    };

    updateDates = lib.mkOption {
      type = lib.types.str;
      default = "Sun 02:00";
      description = "systemd OnCalendar spec for the update/build-test/merge job.";
    };

    switchDates = lib.mkOption {
      type = lib.types.str;
      default = "Sun 04:00";
      description = "systemd OnCalendar spec for the actual switch (system.autoUpgrade). Should run after updateDates.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. On a branch: bump flake.lock, build-test it, and only if the build
    #    succeeds merge it into master and push. Never touches master unless
    #    the new inputs actually evaluate and build.
    systemd.services.flake-update-test = {
      description = "Update flake inputs on a branch and merge to master if the build succeeds";
      path = with pkgs; [
        git
        nixos-rebuild
        nix
        coreutils
      ];
      script = ''
        set -euo pipefail
        cd ${flakeDir}

        git fetch origin
        git checkout master
        git reset --hard origin/master
        git branch -D auto-update 2>/dev/null || true
        git checkout -b auto-update

        nix flake update

        if git diff --quiet -- flake.lock; then
          echo "No input updates available."
          git checkout master
          git branch -D auto-update
          exit 0
        fi

        git commit -am "chore: automated flake.lock update"

        if nixos-rebuild build --flake .#${cfg.hostAttr}; then
          echo "Build succeeded, merging auto-update into master."
          git checkout master
          git merge --ff-only auto-update
          git push origin master
          git branch -D auto-update
        else
          echo "Build failed, pushing auto-update branch for manual review instead of merging." >&2
          git push origin auto-update --force
          git checkout master
          exit 1
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        # `nixos-rebuild build` here delegates the actual build to
        # nix-daemon, so this process itself never needs kernel/module
        # access — unlike system.autoUpgrade below, this one never runs
        # `switch`. ProtectHome is deliberately left off: git push
        # authenticates via whatever's in /root (ssh key/credential
        # helper), unverified from here, so restricting it risked
        # silently breaking the push step.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ flakeDir ];
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
      };
    };

    systemd.timers.flake-update-test = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.updateDates;
        Persistent = true;
      };
    };

    # 2. Stock NixOS auto-upgrade: switches to whatever is currently checked
    #    out at /etc/nixos (master, possibly updated by the job above).
    system.autoUpgrade = {
      enable = true;
      flake = "${flakeDir}#${cfg.hostAttr}";
      dates = cfg.switchDates;
      persistent = true;
      operation = "switch";
    };

    # Only reboot if the switch actually changed the running kernel/initrd,
    # instead of rebooting on every switch (system.autoUpgrade's allowReboot
    # would reboot unconditionally).
    systemd.services.nixos-upgrade.serviceConfig = {
      ExecStartPost = [
        (pkgs.writeShellScript "reboot-if-kernel-changed" ''
          if [ "$(readlink /run/booted-system/kernel)" != "$(readlink /run/current-system/kernel)" ]; then
            echo "Kernel/initrd changed, rebooting."
            systemctl reboot
          fi
        '')
      ];
      # This unit runs `nixos-rebuild switch` itself — real system
      # activation (bootloader, kernel modules, arbitrary unit
      # restarts) — so it can't be sandboxed the way a plain build/git
      # job can. NoNewPrivileges is the one flag safe to add regardless
      # (root already has every privilege it could gain).
      NoNewPrivileges = true;
    };
  };
}

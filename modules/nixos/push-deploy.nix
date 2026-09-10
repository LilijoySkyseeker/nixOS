{ config, ... }:
let
  deployGuardsScript = config.flake.deployGuardsScript;
in
{
  flake.modules.nixos."push-deploy" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.myPushDeploy;
    in
    {
      options.myPushDeploy = {
        enable = lib.mkEnableOption "build locally and push+activate on a remote target host on a schedule";

        flakeDir = lib.mkOption {
          type = lib.types.str;
          description = "Path to the local flake checkout to build from (evaluation/build happens on THIS machine).";
        };

        hostAttr = lib.mkOption {
          type = lib.types.str;
          description = "nixosConfigurations attribute name to build/switch (e.g. \"vps\") — this is the remote target's own config, not this machine's.";
        };

        targetHost = lib.mkOption {
          type = lib.types.str;
          description = "SSH destination for the remote target, e.g. \"vps-deploy@vps\".";
        };

        identityFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to the SSH private key authenticating to targetHost (e.g. a sops secret path).";
        };

        elevate = lib.mkOption {
          type = lib.types.enum [
            "none"
            "sudo"
          ];
          default = "sudo";
          description = ''
            Whether to pass nixos-rebuild's --sudo flag for the target's remote
            activation steps. nixos-rebuild-ng has no separate "elevate backend"
            flag (an earlier assumption here was wrong) — it only wraps
            remote commands in the literal `sudo` binary. That's still
            polkit/run0-based here rather than real sudo, since the target
            aliases `sudo` to run0 (security.run0.enableSudoAlias, set
            globally in profiles/default.nix) instead of enabling real sudo.
            Default "sudo" since the target user (vps-deploy) is unprivileged
            and needs it for both the profile-set and switch-to-configuration
            steps.
          '';
        };

        dates = lib.mkOption {
          type = lib.types.str;
          default = "Thu 03:15";
          description = "systemd OnCalendar spec for the push/switch job — a periodic fallback independent of any onSuccess wiring the caller may also set up.";
        };

        scheduleEnable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether the periodic `push-deploy-<hostAttr>` **timer** is
            installed. False keeps the service defined and manually
            startable (`systemctl start push-deploy-vps`) — which is how
            the target gets deployed by hand — while stopping it
            happening on a schedule.

            Note this only governs the timer. If the caller also wires
            this unit into `myAutoUpdate.onDeployUnits`, it still runs
            after a real activation of the *deploying* host; disabling
            that host's own schedule is what stops the chain.

            The timer is removed rather than merely un-wanted, so a
            `switch` actually stops a running timer instead of leaving it
            armed until the next reboot.

            Currently false fleet-wide — see
            2026-08-27-rebuild-the-update-build-deploy-pipeline-properly.md.
          '';
        };

        minSwitchInterval = lib.mkOption {
          type = lib.types.ints.positive;
          default = 7 * 24 * 60 * 60;
          description = ''
            Minimum seconds since the target's /nix/var/nix/profiles/system
            was last activated (checked remotely over SSH) before this
            scheduled job will build/push. Mainly matters for the periodic
            `dates` fallback — an onSuccess-triggered run right after this
            same host's own switch is already gated by that switch's own
            interval check.
          '';
        };

        operation = lib.mkOption {
          type = lib.types.enum [
            "switch"
            "boot"
          ];
          default = "switch";
          description = "nixos-rebuild operation to run on the target: \"switch\" activates immediately, \"boot\" only sets the default boot entry for next reboot.";
        };

        rebootIfKernelChanged = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "After switching, reboot the target if the switch changed its running kernel/initrd (checked and triggered remotely over SSH).";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services."push-deploy-${cfg.hostAttr}" = {
          description = "Build locally and push+activate ${cfg.hostAttr} on ${cfg.targetHost}";
          path = with pkgs; [
            git
            nixos-rebuild
            nix
            openssh
            coreutils
          ];
          script = ''
            set -euo pipefail
            cd ${cfg.flakeDir}

            ${deployGuardsScript}

            require_clean_master
            fetch_and_merge_master

            export NIX_SSHOPTS="-i ${cfg.identityFile} -o StrictHostKeyChecking=accept-new"

            last_switch=$(ssh $NIX_SSHOPTS ${cfg.targetHost} stat -c %Y /nix/var/nix/profiles/system)
            check_min_switch_interval ${toString cfg.minSwitchInterval} "$last_switch"

            nixos-rebuild ${cfg.operation} \
              --flake .#${cfg.hostAttr} \
              --target-host ${cfg.targetHost} \
              ${lib.optionalString (cfg.elevate == "sudo") "--sudo"}

            ${lib.optionalString cfg.rebootIfKernelChanged ''
              # The target's own /run/booted-system vs /run/current-system
              # check (used by pull-deploy/myAutoUpdate for local switches)
              # doesn't apply here since we're not running on the target —
              # check remotely instead. Reboot itself has to go through the
              # same sudo/run0 alias elevation as the switch above, since
              # the target's deploy user has no other privilege (see
              # hosts/vps/configuration.nix's vps-deploy dispatcher, which
              # matches this exact string).
              booted=$(ssh $NIX_SSHOPTS ${cfg.targetHost} readlink /run/booted-system/kernel)
              current=$(ssh $NIX_SSHOPTS ${cfg.targetHost} readlink /run/current-system/kernel)
              if [ "$booted" != "$current" ]; then
                echo "Kernel/initrd changed on ${cfg.targetHost}, rebooting."
                ssh $NIX_SSHOPTS ${cfg.targetHost} "sudo systemctl reboot"
              fi
            ''}
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            # F-P7-06. VM-tested with a real remote target
            # (tests/push-deploy-sandbox.nix) rather than guessed --
            # nixos-rebuild-ng's own source settles the two hazards this
            # comment used to only speculate about:
            #
            # - It runs its SSH ControlMaster through a tempdir made by
            #   Python's `tempfile.TemporaryDirectory()`, which resolves
            #   against `$TMPDIR`/`/tmp` (nixos_rebuild/tmpdir.py) --
            #   created once at import time, before anything else runs.
            #   `ProtectSystem=strict` alone makes `/tmp` read-only and
            #   this fails immediately; `PrivateTmp=true` fixes it, since
            #   the socket only ever needs to be reachable from this
            #   unit's own process tree, which shares one mount namespace
            #   throughout a single oneshot run.
            # - The initial local flake build/eval (before anything ever
            #   reaches the network) needs `/root/.cache` writable for
            #   nix's own eval/build scratch -- covered by ReadWritePaths
            #   below rather than `ProtectHome=false`, so only that one
            #   path opens up, not all of /root. `nix show-config`
            #   confirms `use-xdg-base-directories = false` (the pinned
            #   default), so this genuinely has to be `~/.cache`, not an
            #   `XDG_CACHE_HOME` redirect to somewhere self-creating.
            # - `ReadWritePaths` does not create the directory it grants
            #   access to -- caught by the VM test on a genuinely fresh
            #   root user with no prior `.cache`: mount-namespace setup
            #   fails outright with ENOENT before the script even starts.
            #   A `+`-prefixed ExecStartPre does NOT help here (also
            #   caught by the same test, on the retry): `+` only bypasses
            #   privilege-dropping (User=/Group=), not the mount
            #   namespace, which is established once for the whole unit
            #   before any ExecStartPre runs. The directory has to exist
            #   before this unit starts at all -- see the tmpfiles rule
            #   below instead.
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            PrivateTmp = true;
            ReadWritePaths = [
              cfg.flakeDir # fetch_and_merge_master writes here
              "/root/.ssh" # known_hosts (StrictHostKeyChecking=accept-new)
              "/root/.cache" # nix's own eval/build scratch
            ];
          };
        };

        # Both ReadWritePaths targets above have to exist before the unit
        # ever starts -- the mount namespace is set up once for the whole
        # unit, before any ExecStartPre runs, so nothing inside the unit
        # itself can create them first (see the serviceConfig comment).
        # `.ssh` is very likely already there on a real host, but this
        # doesn't assume it -- both are declared unconditionally rather
        # than trusting incidental prior state.
        systemd.tmpfiles.rules = [
          "d /root/.cache 0700 root root -"
          "d /root/.ssh 0700 root root -"
        ];

        systemd.timers."push-deploy-${cfg.hostAttr}" = lib.mkIf cfg.scheduleEnable {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.dates;
            Persistent = true;
          };
        };
      };
    };
}

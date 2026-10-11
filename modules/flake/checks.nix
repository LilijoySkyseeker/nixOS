# Integration tests, run with `nix build .#checks.x86_64-linux.<name>` or
# all at once with `nix flake check`. These are the rung above
# `nixos-rebuild build`: they boot real VMs, so they can catch what only
# breaks at runtime. See .claude/skills/verify-a-change/SKILL.md.
{ config, inputs, ... }:
{
  perSystem = _: {
    checks = {
      # pkgsStable, not pkgsUnstable: homelab (the aggregator) is a
      # stable host and the fleet's Alloy is pinned stable
      # plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D18
      loki-pipeline = import ../../tests/loki-pipeline.nix {
        pkgs = config.flake.pkgsStable;
        lokiModule = config.flake.modules.nixos.loki;
        alloyModule = config.flake.modules.nixos."alloy";
        impermanenceModule = inputs.impermanence.nixosModules.impermanence;
      };

      zrepl-replication = import ../../tests/zrepl-replication.nix {
        pkgs = config.flake.pkgsUnstable;
        zreplModule = config.flake.modules.nixos."zrepl";
      };

      zfs-space-guard = import ../../tests/zfs-space-guard.nix {
        pkgs = config.flake.pkgsUnstable;
        zfsSpaceGuardModule = config.flake.modules.nixos."zfs-space-guard";
      };

      zfs-dataset-properties = import ../../tests/zfs-dataset-properties.nix {
        pkgs = config.flake.pkgsUnstable;
        zfsDatasetPropertiesModule = config.flake.modules.nixos."zfs-dataset-properties";
      };

      docker-publish-guard = import ../../tests/docker-publish-guard.nix {
        pkgs = config.flake.pkgsUnstable;
        dockerPublishGuardModule = config.flake.modules.nixos."docker-publish-guard";
      };

      agent-user = import ../../tests/agent-user.nix {
        pkgs = config.flake.pkgsUnstable;
        agentUserModule = config.flake.modules.nixos."agent-user";
      };

      docker-userns-remap = import ../../tests/docker-userns-remap.nix {
        pkgs = config.flake.pkgsUnstable;
        dockerUsernsModule = config.flake.modules.nixos."docker-userns-remap";
      };

      deploy-guards = import ../../tests/deploy-guards.nix {
        pkgs = config.flake.pkgsUnstable;
        deployGuardsScript = config.flake.deployGuardsScript;
      };

      push-deploy-sandbox = import ../../tests/push-deploy-sandbox.nix {
        pkgs = config.flake.pkgsUnstable;
        pushDeployModule = config.flake.modules.nixos."push-deploy";
        # The exact flake, not just its already-instantiated `pkgs`, so the
        # test can call `.lib.nixosSystem` itself and get the byte-identical
        # derivation the pushed flake's own `nixpkgs.lib.nixosSystem` call
        # will produce inside the VM -- see the test file's own comment.
        nixpkgsUnstableFlake = config.flake.nixpkgsUnstableFlake;
      };
    };
  };
}

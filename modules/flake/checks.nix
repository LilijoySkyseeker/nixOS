# VM integration tests: `nix build .#checks.x86_64-linux.<name>` or
# `nix flake check` (see .agents/skills/verify-a-change/SKILL.md)
{ config, inputs, ... }:
{
  perSystem = _: {
    checks = {
      zrepl-replication = import ../../tests/zrepl-replication.nix {
        pkgs = config.flake.pkgsUnstable;
        zreplModule = config.flake.modules.nixos."zrepl";
      };

      zfs-space-guard = import ../../tests/zfs-space-guard.nix {
        pkgs = config.flake.pkgsUnstable;
        zfsSpaceGuardModule = config.flake.modules.nixos."zfs-space-guard";
      };

      health-alerts = import ../../tests/health-alerts.nix {
        pkgs = config.flake.pkgsUnstable;
        healthAlertsModule = config.flake.modules.nixos."health-alerts";
      };

      zfs-dataset-properties = import ../../tests/zfs-dataset-properties.nix {
        pkgs = config.flake.pkgsUnstable;
        zfsDatasetPropertiesModule = config.flake.modules.nixos."zfs-dataset-properties";
      };

      thinkpad-disk = import ../../tests/thinkpad-disk.nix {
        pkgs = config.flake.pkgsUnstable;
        inherit (config.flake) vars;
        diskoModule = inputs.disko.nixosModules.disko;
        encryptedRootModule = config.flake.modules.nixos."encrypted-root";
        hibernateModule = config.flake.modules.nixos."hibernate";
        hibernateOnlyModule = config.flake.modules.nixos."hibernate-only";
      };

      pc-desktop = import ../../tests/pc-desktop.nix {
        pkgs = config.flake.pkgsUnstable;
        specialArgs = {
          inherit inputs;
          inherit (config.flake) vars;
          pkgs-unstable = config.flake.pkgsUnstable;
          pkgs-stable = config.flake.pkgsStable;
        };
        profilePcModule = config.flake.modules.nixos."profile-pc";
        kdeModule = config.flake.modules.nixos.kde;
      };

      server-shell = import ../../tests/server-shell.nix {
        pkgs = config.flake.pkgsUnstable;
        specialArgs = {
          inherit inputs;
          inherit (config.flake) vars;
          pkgs-unstable = config.flake.pkgsUnstable;
          pkgs-stable = config.flake.pkgsStable;
        };
        impermanenceModule = inputs.impermanence.nixosModules.impermanence;
        homeManagerModule = inputs.home-manager.nixosModules.home-manager;
        loginSummaryModule = config.flake.modules.nixos."login-summary";
        toolingModule = config.flake.modules.homeManager.tooling;
      };

      docker-publish-guard = import ../../tests/docker-publish-guard.nix {
        pkgs = config.flake.pkgsUnstable;
        dockerPublishGuardModule = config.flake.modules.nixos."docker-publish-guard";
      };

      agent-user = import ../../tests/agent-user.nix {
        pkgs = config.flake.pkgsUnstable;
        agentUserModule = config.flake.modules.nixos."agent-user";
      };

      local-ai = import ../../tests/local-ai.nix {
        pkgs = config.flake.pkgsUnstable;
        agentUserModule = config.flake.modules.nixos."agent-user";
        localAiModule = config.flake.modules.nixos."local-ai";
      };

      docker-userns-remap = import ../../tests/docker-userns-remap.nix {
        pkgs = config.flake.pkgsUnstable;
        dockerUsernsModule = config.flake.modules.nixos."docker-userns-remap";
      };

      deploy-revision = import ../../tests/deploy-revision.nix {
        pkgs = config.flake.pkgsUnstable;
        deployRevisionScript = config.flake.deployRevisionScript;
      };

      website = import ../../tests/website.nix {
        pkgs = config.flake.pkgsStable;
        websiteModule = config.flake.modules.nixos.website;
      };

      push-deploy-sandbox = import ../../tests/push-deploy-sandbox.nix {
        pkgs = config.flake.pkgsUnstable;
        pushDeployModule = config.flake.modules.nixos."push-deploy";
        # the flake itself, not its pkgs: the test's `.lib.nixosSystem` must
        # yield the byte-identical derivation the pushed flake builds in the VM
        nixpkgsUnstableFlake = config.flake.nixpkgsUnstableFlake;
      };
    };
  };
}

{ config, inputs, ... }:
{
  perSystem = _: {
    checks = {
      zrepl-replication = import ../../tests/zrepl-replication.nix {
        pkgs = config.flake.pkgsUnstable;
        zreplModule = config.flake.modules.nixos."zrepl";
      };

      health-alerts = import ../../tests/health-alerts.nix {
        pkgs = config.flake.pkgsUnstable;
        healthAlertsModule = config.flake.modules.nixos."health-alerts";
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
    };
  };
}

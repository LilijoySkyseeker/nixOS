{ config, inputs, ... }:
{
  # Claude Code from llm-agents, which packages new releases within a day;
  # nixos-unstable lagged days behind a new model's support (Fable 5.2, 2026-11)
  # TODO: drop when claude-code is 2.1.323+ in the locked nixos-unstable
  # (owner: back to nixpkgs once it has it; 2.1.323 has permission and
  # sandbox fixes 2.1.321 lacks): this overlay and its two uses,
  # here and in hosts.nix; the llm-agents input stays for claude-desktop
  flake.overlays.llm-agents = _: prev: {
    inherit (inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}) claude-code;
  };

  # Paseo held at 0.15.4: the repo's patches (modules/nixos/paseo) don't
  # apply to 0.16.0, and 0.16.0 approves `ask` rules without a card (fixed
  # in 0.16.1). paseo-desktop follows, it's paseo.passthru.desktop
  # TODO: drop when the Paseo patches are ported to 0.16.1 or later: this
  # overlay and its two uses, here and in hosts.nix
  flake.overlays.paseo-hold = _: prev: {
    paseo = prev.paseo.overrideAttrs (
      _:
      let
        version = "0.15.4";
        src = prev.fetchFromGitHub {
          owner = "getpaseo";
          repo = "paseo";
          tag = "v${version}";
          hash = "sha256-zqD9MrqYZ6S3O72b5y+7P0iJgIMf4MRq1zgcqBcyhko=";
        };
      in
      {
        inherit version src;
        npmDepsHash = "sha256-a8IgSFKtCzql2c2hCbhxxXnSzEUHRC6dGnBuQhgN2Jg=";
        npmDeps = prev.fetchNpmDeps {
          inherit src;
          name = "paseo-${version}-npm-deps";
          hash = "sha256-a8IgSFKtCzql2c2hCbhxxXnSzEUHRC6dGnBuQhgN2Jg=";
          fetcherVersion = 2;
        };
      }
    );
  };

  flake.pkgsUnstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
    overlays = [
      config.flake.overlays.llm-agents
      config.flake.overlays.paseo-hold
    ];
  };

  flake.pkgsStable = import inputs.nixpkgs-stable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
  };

  flake.pkgsHomelab = import inputs.nixpkgs-homelab {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
  };
}

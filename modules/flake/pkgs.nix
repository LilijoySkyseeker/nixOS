{ config, inputs, ... }:
{
  # Claude Code from llm-agents, which packages new releases within a day;
  # nixos-unstable lagged days behind a new model's support (Fable 5.2, 2026-11)
  # TODO: drop when claude-code is 2.1.321+ in the locked nixos-unstable
  # (owner: back to nixpkgs once it has it): this overlay and its two uses,
  # here and in hosts.nix; the llm-agents input stays for claude-desktop
  flake.overlays.llm-agents = _: prev: {
    inherit (inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}) claude-code;
  };

  flake.pkgsUnstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
    overlays = [
      config.flake.overlays.llm-agents
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

{ config, inputs, ... }:
{
  # build fixes for nixos-unstable, used by pkgsUnstable and torrent's own pkgs
  flake.overlays.unstable-build-fixes = _: prev: {
    # aws-lc-sys now wants a system AWS-LC, which these didn't have
    # (chatgpt pulls in both)
    # TODO: drop when NixOS/nixpkgs#584783 is in nixos-unstable
    tectonic-unwrapped = prev.tectonic-unwrapped.overrideAttrs (old: {
      buildInputs = old.buildInputs ++ [ prev.aws-lc ];
    });
    # TODO: drop when NixOS/nixpkgs#585124 is fixed in nixos-unstable
    codex = prev.codex.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [
        prev.aws-lc
        prev.oniguruma
        prev.sqlite
        prev.zstd
      ];
    });
  };

  # Claude Code from llm-agents, which packages new releases within a day;
  # nixos-unstable lagged days behind a new model's support (Fable 5.2, 2026-11)
  # TODO: drop when claude-code is 2.1.321+ in nixos-unstable (owner: back to
  # nixpkgs once it has it)
  flake.overlays.llm-agents = _: prev: {
    inherit (inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}) claude-code;
  };

  flake.pkgsUnstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config = {
      allowUnfree = true;
    };
    overlays = [
      config.flake.overlays.unstable-build-fixes
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

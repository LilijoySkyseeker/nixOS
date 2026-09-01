{ ... }:
{
  # Single source of truth for interactive debugging tooling, consumed by
  # BOTH the devshell and every host (via profiles/default.nix, which
  # profile-pc also imports). Add a tool here once and it appears in the
  # dev environment and on the machines at the same time — the previous
  # arrangement had them drift, so a tool you had locally was missing on
  # the host you actually needed it on, at the moment you needed it.
  #
  # **Always call this with an unstable pkgs set**, on every consumer.
  # That is a deliberate policy, not an accident of where it is used:
  # debug tooling should be the same version fleet-wide, so a command
  # learned on one host behaves identically on the next, and you are never
  # debugging a live problem against a year-old set of flags. homelab is
  # pinned to nixpkgs-stable for its *system*, and still takes these from
  # unstable.
  #
  # It is a **function of pkgs** rather than a plain list because there is
  # no single unstable package set to close over here: the devshell has
  # `config.flake.pkgsUnstable`, the NixOS profile has the `pkgs-unstable`
  # specialArg. Same shape and reasoning as
  # `flake.deployGuardsScript` being a plain string rather than a
  # derivation — see modules/flake/deploy-guards.nix.
  #
  # What belongs here: things used to inspect a *running* system. What
  # does not: dev-machine-only tooling (nixfmt, statix, gh, sops,
  # nixos-anywhere), which stays in the devshell's own list.
  #
  # Keep it short. This is a hardening-focused fleet and these land on
  # every host including the public-facing one, so `tcpdump` and
  # `conntrack` are deliberately absent until something actually needs
  # them, rather than added speculatively. Adding one is a one-line change
  # here, which is the point.
  flake.debugTools =
    pkgs: with pkgs; [
      jq # JSON on the command line: `tailscale status --json`, webhook payloads
      ipset # inspect CrowdSec's blacklist sets, which the firewall rules match on
    ];
}

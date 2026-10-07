_: {
  # debugging tools for inspecting a running system, shared by the devshell
  # and every host (profiles/default.nix); dev-only tools stay in the devshell
  # always pass an unstable pkgs set, even on stable-pinned homelab, so versions
  # match fleet-wide; a function because each consumer has its own unstable pkgs
  # lands on every host incl. the public one: keep it short, no speculative
  # tcpdump/conntrack
  flake.debugTools =
    pkgs: with pkgs; [
      jq # JSON on the command line: `tailscale status --json`, webhook payloads
      openssl # `rand` for generating secret values, `s_client` for inspecting TLS
    ];
}

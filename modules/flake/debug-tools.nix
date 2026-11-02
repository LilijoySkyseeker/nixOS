_: {
  # always pass an unstable pkgs set, even on stable-pinned homelab, so versions
  # match fleet-wide; a function because each consumer has its own unstable pkgs
  # lands on every host incl. the public one: keep it short, no speculative
  # tcpdump/conntrack
  flake.debugTools =
    pkgs: with pkgs; [
      jq
      openssl
      nvd
      nftables
    ];
}

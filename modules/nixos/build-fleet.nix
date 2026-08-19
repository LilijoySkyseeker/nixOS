# Single source of truth for the distributed-build worker fleet, consumed
# by modules/nixos/build-submitter.nix. Plain data, not a NixOS module —
# imported directly (not via `imports`). Adding a host here (e.g. pi5)
# automatically gets it wired into every other submitter's
# nix.buildMachines, and a matching `sops.secrets.builder_key_<name>`
# declared on every OTHER submitter (never on itself).
#
# See .claude/plans/quirky-herding-teapot.md for the design rationale
# (per-worker not per-edge keys, ssh-ng, publicHostKey pinning,
# native-vs-emulated aarch64 priority via speedFactor).
{
  homelab = {
    maxJobs = 4; # confirmed live via `nproc` on homelab, 2026-08-19
    systems = [
      "x86_64-linux"
      "aarch64-linux" # emulated fallback (native x86_64 host)
    ];
    speedFactor = 2;
    # confirmed live via `ssh-keyscan homelab`, base64 -w0 of the full
    # "ssh-ed25519 AAAA..." line (matches the .pub file format the
    # nixpkgs option description expects — NOT base64 of just the key
    # field), 2026-08-19
    publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUFYdS8wckJwR1VlUlVEbHh2KzZrV2dHVVFqQW44SUdOWjVJdG9KdURTK1oK";
  };

  thinkpad = {
    maxJobs = 12; # 6 physical cores / 12 threads, per user, 2026-08-19
    systems = [
      "x86_64-linux"
      "aarch64-linux" # emulated fallback; AC-gated either way (myBuildWorker.acGated)
    ];
    speedFactor = 1; # weakest + intermittently unavailable
    # TODO before deploying: thinkpad has no sshd/host key yet — this
    # fleet's own rollout is what enables sshd there. Pin in a follow-up
    # commit right after thinkpad's first deploy via
    # `base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub` run on thinkpad.
    publicHostKey = null;
  };

  torrent = {
    maxJobs = 16; # confirmed live via `nproc` on torrent, 2026-08-19
    systems = [ "x86_64-linux" ]; # strongest machine, no emulated-aarch64 duty needed
    speedFactor = 3; # strongest
    # TODO before deploying: same chicken-and-egg as thinkpad above —
    # pin after torrent's first deploy.
    publicHostKey = null;
  };

  # pi5 = {
  #   maxJobs = ...;
  #   systems = [ "aarch64-linux" ]; # native
  #   speedFactor = 3; # prefer over emulated fallbacks when available
  #   publicHostKey = null; # TODO once host exists
  # };
}

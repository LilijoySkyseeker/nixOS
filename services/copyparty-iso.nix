{ inputs, pkgs, ... }:
{
  # Recovery-environment file server: no auth, serving the whole live
  # filesystem (so anything mounted under /mnt or /media during a recovery
  # session is reachable too). Acceptable only because this is a live-boot
  # ISO with no persistent state or secrets — do not reuse this config on a
  # persistent host (see services/nfs.nix / prior copyparty git history for
  # why it was replaced there with a tailnet-only NFS server).
  nixpkgs.overlays = [ inputs.copyparty.overlays.default ];
  imports = [ inputs.copyparty.nixosModules.default ];
  environment.systemPackages = [ pkgs.copyparty ];

  services.copyparty = {
    enable = true;
    settings = {
      no-robots = true;
      p = 3923;
      # No e2dsa/e2ts: those recursively index every volume for
      # search/thumbnails on startup, which on a recovery ISO means
      # crawling whatever's mounted under /mnt — including failing
      # disks, huge zpools, or /proc/sys — before the server comes up.
      # Skipping indexing keeps startup instant and browsing/up-down
      # working regardless of what's plugged in.
    };
    volumes = {
      # Deliberately not xdev: disks mounted under /mnt during recovery
      # are a different filesystem than the live root, and are exactly
      # what this needs to reach. Without e2dsa scanning nothing gets
      # crawled ahead of time anyway — /proc, /sys etc. only get walked
      # if someone actually clicks into them in the browser.
      "/" = {
        path = "/";
        access = {
          A = [ "*" ];
        };
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 3923 ];
}

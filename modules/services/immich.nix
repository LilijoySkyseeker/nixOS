{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.immich =
    { config, lib, ... }:
    {
      # immich: self-hosted photo/video backup, tailnet-only.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md
      services.immich = {
        enable = true;
        # bind broad, restrict at the firewall below -- same shape as
        # jellyfin. openFirewall would open every interface, including
        # homelab's ISP-delegated public IPv6 LAN address.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G3
        host = "0.0.0.0";
        # reuses jellyfin's existing zdata/storage/storage dataset rather
        # than a new one -- already zrepl+restic backed up.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#D1
        mediaLocation = "/storage/immich";
        # GPU-accelerated video transcoding (not the ML/face-detection
        # acceleration deferred in the GPU-accelerate-immich-ml plan --
        # that needs a from-source onnxruntime+CUDA rebuild; this is just
        # device passthrough, since immich's own ffmpeg build already has
        # NVENC/VAAPI compiled in). Same two render nodes jellyfin already
        # uses, confirmed live on this exact host that renderD128 alone is
        # sufficient for working NVENC -- jellyfin's own systemd unit has
        # no /dev/nvidia* DeviceAllow entries at all, just this. The
        # actual hardware-acceleration backend (nvenc) is picked in
        # Immich's own admin UI, not declared here -- see D5.
        # F7 (security review): explicit "rw" rather than a bare path --
        # a bare path defaults to DeviceAllow's implicit "rwm", one bit
        # wider than jellyfin's own explicit rw-only grant this is meant
        # to mirror. Inert either way (CapabilityBoundingSet="" already
        # strips CAP_MKNOD), but precise beats accidentally-inert.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#F7
        accelerationDevices = [
          "/dev/dri/renderD128 rw" # Nvidia GTX 1050 Mobile (NVENC)
          "/dev/dri/renderD129 rw" # Intel HD 630 (QSV/VAAPI fallback)
        ];
      };

      # F6 (security review, superseding the original D5 users.users.
      # immich.extraGroups approach): render-group membership belongs on
      # the immich-server UNIT, not the immich user account.
      # immich-server and immich-machine-learning share that one user --
      # a user-level grant would silently hand GPU device access to the
      # ML worker too, the component that parses untrusted uploaded
      # media, for no benefit (it's CPU-only per D3/the deferred
      # GPU-accelerate-immich-ml plan; device access alone doesn't
      # accelerate anything without that separate CUDA rebuild). Verified
      # this merges with upstream's own conditional redis-group grant on
      # this same unit rather than replacing it (both appear in the
      # generated unit's SupplementaryGroups).
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#F6
      #
      # F6 continued: the group fix above is necessary but not
      # sufficient. `services.immich.accelerationDevices` is an
      # upstream option applied via a `serviceConfig` shared by *both*
      # units (nixpkgs' own `commonServiceConfig`), so DeviceAllow for
      # the render nodes lands on immich-machine-learning regardless of
      # anything scoped here -- confirmed in the generated unit file.
      # Force the ML unit back to its pre-D5 zero-device posture
      # (mkForce wins over the upstream module's plain `mkIf`, which
      # carries no explicit priority) so GPU access is real
      # immich-server-only, not just nominally ungrouped.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#F6
      systemd = {
        services = {
          immich-server.serviceConfig.SupplementaryGroups = [ "render" ];
          immich-machine-learning.serviceConfig = {
            PrivateDevices = lib.mkForce true;
            DeviceAllow = lib.mkForce [ ];
          };
        };

        # the upstream module's own tmpfiles rule for mediaLocation is
        # type `e` (adjust mode if it already exists) -- a no-op for
        # anything but its own default /var/lib/immich, which systemd's
        # StateDirectory= creates for free. Since mediaLocation is
        # overridden above, nothing ever creates it without this `d` rule
        # (merged into the same "immich" settings group the upstream
        # module already declares). Caught live on first deploy:
        # immich-server crash-looped on EACCES trying to mkdir under a
        # mediaLocation that didn't exist.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G4
        tmpfiles.settings.immich.${config.services.immich.mediaLocation}.d = {
          user = config.services.immich.user;
          group = config.services.immich.group;
          mode = "0700";
        };

        # /storage is drwxrws--- root:multimedia
        # (hosts/homelab/configuration.nix) -- immich is in neither, so
        # it can't traverse into its own mediaLocation without this, even
        # once the directory above exists. Non-recursive and additive
        # (a+, not the existing recursive-replace `A /storage ...
        # group:multimedia:rwx` rule) and execute-only: this only lets
        # immich reach the one subpath it already fully owns, not
        # read/list jellyfin's actual media. Must come after that
        # existing rule (same generated file, mkAfter) or the next
        # boot's recursive replace-pass wipes this entry back out.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G4
        #
        # SECURITY-LOAD-BEARING. Full incident writeup: plan#F5. In
        # short: /storage's own recursive `group:multimedia:rwx` grant
        # (hosts/homelab/configuration.nix) re-applies on every
        # boot/switch and would otherwise leak into mediaLocation once
        # it exists, defeating the 0700 confidentiality D1(b)/F3 relied
        # on -- no exploit needed, lilijoy's own account already holds
        # that gid via the NFS mounts. This rule re-locks mediaLocation
        # back down every time. F8 (security review): the guarantee this
        # wins over upstream's own `e`-type rule on the same path is
        # systemd-tmpfiles' own type-based conflict resolution
        # (confirmed against the pinned tmpfiles.c source), not
        # file/list order as originally assumed here -- current behavior
        # is verified correct live regardless (forced boot-equivalent
        # tmpfiles pass + getfacl).
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#F5 #F8
        #
        # D4: torrent/thinkpad (trusted, same NFS multimedia-gid mount
        # jellyfin uses) get read-only access to library/ -- the
        # organized original photos/videos, not
        # upload/thumbs/encoded-video/backups. Read-only: Immich tracks
        # every file's path/checksum in its own database, so an external
        # write risks desyncing that -- a data-integrity concern
        # independent of trust. These entries are additive (a+/A+),
        # layering read grants back on top of the re-lock above rather
        # than replacing it.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#D4
        tmpfiles.rules = lib.mkAfter [
          "a+ /storage - - - - user:immich:--x"
          # rwX (not rwx): X only sets execute on directories/already-
          # executable files, so regular photo/video files don't pick up
          # a spurious execute bit. Matters here specifically because
          # the library grant below is itself X-conditional and would
          # otherwise inherit an execute bit this rule set on every leaf
          # file.
          "A ${config.services.immich.mediaLocation} - - - - user:immich:rwX"
          # mediaLocation itself has no multimedia entry at all --
          # traversal into library/ still fails without this, since
          # POSIX requires +x on every directory in the path, not just
          # the leaf. r-X, not --x: execute-only got traversal working
          # (you could already reach mediaLocation/library directly if
          # you typed the exact path) but `ls` on mediaLocation itself
          # still needs read to list its children -- caught live, same
          # session, right after the first fix: torrent could reach
          # library/ by exact path but still got denied just cd-ing into
          # mediaLocation first, which is how anyone would actually go
          # looking for it. Read here only reveals the sibling directory
          # *names* (backups, thumbs, upload, ...), not their contents
          # -- those still have no grant of their own and stay
          # unreadable even once you can see they exist.
          "a+ ${config.services.immich.mediaLocation} - - - - group:multimedia:r-X"
          # Walks library/ a second time (the rwX re-lock above already
          # recursed over the whole tree including this). Deliberately
          # not merged into one pass: the only way to avoid the double
          # walk is to scope the re-lock above away from library/ by
          # enumerating mediaLocation's *other* subdirectories by name,
          # which would silently miss any new directory a future Immich
          # version adds -- trading a real correctness risk for a
          # boot-time-only performance gain. Accepted, not fixed.
          "A+ ${config.services.immich.mediaLocation}/library - - - - group:multimedia:r-X"
        ];
      };

      # no wg0 rule here, unlike jellyfin -- this is the whole point:
      # never reachable through vps's public Caddy+Anubis proxy.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        config.services.immich.port
      ];

      # database/redis: both default to local unix sockets, no secrets
      # needed. plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G2
      environment.persistence.${vars.persistRoot}.directories = [
        # postgres holds the actual photo/album/face metadata + embeddings
        # -- unlike mediaLocation (a real ZFS mount that already survives
        # reboots), this sits under root and gets wiped by the
        # impermanence rollback every boot without this. Explicit
        # user/group (not a bare string) to match jellyfin.nix's
        # convention rather than impermanence's root:root/0755 default.
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#F4
        {
          directory = "/var/lib/postgresql";
          user = "postgres";
          group = "postgres";
        }
      ];
    };
}

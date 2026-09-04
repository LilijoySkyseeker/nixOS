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
        # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#D5
        accelerationDevices = [
          "/dev/dri/renderD128" # Nvidia GTX 1050 Mobile (NVENC)
          "/dev/dri/renderD129" # Intel HD 630 (QSV/VAAPI fallback)
        ];
      };

      # matches jellyfin's exact working device-group membership
      # (modules/services/jellyfin.nix) -- accelerationDevices above
      # grants the cgroup device-controller permission, but the render
      # nodes are group-owned too, so immich also needs to actually be a
      # member to open() them.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#D5
      users.users.immich.extraGroups = [ "render" ];

      # the upstream module's own tmpfiles rule for mediaLocation is type
      # `e` (adjust mode if it already exists) -- a no-op for anything but
      # its own default /var/lib/immich, which systemd's StateDirectory=
      # creates for free. Since mediaLocation is overridden above, nothing
      # ever creates it without this `d` rule (merged into the same
      # "immich" settings group the upstream module already declares).
      # Caught live on first deploy: immich-server crash-looped on EACCES
      # trying to mkdir under a mediaLocation that didn't exist.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G4
      systemd.tmpfiles.settings.immich.${config.services.immich.mediaLocation}.d = {
        user = config.services.immich.user;
        group = config.services.immich.group;
        mode = "0700";
      };

      # /storage is drwxrws--- root:multimedia (hosts/homelab/configuration.nix)
      # -- immich is in neither, so it can't traverse into its own
      # mediaLocation without this, even once the directory above exists.
      # Non-recursive and additive (a+, not the existing recursive-replace
      # `A /storage ... group:multimedia:rwx` rule) and execute-only: this
      # only lets immich reach the one subpath it already fully owns, not
      # read/list jellyfin's actual media. Must come after that existing
      # rule (same generated file, mkAfter) or the next boot's recursive
      # replace-pass wipes this entry back out.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#G4
      #
      # SECURITY-LOAD-BEARING (F5, caught by post-deploy security review):
      # the existing `A /storage - - - - group:multimedia:rwx` rule above
      # is recursive and re-applies on *every* boot/switch. It has no
      # effect on mediaLocation only by accident of file-sort ordering on
      # the deploy that first created it (00-nixos.conf runs before this
      # module's `d` rule, so /storage/immich didn't exist yet when it
      # ran) -- the very next unrelated switch or reboot would recurse
      # into mediaLocation and grant the whole multimedia group read/write
      # ACL access to every photo Immich stores there, silently defeating
      # the 0700 immich:immich confidentiality D1(b)/F3 both relied on.
      # lilijoy's own account already holds that gid via the NFS mounts in
      # nfs-homelab-mounts.nix, so this needed no exploit, just normal use.
      # This second rule re-locks mediaLocation on every single boot/switch
      # too, recursively replacing any ACL entries the broad rule just set
      # underneath it with only immich's own -- ordered after both prior
      # rules via the same mkAfter list, so it always runs last and wins.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#F5
      #
      # torrent/thinkpad (trusted machines, same NFS multimedia-gid mount
      # jellyfin already uses) get read-only access to library/ -- the
      # organized original photos/videos -- but not the rest of the tree
      # (upload/ staging, thumbs/, encoded-video/, backups/ Postgres
      # dumps). Read-only, not read-write: Immich tracks every file's path
      # and checksum in its own database, so an external write (rename,
      # edit, delete) could desync that and corrupt Immich's own view of
      # the library -- a data-integrity risk, not a trust one. Ordered
      # last in this same list so it re-applies after F5's re-lock strips
      # everything, every boot/switch, additive (A+) so it doesn't wipe
      # immich's own entries set by the rule above.
      # plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#D4
      systemd.tmpfiles.rules = lib.mkAfter [
        "a+ /storage - - - - user:immich:--x"
        # rwX (not rwx): X only sets execute on directories/already-
        # executable files, so regular photo/video files don't pick up a
        # spurious execute bit. Matters here specifically because the
        # library grant below is itself X-conditional and would otherwise
        # inherit an execute bit this rule set on every leaf file.
        "A ${config.services.immich.mediaLocation} - - - - user:immich:rwX"
        # mediaLocation itself (the F5 rule above) has no multimedia entry
        # at all -- traversal into library/ still fails without this, since
        # POSIX requires +x on every directory in the path, not just the
        # leaf. r-X, not --x: execute-only got traversal working (you could
        # already reach mediaLocation/library directly if you typed the
        # exact path) but `ls` on mediaLocation itself still needs read to
        # list its children -- caught live, same session, right after the
        # first fix: torrent could reach library/ by exact path but still
        # got denied just cd-ing into mediaLocation first, which is how
        # anyone would actually go looking for it. Read here only reveals
        # the sibling directory *names* (backups, thumbs, upload, ...),
        # not their contents -- those still have no grant of their own and
        # stay unreadable even once you can see they exist.
        "a+ ${config.services.immich.mediaLocation} - - - - group:multimedia:r-X"
        "A+ ${config.services.immich.mediaLocation}/library - - - - group:multimedia:r-X"
      ];

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

{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.immich =
    { config, lib, ... }:
    {
      # immich: self-hosted photo/video backup, tailnet-only

      # version-exact so a bump re-breaks the build instead of silently
      # inheriting the exemption; accepted risk: docs/accepted-risks.md AR-9
      nixpkgs.config.permittedInsecurePackages = [ "immich-2.7.5" ];

      services.immich = {
        enable = true;
        # bind broad, restrict at the firewall below; openFirewall would also
        # open homelab's public IPv6 LAN address
        host = "0.0.0.0";
        # on jellyfin's zdata/storage/storage dataset (zrepl + restic backed)
        mediaLocation = "/storage/immich";
        # video transcoding only (not ML); backend is picked in immich's admin UI.
        # explicit rw: a bare path means DeviceAllow's wider rwm
        accelerationDevices = [
          "/dev/dri/renderD128 rw" # Nvidia GTX 1050 Mobile (NVENC)
          "/dev/dri/renderD129 rw" # Intel HD 630 (QSV/VAAPI fallback)
        ];
      };

      # GPU access for immich-server only: render group on the unit, not the
      # user (shared with the ML worker, which parses untrusted media), and
      # accelerationDevices lands on both units, so force the ML unit back off
      systemd = {
        services = {
          immich-server.serviceConfig.SupplementaryGroups = [ "render" ];
          immich-machine-learning.serviceConfig = {
            PrivateDevices = lib.mkForce true;
            DeviceAllow = lib.mkForce [ ];
          };
        };

        # upstream's `e` rule never creates a non-default mediaLocation
        tmpfiles.settings.immich.${config.services.immich.mediaLocation}.d = {
          user = config.services.immich.user;
          group = config.services.immich.group;
          mode = "0700";
        };

        # /storage is drwxrws--- root:multimedia: let immich traverse to its own
        # subpath only. must come after the host's recursive `A /storage` rule
        # (mkAfter) or the next boot's replace-pass wipes it
        #
        # SECURITY-LOAD-BEARING: the recursive multimedia grant on /storage
        # re-applies every boot and would leak into the 0700 mediaLocation; the
        # `A` below re-locks it each time (plan: 2026-09-03-add-immich-tailscale-only-to-homelab.md#F5)
        #
        # torrent/thinkpad (multimedia gid via NFS) get read-only library/:
        # immich tracks paths/checksums in its db, so external writes desync it
        tmpfiles.rules = lib.mkAfter [
          "a+ /storage - - - - user:immich:--x"
          # rwX: no execute bit on regular files (the library grant below is X-conditional)
          "A ${config.services.immich.mediaLocation} - - - - user:immich:rwX"
          # r-X: traverse and list into library/; sibling dirs stay unreadable
          "a+ ${config.services.immich.mediaLocation} - - - - group:multimedia:r-X"
          # second walk of library/ is deliberate: scoping the re-lock to the
          # other subdirs by name would miss any new one immich adds
          "A+ ${config.services.immich.mediaLocation}/library - - - - group:multimedia:r-X"
        ];
      };

      # tailnet only, never over wg0 from vps
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        config.services.immich.port
      ];

      # database/redis: local unix sockets, no secrets needed
      environment.persistence.${vars.persistRoot}.directories = [
        # photo/album/face metadata; on root, so wiped by the impermanence rollback without this
        {
          directory = "/var/lib/postgresql";
          user = "postgres";
          group = "postgres";
        }
      ];
    };
}

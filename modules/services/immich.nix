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

      # immich-machine-learning pulls in imageio, and pillow 13 fails two of
      # imageio's 16-bit PNG tests
      # TODO: drop when python313Packages.imageio builds on release-26.05 again (https://hydra.nixos.org/job/nixos/release-26.05/nixpkgs.python313Packages.imageio.x86_64-linux)
      nixpkgs.overlays = [
        (_: prev: {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (_: pyprev: {
              imageio = pyprev.imageio.overridePythonAttrs (old: {
                disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
                  "tests/test_pillow.py::test_png_16bit"
                  "tests/test_pillow_legacy.py::test_png"
                ];
              });
            })
          ];
        })
      ];

      services.immich = {
        enable = true;
        # bind broad, restrict at the firewall below; openFirewall would also
        # open homelab's public IPv6 LAN address
        host = "0.0.0.0";
        # on jellyfin's zdata/storage/storage dataset (zrepl + restic backed)
        mediaLocation = "/storage/immich";
      };

      systemd = {
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
        tmpfiles.rules = lib.mkAfter [
          "a+ /storage - - - - user:immich:--x"
          # rwX: no execute bit on regular files
          "A ${config.services.immich.mediaLocation} - - - - user:immich:rwX"
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

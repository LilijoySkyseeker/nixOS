{ config, ... }:
let
  vars = config.flake.vars;
in
{
  flake.modules.nixos.jellyfin =
    {
      config,
      lib,
      ...
    }:
    {
      # jellyfin
      services.jellyfin = {
        enable = true;
        group = "multimedia";
        configDir = "/srv/jellyfin/config";
        cacheDir = "/srv/jellyfin/cache";
        dataDir = "/srv/jellyfin/data";
        logDir = "/srv/jellyfin/log";

        # the module only writes encoding.xml if absent; force it so NixOS stays
        # the source of truth. unmodelled fields (EncoderPreset, tonemapping,
        # ...) revert to Jellyfin's defaults
        forceEncodingConfig = true;

        # GTX 1050 Mobile (NVENC/NVDEC) as primary transcoder; the Intel iGPU's
        # render node is granted below as a dashboard-selectable QSV/VAAPI fallback
        hardwareAcceleration = {
          enable = true;
          type = "nvenc";
          device = "/dev/dri/renderD128"; # Nvidia GTX 1050 Mobile
        };
        transcoding = {
          enableHardwareEncoding = true;
          hardwareDecodingCodecs = {
            h264 = true;
            hevc = true;
            hevc10bit = true;
            vc1 = true;
            vp8 = true;
            vp9 = true;
          };
          # av1 left off: GP107 (Pascal) NVENC has no AV1 encode block
          hardwareEncodingCodecs = {
            hevc = true;
          };
        };
      };

      # Intel HD 630's render node, for the QSV/VAAPI fallback described above.
      systemd.services.jellyfin.serviceConfig.DeviceAllow = lib.mkAfter [
        "/dev/dri/renderD129 rw"
      ];
      users.users.jellyfin.extraGroups = [ "render" ];

      # pinned gid: NFS clients (modules/nixos/nfs-homelab-mounts.nix) authorize
      # by numeric gid, so drift silently breaks /storage access
      users.groups.multimedia = {
        gid = vars.gids.multimedia;
        members = [ "jellyfin" ];
      };
      # no tmpfiles rules for jellyfin's dirs: upstream creates them at 0700
      # (jellyfinDirs.conf); raw rules here land in 00-nixos.conf, sort first
      # and would loosen that

      # tailnet only: homelab's LAN NIC has a public IPv6 address, so no host-wide rule
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8096 ];

      # persistence
      environment.persistence.${vars.persistRoot}.directories = with config.services.jellyfin; [
        {
          directory = configDir;
          inherit user group;
        }
        {
          directory = cacheDir;
          inherit user group;
        }
        {
          directory = dataDir;
          inherit user group;
        }
        {
          directory = logDir;
          inherit user group;
        }
      ];
    };
}

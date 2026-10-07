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

        # encoding.xml had drifted to HardwareAccelerationType=none and the
        # module silently stops applying config once the file exists (only
        # writes it if absent by default) -- force it so NixOS stays the
        # source of truth and this can't drift again unnoticed. Backs up the
        # prior file with a timestamp on every change. Loses a few fields
        # the module doesn't model (DownMixAudioBoost, MaxMuxingQueueSize,
        # EncoderPreset, DeinterlaceMethod, tonemapping algorithm/mode/
        # range, ...), which revert to Jellyfin's own defaults -- accepted.
        # plan: 2026-09-03-fix-homelab-jellyfin-ffmpeg-high-cpu-nvidia-driver-dropped-gtx-1050.md#D1
        forceEncodingConfig = true;

        # Nvidia GTX 1050 Mobile as primary transcoder: dedicated NVENC/NVDEC
        # blocks free the CPU entirely, and it's the stronger of this host's two
        # GPUs. The Intel iGPU's render node is also granted to the sandbox
        # below so QSV/VAAPI can be picked from the dashboard as a fallback
        # without touching this config.
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

      # pinned explicitly (rather than left to dynamic allocation) so its gid
      # stays stable across rebuilds — NFS clients (see
      # modules/nixos/nfs-homelab-mounts.nix) authorize purely by numeric
      # gid, so drift here would silently break their access to /storage and
      # /storage-bulk.
      users.groups.multimedia = {
        gid = vars.gids.multimedia;
        members = [ "jellyfin" ];
      };
      # No tmpfiles rules for jellyfin's own directories, on purpose. The
      # pinned nixpkgs jellyfin module already creates all four through the
      # typed systemd.tmpfiles.settings API (rendered as jellyfinDirs.conf)
      # at 0700 jellyfin:multimedia -- tighter than what this repo used to
      # declare. The four raw rules that were here duplicated that in
      # 00-nixos.conf at 0770, and since systemd-tmpfiles takes the first
      # line it sees per path and 00-nixos.conf sorts first, their only
      # effect was to *loosen* upstream from 0700 to 0770. Removed
      # 2026-08-28 -- see
      # 2026-08-28-fix-srv-permissions-stop-three-systems-fighting-ov.md.

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

{ config, pkgs, lib, ... }:
{
  # jellyfin
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    group = "multimedia";
    configDir = "/srv/jellyfin/config";
    cacheDir = "/srv/jellyfin/cache";
    dataDir = "/srv/jellyfin/data";
    logDir = "/srv/jellyfin/log";

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

  # The NixOS jellyfin module has no option for network.xml (only
  # encoding.xml, via services.jellyfin.transcoding/hardwareAcceleration)
  # — KnownProxies has to be patched into the XML ourselves. Without this,
  # every request through the vps -> Anubis -> Caddy -> wireguard chain
  # arrives at Jellyfin looking like it came from the tunnel IP rather
  # than the real client, which breaks Jellyfin's own per-IP failed-login
  # lockout (one bad actor could lock out every real user, since they'd
  # all look like the same source IP). Runs on every start so it's
  # idempotent and self-heals if the dashboard ever clears it; only
  # touches the KnownProxies element, leaving any other network.xml
  # settings made through the dashboard untouched.
  systemd.services.jellyfin.preStart = lib.mkAfter ''
    networkXml=${lib.escapeShellArg "${config.services.jellyfin.configDir}/network.xml"}
    if [ -f "$networkXml" ]; then
      ${lib.getExe' pkgs.xmlstarlet "xmlstarlet"} ed -L \
        -d '/NetworkConfiguration/KnownProxies/*' \
        -s '/NetworkConfiguration/KnownProxies' -t elem -n string -v '10.100.0.1' \
        -s '/NetworkConfiguration/KnownProxies' -t elem -n string -v '10.100.0.2' \
        "$networkXml"
    fi
  '';
  # pinned explicitly (rather than left to dynamic allocation) so its gid
  # stays stable across rebuilds — NFS clients (see
  # modules/nixos/nfs-homelab-mounts.nix) authorize purely by numeric
  # gid, so drift here would silently break their access to /storage and
  # /storage-bulk.
  users.groups.multimedia = {
    gid = 999;
    members = [ "jellyfin" ];
  };
  systemd.tmpfiles.rules = [
    "d ${config.services.jellyfin.configDir} 0770 jellyfin - - -"
    "d ${config.services.jellyfin.cacheDir} 0770 jellyfin - - -"
    "d ${config.services.jellyfin.dataDir} 0770 jellyfin - - -"
    "d ${config.services.jellyfin.logDir} 0770 jellyfin - - -"
  ];

  # networking
  networking.firewall.allowedTCPPorts = [ 8096 ];
  networking.firewall.allowedUDPPorts = [ 8096 ];

  # persistence
  environment.persistence."/nix/state".directories = with config.services.jellyfin; [
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
}

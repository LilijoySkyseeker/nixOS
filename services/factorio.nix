{ ... }:
{
  # networking
  networking.firewall.allowedUDPPorts = [ 34197 ];

  # persistence
  environment.persistence."/nix/state".directories = [ { directory = "/srv/factorio/main"; } ];

  # factorio server
  virtualisation.oci-containers.containers.factorio-main = {
    autoStart = true;
    image = "factoriotools/factorio:latest";
    ports = [ "34197:34197/udp" ];
    volumes = [ "/srv/factorio/main:/factorio" ];
    environment = {
      UPDATE_MODS_ON_START = "true";
    };
    # container hardening — see services/minecraft.nix for the same
    # pattern and troubleshooting note. Everything factorio's entrypoint
    # writes lives under /factorio (already a writable volume) or /tmp
    # (tmpfs below); if the container fails to start after this change,
    # check `docker logs factorio-main` for "Read-only file system".
    extraOptions = [
      "--read-only"
      "--tmpfs=/tmp:rw,nosuid,nodev,size=512m"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
  };
}

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
  };
}

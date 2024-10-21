{...}: {
  # networking
  services.caddy.virtualHosts."factorio.skyseekerhomelab.duckdns.org".extraConfig = ''
    reverse_proxy localhost:34197
  '';
  networking.firewall.allowedUDPPorts = [
    34197
  ];

  # persistence
  environment.persistence."/nix/state".directories = [
    {
      directory = "/srv/factorio/main";
    }
  ];

  # factorio server
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.factorio-main = {
    autoStart = true;
    image = "factoriotools/factorio";
    ports = [
      "34197:34197/udp"
    ];
    volumes = ["/srv/factorio/main:/factorio"];
  };
}

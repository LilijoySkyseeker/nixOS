# VM test: userns-remap puts a non-zero host uid under container uid 0
{
  pkgs,
  dockerUsernsModule,
}:
let
  # built locally: userns-remap changes dockerd's storage path, forcing a
  # re-pull the network-less VM can't do
  probeImage = pkgs.dockerTools.buildImage {
    name = "userns-remap-probe";
    tag = "test";
    copyToRoot = pkgs.buildEnv {
      name = "probe-root";
      paths = [ pkgs.busybox ];
    };
    config.Cmd = [
      "/bin/sh"
      "-c"
      "sleep infinity"
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "docker-userns-remap";

  nodes.remapped = _: {
    imports = [ dockerUsernsModule ];
    virtualisation = {
      docker.enable = true;
      oci-containers = {
        backend = "docker";
        containers.probe = {
          image = "userns-remap-probe:test";
          imageFile = probeImage;
          autoStart = true;
        };
      };
    };
    myDockerUserns.enable = true;
  };

  testScript = ''
    start_all()
    remapped.wait_for_unit("docker-probe.service")

    def host_uid_of_container(node, name="probe"):
        pid = node.succeed(f"docker inspect -f '{{{{.State.Pid}}}}' {name}").strip()
        return node.succeed(f"stat -c %u /proc/{pid}").strip()

    with subtest("remapped: dockremap's subuid range actually rendered"):
        subuid = remapped.succeed("cat /etc/subuid")
        assert "dockremap:10000000:65536" in subuid, f"subuid not set: {subuid!r}"
        # NixOS passes daemon.json as --config-file=<store path>, not
        # /etc/docker; `docker info` shows the live effective config
        security_opts = remapped.succeed("docker info --format '{{.SecurityOptions}}'")
        assert "name=userns" in security_opts, \
            f"userns-remap not active per dockerd itself: {security_opts!r}"

    with subtest("remapped: container root is NOT host uid 0"):
        # The probe's PID 1 is the /bin/sh entrypoint itself, which never
        # drops privileges -- so it's container uid 0, mapping to host
        # uid 0 + subIdStart.
        uid = host_uid_of_container(remapped)
        assert uid != "0", "container root is still host uid 0 -- remap not in effect"
        assert uid == "10000000", f"expected the mapped uid 10000000, got {uid!r}"
  '';
}

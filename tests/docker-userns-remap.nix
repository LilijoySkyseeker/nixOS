# VM test: userns-remap puts a non-zero host uid under container uid 0, and
# myDockerUserns.migrations keeps pre-existing bind-mount data usable
# two nodes rather than a live toggle: userns-remap isn't live-reloadable
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
      ''
        echo probe-wrote-this > /data/probe-marker &&
        cat /data/pre-existing >> /data/probe-marker &&
        id -u > /data/probe-uid-inside &&
        sleep infinity
      ''
    ];
  };

  # bind-mount data owned by the pre-remap uid (like /srv/factorio/main's 845:845)
  preSeed = [
    "d /srv/test-app 0755 845 845 -"
    "f /srv/test-app/pre-existing 0644 845 845 - already-here"
  ];

  probeContainer = {
    image = "userns-remap-probe:test";
    imageFile = probeImage;
    volumes = [ "/srv/test-app:/data" ];
    autoStart = true;
  };
in
pkgs.testers.runNixOSTest {
  name = "docker-userns-remap";

  nodes = {
    remapped = _: {
      imports = [ dockerUsernsModule ];
      virtualisation = {
        docker.enable = true;
        oci-containers = {
          backend = "docker";
          containers.probe = probeContainer;
        };
      };
      systemd.tmpfiles.rules = preSeed;
      myDockerUserns = {
        enable = true;
        migrations = [
          {
            path = "/srv/test-app";
            uid = 845;
            gid = 845;
          }
        ];
      };
    };

    # negative control: no remap, so container root is host root
    plain = _: {
      virtualisation = {
        docker.enable = true;
        oci-containers = {
          backend = "docker";
          containers.probe = probeContainer;
        };
      };
      systemd.tmpfiles.rules = preSeed;
    };

    # fail-closed: a failed migration must keep docker.service from starting
    brokenMigration =
      { lib, ... }:
      {
        imports = [ dockerUsernsModule ];
        virtualisation.docker.enable = true;
        systemd.tmpfiles.rules = preSeed;
        myDockerUserns = {
          enable = true;
          migrations = [
            {
              path = "/srv/test-app";
              uid = 845;
              gid = 845;
            }
          ];
        };
        systemd.services.docker-userns-remap-migrate.script = lib.mkForce "exit 1";
      };
  };

  testScript = ''
    start_all()
    remapped.wait_for_unit("docker-userns-remap-migrate.service")
    remapped.wait_for_unit("docker-probe.service")
    plain.wait_for_unit("docker.service")
    plain.wait_for_unit("docker-probe.service")

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

    with subtest("remapped: the pre-existing tree was actually migrated"):
        owner = remapped.succeed("stat -c %u:%g /srv/test-app/pre-existing").strip()
        assert owner == "10000845:10000845", f"migration did not run: {owner!r}"

    with subtest("remapped: container root is NOT host uid 0"):
        # The probe's PID 1 is the /bin/sh entrypoint itself, which never
        # drops privileges -- so it's container uid 0, mapping to host
        # uid 0 + subIdStart, not the 845 the *bind-mount data* uses.
        uid = host_uid_of_container(remapped)
        assert uid != "0", "container root is still host uid 0 -- remap not in effect"
        assert uid == "10000000", f"expected the mapped uid 10000000, got {uid!r}"

    with subtest("remapped: the container can read migrated data and write new data"):
        marker = remapped.succeed("cat /srv/test-app/probe-marker")
        assert "probe-wrote-this" in marker and "already-here" in marker, \
            f"container could not use its own pre-existing bind-mount data: {marker!r}"

    with subtest("remapped: the completion marker exists, outside the migrated tree"):
        marker = "/var/lib/docker-userns-remap-migrate/-srv-test-app.migrated"
        remapped.succeed(f"test -e {marker}")
        remapped.fail(f"test -e /srv/test-app/{marker.rsplit('/', 1)[-1]}")

    with subtest("remapped: the migration is idempotent on a second run"):
        remapped.succeed("systemctl restart docker-userns-remap-migrate.service")
        owner = remapped.succeed("stat -c %u:%g /srv/test-app/pre-existing").strip()
        assert owner == "10000845:10000845", f"second run changed ownership: {owner!r}"

    with subtest("plain (negative control): container root IS host uid 0"):
        uid = host_uid_of_container(plain)
        assert uid == "0", \
            f"expected the unpatched vulnerability (host uid 0), got {uid!r} -- test itself may be broken"

    with subtest("plain (negative control): pre-existing ownership is untouched"):
        owner = plain.succeed("stat -c %u:%g /srv/test-app/pre-existing").strip()
        assert owner == "845:845", f"expected untouched 845:845, got {owner!r}"

    with subtest("brokenMigration: a real migration failure actually blocks docker.service (fail-closed, requiredBy not wantedBy)"):
        brokenMigration.wait_for_unit("multi-user.target")
        migrate_state = brokenMigration.succeed(
            "systemctl is-failed docker-userns-remap-migrate.service"
        ).strip()
        assert migrate_state == "failed", f"expected the forced failure to register: {migrate_state!r}"
        docker_active = brokenMigration.get_unit_info("docker.service")["ActiveState"]
        assert docker_active != "active", \
            f"docker.service started despite its required migration failing: {docker_active!r}"
  '';
}

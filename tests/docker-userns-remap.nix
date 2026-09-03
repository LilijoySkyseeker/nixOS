# Does userns-remap actually put a real, non-zero host uid under a
# container's uid 0, and does the ownership migration for pre-existing
# bind-mount data (myDockerUserns.migrations) actually let the container
# read/write the data it already had before the remap was enabled?
#
# F-P4-07 / RESUME.md item 4: container uid 0 was host uid 0 on every
# bind mount. A build cannot prove any of this -- the security property
# under test is what the *host kernel* thinks a running container
# process's uid is, and whether pre-existing bind-mount files are still
# readable/writable after the remap, neither of which a Nix eval touches.
#
# Two otherwise-identical nodes, not a live toggle: Docker's own docs
# confirm userns-remap is not live-reloadable (changing it needs a full
# dockerd restart), so there's no "clear it and watch the same probe
# succeed" causation proof available the way anubis-admin-egress.nix
# does it -- the two-node comparison (matching push-deploy-sandbox.nix's
# deployer/deployer-broken shape) is the equivalent here.
{
  pkgs,
  dockerUsernsModule,
}:
let
  # Built locally, no network required -- see the plan's G6: enabling
  # userns-remap changes dockerd's storage path per remap user, which
  # would force a real re-pull of any registry image anyway, and the
  # sandboxed test VM has no network to do that with.
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

  # Shared by both nodes: a bind-mount directory with data already on it,
  # standing in for /srv/factorio/main's real 845:845 -- simulates a
  # host that already ran the container before userns-remap ever entered
  # the picture, which is the exact situation this migration exists for.
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

  nodes.remapped = _: {
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

  # Negative control: same container, same pre-seeded data, no remap at
  # all -- this is the vulnerability F-P4-07 describes, kept live in the
  # test so a regression that silently stops applying the remap shows up
  # as "the two nodes look the same" rather than nothing.
  nodes.plain = _: {
    virtualisation = {
      docker.enable = true;
      oci-containers = {
        backend = "docker";
        containers.probe = probeContainer;
      };
    };
    systemd.tmpfiles.rules = preSeed;
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
        assert "dockremap:100000:65536" in subuid, f"subuid not set: {subuid!r}"
        # NixOS passes the rendered daemon.json to dockerd via
        # --config-file=<store path> on the unit's own ExecStart, not
        # /etc/docker/daemon.json -- confirmed by reading docker.nix
        # itself (settingsFormat.generate, no /etc/docker anywhere).
        # `docker info` is dockerd's own live-effective-config view, more
        # robust than chasing the store path.
        security_opts = remapped.succeed("docker info --format '{{.SecurityOptions}}'")
        assert "name=userns" in security_opts, \
            f"userns-remap not active per dockerd itself: {security_opts!r}"

    with subtest("remapped: the pre-existing tree was actually migrated"):
        owner = remapped.succeed("stat -c %u:%g /srv/test-app/pre-existing").strip()
        assert owner == "100845:100845", f"migration did not run: {owner!r}"

    with subtest("remapped: container root is NOT host uid 0"):
        # The probe's PID 1 is the /bin/sh entrypoint itself, which never
        # drops privileges -- so it's container uid 0, mapping to host
        # uid 0 + subIdStart, not the 845 the *bind-mount data* uses.
        uid = host_uid_of_container(remapped)
        assert uid != "0", "container root is still host uid 0 -- remap not in effect"
        assert uid == "100000", f"expected the mapped uid 100000, got {uid!r}"

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
        assert owner == "100845:100845", f"second run changed ownership: {owner!r}"

    with subtest("plain (negative control): container root IS host uid 0"):
        uid = host_uid_of_container(plain)
        assert uid == "0", \
            f"expected the unpatched vulnerability (host uid 0), got {uid!r} -- test itself may be broken"

    with subtest("plain (negative control): pre-existing ownership is untouched"):
        owner = plain.succeed("stat -c %u:%g /srv/test-app/pre-existing").strip()
        assert owner == "845:845", f"expected untouched 845:845, got {owner!r}"
  '';
}

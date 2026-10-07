# VM test: the DOCKER-USER allowlist constrains a docker-published port
# a `-p` publish is DNAT'd and forwarded, never hitting INPUT, so
# `firewall.interfaces.<iface>.allowed*Ports` look right and do nothing;
# only real netfilter state and real packets prove the guard
{ pkgs, dockerPublishGuardModule }:
let
  # built locally so the test needs no network; answers one line on 8080
  listenerImage = pkgs.dockerTools.buildImage {
    name = "guard-test-listener";
    tag = "latest";
    copyToRoot = pkgs.buildEnv {
      name = "listener-root";
      paths = [
        pkgs.busybox
      ];
    };
    config.Cmd = [
      "/bin/sh"
      "-c"
      "while true; do echo reached | nc -l -p 8080; done"
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "docker-publish-guard";

  nodes.client = _: {
    environment.systemPackages = [ pkgs.netcat ];
  };

  nodes.machine =
    { ... }:
    {
      imports = [ dockerPublishGuardModule ];

      virtualisation.docker.enable = true;
      virtualisation.docker.daemon.settings.userland-proxy = false;

      # preload the local image: no registry, no network
      virtualisation.oci-containers.backend = "docker";
      virtualisation.oci-containers.containers.listener = {
        image = "guard-test-listener:latest";
        imageFile = listenerImage;
        ports = [ "8080:8080" ];
      };

      # dummy stand-ins for wg0 and tailscale0, so rules assert by name
      systemd.network.netdevs = {
        "10-wg0" = {
          netdevConfig = {
            Name = "wg0";
            Kind = "dummy";
          };
        };
        "10-tailscale0" = {
          netdevConfig = {
            Name = "tailscale0";
            Kind = "dummy";
          };
        };
      };

      myDockerPublishGuard = {
        enable = true;
        allowedInterfaces = [
          "wg0"
          "tailscale0"
        ];
        ports = [
          {
            port = 25565;
            protocol = "tcp";
            comment = "minecraft: java edition";
          }
          {
            port = 19132;
            protocol = "udp";
            comment = "minecraft: geyser bedrock listener";
          }
          {
            port = 34197;
            protocol = "udp";
            comment = "factorio";
          }
          {
            port = 8080;
            protocol = "tcp";
            comment = "the real container this test connects to";
          }
        ];
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("docker.service")
    machine.wait_for_unit("docker-publish-guard.service")
    machine.wait_for_unit("docker-listener.service")
    machine.wait_for_open_port(8080)
    client.wait_for_unit("multi-user.target")

    chain = "docker-publish-guard"

    with subtest("the guard chain exists and DOCKER-USER jumps into it"):
        docker_user = machine.succeed("iptables -S DOCKER-USER")
        assert f"-j {chain}" in docker_user, \
            f"DOCKER-USER does not jump to the guard chain:\n{docker_user}"

    with subtest("every guarded port allows both interfaces and drops the rest"):
        rules = machine.succeed(f"iptables -S {chain}")
        for proto, port in [("tcp", 25565), ("udp", 19132),
                            ("udp", 34197)]:
            # matched on components, not one exact string: the rule text
            # legitimately grows
            for iface in ["wg0", "tailscale0"]:
                accept = [
                    r for r in rules.splitlines()
                    if f"-i {iface}" in r and f"--dport {port}" in r
                    and f"-p {proto}" in r and "-j RETURN" in r
                ]
                assert accept, \
                    f"missing accept for {proto}/{port} on {iface}:\n{rules}"
            drop = [
                r for r in rules.splitlines()
                if f"--dport {port}" in r and f"-p {proto}" in r
                and "-j DROP" in r and "-i " not in r
            ]
            assert drop, f"missing drop for {proto}/{port}:\n{rules}"

    with subtest("the DROP comes after the RETURNs, or it would drop everything"):
        rules = machine.succeed(f"iptables -S {chain}").splitlines()
        for proto, port in [("tcp", 25565), ("udp", 19132),
                            ("udp", 34197)]:
            idx = [i for i, r in enumerate(rules)
                   if f"--dport {port} " in r and f"-p {proto}" in r]
            returns = [i for i in idx if "-j RETURN" in rules[i]]
            drops = [i for i in idx if "-j DROP" in rules[i]]
            assert returns and drops, f"no rules found for {proto}/{port}"
            assert max(returns) < min(drops), \
                f"DROP precedes RETURN for {proto}/{port} — allowed traffic would be dropped"

    with subtest("nothing else is filtered — the chain falls through"):
        # An unrelated forwarded port must not be touched, or this would
        # be a blanket firewall rather than a guard on named ports.
        rules = machine.succeed(f"iptables -S {chain}")
        assert "--dport 8096" not in rules, \
            "guard chain matched a port it was never given"

    # ---- the actual claim: a real packet, to a real container --------
    # rules existing proves nothing; prove behaviour, both directions

    with subtest("a client off an unlisted interface cannot reach the container"):
        # The client is on the test LAN (eth1), which is not in
        # allowedInterfaces. Its packets are DNAT'd toward the container
        # and must die in the guard chain.
        client.fail("nc -w 5 -z machine 8080")

    with subtest("and it is the guard doing it, not something else"):
        # Drop the guard and the very same connection must now succeed.
        # Without this, "connection failed" could mean a broken test rig.
        machine.succeed("systemctl stop docker-publish-guard.service")
        client.succeed("nc -w 5 -z machine 8080")
        out = client.succeed("nc -w 5 machine 8080")
        assert "reached" in out, f"connected but got unexpected payload: {out!r}"

    with subtest("restarting the guard closes it again"):
        machine.succeed("systemctl start docker-publish-guard.service")
        client.fail("nc -w 5 -z machine 8080")

    with subtest("guard rules only apply to traffic entering the bridge"):
        # --dport alone also matches a container's outbound same-port traffic
        # (factorio heartbeat, 34197 -> 34197); every rule needs -o docker0
        rules = machine.succeed(f"iptables -S {chain}").splitlines()
        for r in rules:
            if "--dport" not in r:
                continue
            assert "-o docker0" in r, \
                f"rule not pinned to the bridge, will match outbound traffic too:\n{r}"

    with subtest("a container's own outbound same-port traffic is not dropped"):
        # Send from inside the container to an outside address using the
        # guarded port as *source* and destination
        before = machine.succeed(
            f"iptables -vnL {chain} | grep 'dpt:34197' | tail -1"
        ).split()[0]
        machine.succeed(
            "docker exec listener sh -c "
            "'echo hi | nc -u -w 1 -p 34197 192.0.2.1 34197' || true"
        )
        after = machine.succeed(
            f"iptables -vnL {chain} | grep 'dpt:34197' | tail -1"
        ).split()[0]
        assert before == after, (
            f"the container's outbound packet hit the DROP rule "
            f"({before} -> {after}); the guard is filtering egress"
        )

    with subtest("the guard survives a docker restart"):
        # docker recreates the FORWARD -> DOCKER-USER jump on start. If
        # our jump were lost here, the ports would silently reopen.
        machine.succeed("systemctl restart docker.service")
        machine.wait_for_unit("docker.service")
        machine.wait_for_unit("docker-publish-guard.service")
        docker_user = machine.succeed("iptables -S DOCKER-USER")
        assert f"-j {chain}" in docker_user, \
            f"guard lost after docker restart:\n{docker_user}"
        rules = machine.succeed(f"iptables -S {chain}")
        assert "--dport 25565" in rules, \
            f"guard chain empty after docker restart:\n{rules}"

    with subtest("re-running converges instead of duplicating rules"):
        machine.succeed("systemctl restart docker-publish-guard.service")
        docker_user = machine.succeed("iptables -S DOCKER-USER")
        assert docker_user.count(f"-j {chain}") == 1, \
            f"duplicate jump into the guard chain:\n{docker_user}"
        rules = machine.succeed(f"iptables -S {chain}")
        assert rules.count("--dport 25565") == 3, \
            f"expected exactly 2 RETURNs + 1 DROP for 25565:\n{rules}"
  '';
}

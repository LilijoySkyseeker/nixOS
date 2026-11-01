{ pkgs, dockerPublishGuardModule }:
let
  # built locally so the test needs no network; answers one line on 8080
  # and 8081
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
      "while true; do echo reached | nc -l -p 8081; done & while true; do echo reached | nc -l -p 8080; done"
    ];
  };
in
pkgs.testers.runNixOSTest {
  name = "docker-publish-guard";

  nodes.client = _: {
    environment.systemPackages = [ pkgs.netcat ];
    # a LAN host the container must not be able to open connections to
    networking.firewall.allowedTCPPorts = [ 9000 ];
    systemd.services.lan-listener = {
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.netcat ];
      script = "nc -lk 9000";
    };
  };

  nodes.machine =
    { ... }:
    {
      imports = [ dockerPublishGuardModule ];

      virtualisation.docker.enable = true;
      virtualisation.docker.daemon.settings.userland-proxy = false;

      virtualisation.oci-containers.backend = "docker";
      virtualisation.oci-containers.containers.listener = {
        image = "guard-test-listener:latest";
        imageFile = listenerImage;
        ports = [
          "8080:8080"
          # unguarded: stands in for a player's connection the guard admits
          "8081:8081"
        ];
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
        rules = machine.succeed(f"iptables -S {chain}")
        assert "--dport 8096" not in rules, \
            "guard chain matched a port it was never given"


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

    egress = "docker-egress-guard"

    with subtest("egress to every private and special range is dropped, v4 and v6"):
        for cmd, nets in [
            ("iptables", ["0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10",
                          "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12",
                          "192.168.0.0/16", "224.0.0.0/3"]),
            ("ip6tables", ["::1/128", "fc00::/7", "fe80::/10", "ff00::/8"]),
        ]:
            rules = machine.succeed(f"{cmd} -t mangle -S {egress}")
            for net in nets:
                assert any(f"-d {net}" in r and "-i docker0" in r
                           and "--ctstate NEW" in r and "-j DROP" in r
                           for r in rules.splitlines()), \
                    f"{cmd}: no egress drop for {net}:\n{rules}"
            fwd = machine.succeed(f"{cmd} -t mangle -S FORWARD").splitlines()
            assert fwd[1] == f"-A FORWARD -j {egress}", \
                f"{cmd}: mangle FORWARD does not jump to the egress guard first:\n{fwd}"

    # the client sits on 192.168.1.0/24, standing in for the home LAN
    client_ip = client.succeed(
        "ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1"
    ).strip()
    client.wait_for_open_port(9000)

    with subtest("the container cannot open a connection to a LAN host"):
        # stand-in for tailscaled's ts-forward, which lands ahead of
        # DOCKER-USER and ACCEPTs everything out of tailscale0
        machine.succeed("iptables -I FORWARD 1 -o eth1 -j ACCEPT")
        machine.fail(
            f"docker exec listener sh -c 'echo hi | nc -w 3 {client_ip} 9000'"
        )

    with subtest("and it is the egress guard doing it"):
        machine.succeed("systemctl stop docker-publish-guard.service")
        machine.succeed(
            f"docker exec listener sh -c 'echo hi | nc -w 3 {client_ip} 9000'"
        )
        machine.succeed("systemctl start docker-publish-guard.service")
        machine.fail(
            f"docker exec listener sh -c 'echo hi | nc -w 3 {client_ip} 9000'"
        )
        machine.succeed("iptables -D FORWARD -o eth1 -j ACCEPT")

    with subtest("replies to an admitted connection from a private address pass"):
        # players' replies are ESTABLISHED, not NEW; the client's address is
        # private, so a stateless rule would break this
        out = client.succeed("nc -w 5 machine 8081")
        assert "reached" in out, f"reply to an admitted connection lost: {out!r}"

    with subtest("guard rules only apply to traffic entering the bridge"):
        rules = machine.succeed(f"iptables -S {chain}").splitlines()
        for r in rules:
            if "--dport" not in r:
                continue
            assert "-o docker0" in r, \
                f"rule not pinned to the bridge, will match outbound traffic too:\n{r}"

    with subtest("a container's own outbound same-port traffic is not dropped"):
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

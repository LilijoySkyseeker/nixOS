# VM test: Caddy serves the site on the tunnel address only, with its
# headers, 404 page, www redirect and status.json; the LAN gets nothing.
# Caddy's sandbox lets it reach the public internet only (the client
# stands in for it at 203.0.113.10), never the LAN, loopback or IPv6
# plain HTTP here: a VM can't get ACME certs, so the test swaps the site
# addresses for http:// ones and keeps everything else from the module
{ pkgs, websiteModule }:
let
  # stand-in for the built site: just enough pages to tell them apart
  site = pkgs.runCommand "test-site" { } ''
    mkdir -p $out/projects
    echo "lid-home-page" > $out/index.html
    echo "lid-projects-page" > $out/projects/index.html
    echo "lid-not-found-page" > $out/404.html
  '';
in
pkgs.testers.runNixOSTest {
  name = "website";

  # also "the internet": a web server and DNS on a public address added at runtime
  nodes.client = _: {
    environment.systemPackages = [ pkgs.curl ];
    systemd.services.probe-web = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        mkdir -p /tmp/probe && echo lid-probe-reached > /tmp/probe/index.html
        exec ${pkgs.python3}/bin/python3 -m http.server 8000 --bind 0.0.0.0 --directory /tmp/probe
      '';
    };
    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      # local: answer all of .test here, AAAA included, instead of forwarding to no upstream
      settings = {
        address = "/public.test/203.0.113.10";
        local = "/test/";
      };
    };
    networking.firewall.allowedTCPPorts = [
      53
      8000
    ];
    networking.firewall.allowedUDPPorts = [ 53 ];
  };

  nodes.machine =
    { lib, nodes, ... }:
    {
      imports = [ websiteModule ];
      _module.args.pkgs-stable = pkgs;

      # dummy stand-in for wg0, holding homelab's tunnel address
      systemd.network.enable = true;
      systemd.network.netdevs."10-wg0".netdevConfig = {
        Name = "wg0";
        Kind = "dummy";
      };
      # 10.100.0.1 too: the vps end, where every visitor comes from after its SNAT
      systemd.network.networks."10-wg0" = {
        matchConfig.Name = "wg0";
        address = [
          "10.100.0.2/24"
          "10.100.0.1/24"
        ];
      };

      services.caddy.virtualHosts."skyseekerlabs.net".hostName = lib.mkForce "http://skyseekerlabs.net";
      services.caddy.virtualHosts."www.skyseekerlabs.net".hostName =
        lib.mkForce "http://www.skyseekerlabs.net";
      services.caddy.virtualHosts."minecraft.skyseekerlabs.net".hostName =
        lib.mkForce "http://minecraft.skyseekerlabs.net";
      services.caddy.virtualHosts."factorio.skyseekerlabs.net".hostName =
        lib.mkForce "http://factorio.skyseekerlabs.net";
      services.caddy.virtualHosts."hytale.skyseekerlabs.net".hostName =
        lib.mkForce "http://hytale.skyseekerlabs.net";

      # no network to pull from: the test publishes the stand-in site itself
      systemd.timers.website-deploy.enable = false;
      systemd.tmpfiles.rules = [
        "d /var/lib/website 0755 root root -"
        "L+ /var/lib/website/current - - - - ${site}"
        "f /var/lib/website/deployed 0644 root root -"
      ];

      # caddy's lookups go through resolved's stub, as on homelab
      services.resolved.enable = true;
      networking.nameservers = [ "203.0.113.10" ];

      # caddy reaching out: each path proxies to a destination the sandbox should allow or refuse
      services.caddy.virtualHosts."http://probe.test".extraConfig = ''
        bind 10.100.0.2
        handle_path /public/* {
          reverse_proxy public.test:8000
        }
        handle_path /lan/* {
          reverse_proxy ${nodes.client.networking.primaryIPAddress}:8000
        }
        handle_path /loopback/* {
          reverse_proxy 127.0.0.1:8001
        }
        handle_path /ipv6/* {
          reverse_proxy [::1]:8001
        }
      '';
      # a local service caddy must not reach
      systemd.services.probe-local = {
        wantedBy = [ "multi-user.target" ];
        script = ''
          mkdir -p /tmp/probe && echo lid-local-reached > /tmp/probe/index.html
          exec ${pkgs.python3}/bin/python3 -m http.server 8001 --bind :: --directory /tmp/probe
        '';
      };

      environment.systemPackages = [ pkgs.curl ];
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("caddy.service")
    client.wait_for_unit("multi-user.target")
    client_lan = client.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()

    # from the vps's tunnel address, as every real visitor arrives
    def get(path, host="skyseekerlabs.net"):
        return machine.succeed(f"curl -s -D - --interface 10.100.0.1 -H 'Host: {host}' http://10.100.0.2{path}")

    machine.wait_until_succeeds("curl -s --max-time 2 --interface 10.100.0.1 http://10.100.0.2/")

    with subtest("pages are served from the published build"):
        assert "lid-home-page" in get("/")
        assert "lid-projects-page" in get("/projects/")

    with subtest("every response carries the security headers, and no Server header"):
        r = get("/").lower()
        for h in ["content-security-policy: default-src 'self'", "x-content-type-options: nosniff",
                  "referrer-policy: strict-origin-when-cross-origin", "strict-transport-security: max-age=86400"]:
            assert h in r, f"missing {h}:\n{r}"
        assert "\nserver:" not in r, f"Server header leaked:\n{r}"

    with subtest("a missing page gets the site's own 404"):
        r = get("/nope/")
        assert r.startswith("HTTP/1.1 404"), r
        assert "lid-not-found-page" in r, r

    with subtest("www redirects to the apex, keeping the path"):
        r = get("/projects/?x=1", host="www.skyseekerlabs.net")
        assert " 301" in r.splitlines()[0], r
        assert "location: https://skyseekerlabs.net/projects/?x=1" in r.lower(), r

    with subtest("a game server's address in a browser goes to its oops page"):
        for game in ["minecraft", "factorio", "hytale"]:
            r = get("/", host=f"{game}.skyseekerlabs.net")
            assert " 302" in r.splitlines()[0], r
            assert f"location: https://skyseekerlabs.net/oops/{game}/" in r.lower(), r

    with subtest("website-status writes status.json, served uncached"):
        machine.succeed("systemctl start website-status.service")
        r = get("/status.json")
        assert "cache-control: no-store" in r.lower(), r
        body = r.split("\r\n\r\n", 1)[1]
        import json
        status = json.loads(body)
        assert isinstance(status["uptime_days"], int), status
        assert status["deployed"] and status["deployed"].endswith("Z"), status
        assert "nixpkgs_days" in status, status

    with subtest("Caddy listens on the tunnel address only"):
        listeners = machine.succeed("ss -Htlnp | grep caddy")
        for line in listeners.splitlines():
            local = line.split()[3]
            assert local.startswith("10.100.0.2:"), f"caddy listening beyond the tunnel address: {line}"

    with subtest("the admin API is a socket only caddy can reach, and reload uses it"):
        machine.succeed("test -S /run/caddy/admin.sock")
        assert machine.succeed("stat -c %a:%U /run/caddy").strip() == "700:caddy"
        machine.succeed("systemctl reload caddy.service")
        assert "lid-home-page" in get("/")

    with subtest("caddy holds CAP_NET_BIND_SERVICE and nothing else"):
        pid = machine.succeed("systemctl show -P MainPID caddy.service").strip()
        status = machine.succeed(f"cat /proc/{pid}/status")
        for cap in ["CapBnd", "CapAmb", "CapEff"]:
            assert f"{cap}:\t0000000000000400" in status, status

    with subtest("the sandbox settings are in effect"):
        r = machine.succeed("systemctl show caddy.service -p ProtectSystem -p RestrictNamespaces -p ProtectKernelModules -p ProtectControlGroups")
        for want in ["ProtectSystem=strict", "RestrictNamespaces=yes", "ProtectKernelModules=yes", "ProtectControlGroups=yes"]:
            assert want in r, r

    with subtest("only the vps's address can reach caddy, not homelab's own"):
        machine.fail("curl -s --max-time 5 -H 'Host: skyseekerlabs.net' http://10.100.0.2/")

    with subtest("caddy reaches the public internet by name, as ACME needs"):
        client.succeed("ip addr add 203.0.113.10/32 dev eth1")
        client.wait_for_open_port(8000)
        machine.wait_for_open_port(8001)
        machine.succeed(f"ip route add 203.0.113.10/32 via {client_lan}")
        r = get("/public/", host="probe.test")
        assert "lid-probe-reached" in r, r

    with subtest("caddy can't reach the LAN, loopback services or IPv6"):
        # each is reachable from outside caddy, so a 502 is the sandbox
        machine.succeed(f"curl -sf http://{client_lan}:8000/ | grep -q lid-probe-reached")
        machine.succeed("curl -sf http://127.0.0.1:8001/ | grep -q lid-local-reached")
        machine.succeed("curl -sf 'http://[::1]:8001/' | grep -q lid-local-reached")
        for path in ["/lan/", "/loopback/", "/ipv6/"]:
            r = get(path, host="probe.test")
            assert r.startswith("HTTP/1.1 502"), f"{path}: {r}"

    with subtest("the LAN can't reach the site, even routed at the tunnel address"):
        machine_lan = machine.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()
        client.succeed(f"ip route add 10.100.0.2/32 via {machine_lan}")
        client.fail("curl -s --max-time 5 -H 'Host: skyseekerlabs.net' http://10.100.0.2/")
        client.fail(f"curl -s --max-time 5 -H 'Host: skyseekerlabs.net' http://{machine_lan}/")
  '';
}

# VM test: Caddy serves the site on the tunnel address only, with its
# headers, 404 page, www redirect and status.json; the LAN gets nothing
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

  nodes.client = _: {
    environment.systemPackages = [ pkgs.curl ];
  };

  nodes.machine =
    { lib, ... }:
    {
      imports = [ websiteModule ];
      _module.args.pkgs-stable = pkgs;

      # dummy stand-in for wg0, holding homelab's tunnel address
      systemd.network.enable = true;
      systemd.network.netdevs."10-wg0".netdevConfig = {
        Name = "wg0";
        Kind = "dummy";
      };
      systemd.network.networks."10-wg0" = {
        matchConfig.Name = "wg0";
        address = [ "10.100.0.2/24" ];
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

      environment.systemPackages = [ pkgs.curl ];
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("caddy.service")
    machine.wait_for_open_port(80, "10.100.0.2")
    client.wait_for_unit("multi-user.target")

    def get(path, host="skyseekerlabs.net"):
        return machine.succeed(f"curl -s -D - -H 'Host: {host}' http://10.100.0.2{path}")

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
            assert local.startswith("10.100.0.2:") or local.startswith("127.0.0.1:2019"), \
                f"caddy listening beyond the tunnel address: {line}"

    with subtest("the LAN can't reach the site, even routed at the tunnel address"):
        machine_lan = machine.succeed("ip -4 -o addr show eth1 | awk '{print $4}' | cut -d/ -f1").strip()
        client.succeed(f"ip route add 10.100.0.2/32 via {machine_lan}")
        client.fail("curl -s --max-time 5 -H 'Host: skyseekerlabs.net' http://10.100.0.2/")
        client.fail(f"curl -s --max-time 5 -H 'Host: skyseekerlabs.net' http://{machine_lan}/")
  '';
}

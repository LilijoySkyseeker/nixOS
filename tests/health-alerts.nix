{
  pkgs,
  healthAlertsModule,
}:
let
  fakehook = pkgs.writers.writePython3 "fakehook" { } ''
    import http.server


    class H(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers["Content-Length"]))
            with open("/run/fakehook/code") as f:
                code = int(f.read().strip())
            if code < 300:
                with open("/run/fakehook/posts", "ab") as f:
                    f.write(body + b"\n")
            self.send_response(code)
            self.end_headers()


    http.server.HTTPServer(("127.0.0.1", 8080), H).serve_forever()
  '';
in
pkgs.testers.runNixOSTest {
  name = "health-alerts";

  nodes.machine =
    { ... }:
    {
      imports = [ healthAlertsModule ];
      boot.supportedFilesystems = [ "zfs" ];
      networking.hostId = "8425e349";
      boot.zfs.forceImportRoot = false;
      virtualisation.emptyDiskImages = [ 4096 ];
      virtualisation.memorySize = 2048;

      environment.etc."health-webhook.conf".text = ''
        url = "http://127.0.0.1:8080/hook"
      '';

      myHealthAlerts = {
        enable = true;
        webhookUrlFile = "/etc/health-webhook.conf";
        checkSmart = false;
        # 0h: always stale, so both alert on every run
        backupStaleness = {
          "tank/a/home" = 0;
          "tank/b/home" = 0;
        };
      };

      systemd.services.fakehook = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = fakehook;
          RuntimeDirectory = "fakehook";
          RuntimeDirectoryPreserve = true;
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_open_port(8080)
    machine.succeed("zpool create -f -O compression=off tank /dev/vdb")
    for ds in ["tank/a", "tank/a/home", "tank/b", "tank/b/home"]:
        machine.succeed(f"zfs create {ds}")
    machine.succeed("zfs snapshot tank/a/home@s1 tank/b/home@s1")
    state = "/var/lib/health-alerts"

    def set_code(code):
        machine.succeed(f"echo {code} > /run/fakehook/code")

    def posts():
        return machine.succeed("cat /run/fakehook/posts 2>/dev/null || true")

    def run_check():
        return machine.execute("systemctl start health-check.service")[0]

    with subtest("a rejected post fails the unit and leaves no stamp"):
        set_code(500)
        assert run_check() != 0, "health-check should fail when every post is rejected"
        machine.succeed("journalctl -u health-check.service | grep -q 'could not post alert'")
        machine.fail(f"ls {state}/backup-stale-*")

    with subtest("an accepted post stamps it, one key per dataset"):
        set_code(200)
        assert run_check() == 0, "health-check should succeed once posts go through"
        machine.succeed(f"test -f {state}/backup-stale-tank-a-home")
        machine.succeed(f"test -f {state}/backup-stale-tank-b-home")
        assert "tank/a/home" in posts() and "tank/b/home" in posts()

    def fill_to(percent):
        i = 0
        while int(machine.succeed("zpool list -H -p -o capacity tank").strip()) < percent:
            machine.succeed(f"dd if=/dev/urandom of=/tank/fill{i} bs=1M count=100 status=none")
            machine.succeed("sync")
            i += 1
        return i

    with subtest("a pool past 80% warns"):
        n = fill_to(81)
        assert run_check() == 0
        assert "ZFS pool filling up" in posts(), posts()
        machine.succeed(f"test -f {state}/pool-warn-tank")

    with subtest("past 90% it alerts again despite the warning's cooldown"):
        before = posts().count("ZFS pool nearly full")
        machine.succeed("dd if=/dev/urandom of=/tank/big bs=1M count=1 status=none")
        i = 0
        while int(machine.succeed("zpool list -H -p -o capacity tank").strip()) < 91:
            machine.succeed(f"dd if=/dev/urandom of=/tank/more{i} bs=1M count=50 status=none")
            machine.succeed("sync")
            i += 1
        assert run_check() == 0
        assert posts().count("ZFS pool nearly full") == before + 1, posts()
        assert posts().count("ZFS pool filling up") == 1, posts()

    with subtest("back under 80% clears both"):
        machine.succeed("rm -f /tank/fill* /tank/more* /tank/big && sync")
        machine.wait_until_succeeds("test $(zpool list -H -p -o capacity tank) -lt 80")
        assert run_check() == 0
        machine.fail(f"test -e {state}/pool-warn-tank")
        machine.fail(f"test -e {state}/pool-critical-tank")
  '';
}

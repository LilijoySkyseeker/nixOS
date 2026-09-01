# Does anubis's IPAddressDeny/IPAddressAllow actually stop it reaching
# caddy's admin API, while the caddy -> anubis -> backend reverse-proxy
# chain over the unix socket keeps working?
#
# anubis sits outermost in the path of untrusted internet traffic, by
# design, and ships with a thorough syscall/namespace sandbox but no
# restriction on what it can *connect to*. Nothing stopped it reaching
# caddy's admin API on 127.0.0.1:2019, which can replace caddy's whole
# running config -- arbitrary reverse-proxy targets, a file_server rooted
# where the ACME account key lives, MITM of jellyfin
# (docs/audits/2026-08-26/findings-tail.md L-01). A build cannot prove
# this either way: IPAddressDeny/IPAddressAllow are a cgroup-attached BPF
# egress filter, invisible to anything short of exercising it, and the
# finding explicitly says so ("needs a VM test with a real request
# through caddy, not a unit start").
#
# This boots caddy + anubis for real, with a stand-in backend on the same
# non-loopback address anubis's real TARGET uses (10.100.0.2, the wg0
# tunnel address in production), and:
#   - proves the fix renders on the live unit, not just in the Nix eval
#   - proves a legitimate request still reaches the backend through the
#     whole chain (the thing that must not break)
#   - proves the restriction actually blocks anubis's own cgroup from
#     reaching the admin port, by migrating a probe shell into that exact
#     cgroup rather than trusting the rendered directive alone
#   - proves it is the restriction causing that, not something else, by
#     clearing it live and watching the same probe start succeeding
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "anubis-admin-egress";

  nodes.machine =
    { ... }:
    {
      # Stand-in for the wg0 tunnel address jellyfin's real TARGET lives
      # at, so IPAddressAllow is exercised against a real routable,
      # non-loopback address rather than 127.0.0.1.
      systemd.network.netdevs."10-backend0" = {
        netdevConfig = {
          Name = "backend0";
          Kind = "dummy";
        };
      };
      systemd.network.networks."10-backend0" = {
        matchConfig.Name = "backend0";
        address = [ "10.100.0.2/32" ];
      };
      networking.useNetworkd = true;

      systemd.tmpfiles.rules = [
        "d /srv/backend-stub 0755 root root -"
        "f /srv/backend-stub/index.html 0644 root root - backend-reached"
      ];
      systemd.services.jellyfin-stub = {
        description = "stand-in for jellyfin, answering on anubis's TARGET address";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.busybox}/bin/busybox httpd -f -v -p 10.100.0.2:8096 -h /srv/backend-stub";
      };

      # Same shape as the production fix (hosts/vps/configuration.nix):
      # anubis in front of a target, IPAddressDeny/Allow pinned to it.
      services.anubis.instances.jellyfin = {
        enable = true;
        settings.TARGET = "http://10.100.0.2:8096";
        # The test client is curl, not a browser -- bypass anubis's
        # proof-of-work challenge so a successful proxy is observable.
        # This test is about network reachability, not the challenge.
        policy = {
          useDefaultBotRules = false;
          extraBots = [
            {
              name = "allow-everything";
              user_agent_regex = ".*";
              action = "ALLOW";
            }
          ];
        };
      };
      systemd.services.anubis-jellyfin.serviceConfig = {
        IPAddressDeny = "any";
        IPAddressAllow = [ "10.100.0.2/32" ];
      };

      users.users.caddy.extraGroups = [ "anubis" ];
      systemd.services.caddy.after = [ "anubis-jellyfin.service" ];
      systemd.services.caddy.wants = [ "anubis-jellyfin.service" ];
      services.caddy = {
        enable = true;
        virtualHosts.":8080" = {
          extraConfig = ''
            reverse_proxy unix//run/anubis/anubis-jellyfin/anubis.sock {
              header_up X-Real-Ip {remote_host}
            }
          '';
        };
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("jellyfin-stub.service")
    machine.wait_for_open_port(8096, "10.100.0.2")
    machine.wait_for_unit("anubis-jellyfin.service")
    machine.wait_for_unit("caddy.service")

    def probe_from_anubis_cgroup(target):
        cgroup = machine.succeed(
            "systemctl show anubis-jellyfin.service -p ControlGroup --value"
        ).strip()
        return (
            f"echo $$ > /sys/fs/cgroup{cgroup}/cgroup.procs && "
            f"curl -s --max-time 5 -o /dev/null -w '%{{http_code}}' {target}"
        )

    with subtest("the restriction actually renders on the live unit"):
        deny = machine.succeed(
            "systemctl show anubis-jellyfin.service -p IPAddressDeny --value"
        ).strip()
        allow = machine.succeed(
            "systemctl show anubis-jellyfin.service -p IPAddressAllow --value"
        ).strip()
        # systemd normalises "any" into its two constituent prefixes when
        # reporting the effective value back.
        assert "0.0.0.0/0" in deny and "::/0" in deny, f"IPAddressDeny not applied: {deny!r}"
        assert "10.100.0.2/32" in allow, f"IPAddressAllow missing the target: {allow!r}"

    with subtest("caddy still serves through anubis to the real backend"):
        out = machine.succeed("curl -s --max-time 5 http://127.0.0.1:8080/")
        assert "backend-reached" in out, f"reverse proxy chain broken: {out!r}"

    with subtest("anubis's own cgroup cannot reach caddy's admin API"):
        machine.fail(probe_from_anubis_cgroup("http://127.0.0.1:2019/config/"))

    with subtest("and the same cgroup can still reach the real backend"):
        # Confirms the previous failure is the admin port specifically
        # being denied, not the probe technique itself being broken.
        code = machine.succeed(
            probe_from_anubis_cgroup("http://10.100.0.2:8096/")
        ).strip()
        assert code == "200", f"expected the backend reachable, got {code!r}"

    with subtest("and it is the restriction doing it, not something else"):
        machine.succeed(
            "systemctl set-property anubis-jellyfin.service "
            "IPAddressDeny= IPAddressAllow="
        )
        code = machine.succeed(
            probe_from_anubis_cgroup("http://127.0.0.1:2019/config/")
        ).strip()
        assert code == "200", (
            f"expected the admin API reachable once the restriction is cleared, got {code!r}"
        )
  '';
}

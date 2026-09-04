# Does the rate-limited replacement for logRefusedConnections actually log
# refused connections, cap a burst, survive a firewall restart without
# duplicating, and leave real refusal behaviour (the security boundary)
# untouched -- or does it just look right in the rendered iptables rules?
#
# This exists because it almost shipped broken: the first version of this
# rule appended (-A) into nixos-fw-log-refuse, which the module already
# terminates with an unconditional refuse jump by the time extraCommands
# runs -- the rule built cleanly, rendered correctly, and never matched a
# single packet (G4 in
# 2026-09-03-troubleshoot-fail2ban-vps-closed-port-scan-journal-stall.md).
# Only /simplify's efficiency pass caught it, by tracing the *built*
# script's actual rule order -- nixos-rebuild build and nix flake check
# both passed the whole time. A VM test that fires a real refused
# connection and checks the real kernel log is the only thing that would
# have caught this the same way live traffic eventually would have.
#
# Also proves the piece CrowdSec's crowdsecurity/iptables-scan-multi_ports
# scenario actually depends on: that a refused connection lands in the
# _TRANSPORT=kernel journal with the exact log-prefix its acquisition
# reads. What this test deliberately does NOT attempt: CrowdSec's hub
# collections (crowdsecurity/iptables included) are fetched live from
# CrowdSec's own servers at service start (cscli hub update/install),
# which this repo's sandboxed VM-test build has no path to reach -- so
# whether the scenario itself fires a ban on a simulated scan is not
# testable here. See D6 in the same plan for that scoping decision.
#
# Loopback traffic never reaches nixos-fw-log-refuse at all (the module's
# own nixos-fw-accept -i lo rule accepts it unconditionally, earlier in
# the chain) -- a single-node test connecting to itself would prove
# nothing. Two nodes, same shape as tests/docker-publish-guard.nix.
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "vps-refused-connection-logging";

  nodes.client = _: {
    environment.systemPackages = [
      pkgs.netcat
      pkgs.nmap
    ];
  };

  nodes.machine = _: {
    # Same shape as the production fix (hosts/vps/configuration.nix):
    # disable the module's own unlimited LOG rule, replace with a
    # rate-limited equivalent inserted ahead of the chain's own refuse
    # jump, not appended after it.
    networking.firewall.logRefusedConnections = false;
    networking.firewall.extraCommands = ''
      iptables -I nixos-fw-log-refuse 1 -p tcp --syn \
        -m limit --limit 50/sec --limit-burst 100 \
        -j LOG --log-level info --log-prefix "refused connection: "
      ip6tables -I nixos-fw-log-refuse 1 -p tcp --syn \
        -m limit --limit 50/sec --limit-burst 100 \
        -j LOG --log-level info --log-prefix "refused connection: "
    '';
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("firewall.service")
    client.wait_for_unit("multi-user.target")

    with subtest("a refused connection is actually refused, not silently accepted"):
        # Nothing in allowedTCPPorts -- default policy is DROP (rejectPackets
        # defaults false), so the connect attempt times out rather than resets.
        client.fail("nc -w 2 -z machine 9999")

    with subtest("the refused connection produces a rate-limited LOG line"):
        client.fail("nc -w 2 -z machine 9998")
        machine.sleep(1)
        # nc's SYN gets retransmitted by the client's own TCP stack while it
        # waits out the 2s timeout (DROP gives no RST to stop it) -- so this
        # is "at least one", not "exactly one". The rate limit capping a
        # *fast* burst is covered by its own subtest below.
        out = machine.succeed(
            "journalctl -k --no-pager | grep -c 'refused connection:.*DPT=9998' || true"
        ).strip()
        assert int(out) >= 1, f"expected at least one LOG line for the probe, got {out!r}"

    with subtest("the LOG rule is scoped to _TRANSPORT=kernel, matching CrowdSec's acquisition filter"):
        out = machine.succeed(
            "journalctl -o cat _TRANSPORT=kernel --no-pager | grep -c 'refused connection:.*DPT=9998'"
        ).strip()
        assert int(out) >= 1, (
            f"the exact journalctl_filter CrowdSec's acquisition uses doesn't see it: {out!r}"
        )

    with subtest("a fast burst is capped by the rate limit, not logged unbounded"):
        # nmap as root defaults to a raw SYN scan -- exactly what the -p tcp
        # --syn match is watching for. 250 ports, well past the 100-packet
        # burst, proves the cap actually bites rather than just being present.
        client.succeed("nmap -Pn -T5 --max-retries 0 -p 1-250 machine || true")
        machine.sleep(2)
        count = int(machine.succeed(
            "journalctl -k --no-pager | grep -c 'refused connection:' || true"
        ).strip())
        assert 10 < count < 200, (
            f"expected the burst capped near the 100-packet limit (plus the "
            f"2 earlier probes), got {count} lines -- either the limit isn't "
            f"biting (too high) or the rule isn't matching at all (too low)"
        )

    with subtest("restarting the firewall does not duplicate the rate-limited rule"):
        machine.succeed("systemctl restart firewall.service")
        rules = machine.succeed("iptables -S nixos-fw-log-refuse")
        assert rules.count("refused connection:") == 1, (
            f"expected exactly one rate-limited LOG rule after one restart:\n{rules}"
        )
        machine.succeed("systemctl restart firewall.service")
        rules = machine.succeed("iptables -S nixos-fw-log-refuse")
        assert rules.count("refused connection:") == 1, (
            f"expected exactly one rate-limited LOG rule after two restarts:\n{rules}"
        )

    with subtest("and refusal still works after a restart"):
        client.fail("nc -w 2 -z machine 9997")
  '';
}

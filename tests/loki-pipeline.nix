# End-to-end test of the fleet log pipeline: an Alloy shipper node reads
# its own journal and pushes to a Loki aggregator node, whose ruler
# evaluates the launch alert rules into a localhost Alertmanager.
#
# What only fails at runtime, and therefore needs a booted VM:
# - the River config's syntax and component wiring (services.alloy just
#   points at /etc/alloy; nothing validates the config at build time)
# - Alloy actually being able to read the journal as the pinned real
#   `alloy` user (the module's DynamicUser is forced off for
#   impermanence's sake -- a wrong group membership only shows up live)
# - Loki accepting the generated JSON config at startup (`-verify-config`
#   runs at build, but ruler/compactor dirs only materialize at runtime)
# - the ruler loading the rules dir (a wrong tenant layout loads zero
#   rules, silently) and reaching Alertmanager
# - the alertmanager-discord-env oneshot's sed extraction feeding
#   envsubst a URL Alertmanager will parse
# - label shape end-to-end: the alert rules select on {host=, unit=,
#   identifier=} -- a relabel typo makes every rule silently dead
#
# The shipper VM is sized at 1GB like vps; the test prints Alloy's cgroup
# MemoryCurrent (overstates RSS -- includes reclaimable page cache, see G10)
# as an early data point for the plan's D15/D16 measurement (the binding
# measurement still happens on the real vps under real volume).
# plan: 2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md
{
  pkgs,
  lokiModule,
  alloyModule,
  impermanenceModule,
}:
pkgs.testers.runNixOSTest {
  name = "loki-pipeline";

  node.specialArgs = {
    # the alloy module pins its package from the stable tree; in the test
    # both trees are whatever `pkgs` the check was instantiated with
    pkgs-stable = pkgs;
  };

  nodes = {
    aggregator =
      { ... }:
      {
        imports = [ lokiModule ];
        virtualisation.memorySize = 2048;
        # stand-in for homelab's sops-provisioned secret, same curl -K
        # format the real extraction parses
        myLoki.alertWebhookFile = builtins.toString (
          pkgs.writeText "fake-webhook" ''
            url = "http://127.0.0.1:9/discord-sink-that-never-answers"
          ''
        );
        # the real firewall rule is tailscale0-scoped; the test network has
        # no tailscale, so open the port on the test NIC instead
        networking.firewall.allowedTCPPorts = [ 3100 ];
      };

    shipper =
      { ... }:
      {
        imports = [
          alloyModule
          impermanenceModule
        ];
        # 1GB like vps, the fleet's tightest host
        virtualisation.memorySize = 1024;
        myAlloy = {
          enable = true;
          lokiUrl = "http://aggregator:3100/loki/api/v1/push";
        };
      };
  };

  testScript = ''
    start_all()

    with subtest("aggregator services come up"):
        aggregator.wait_for_unit("loki.service")
        aggregator.wait_for_unit("alertmanager.service")
        aggregator.wait_for_open_port(3100)
        aggregator.wait_for_open_port(9093)

    with subtest("webhook env extraction produced a URL"):
        aggregator.succeed(
            "grep -q '^DISCORD_WEBHOOK_URL=http' /run/alertmanager-discord.env"
        )

    with subtest("ruler loaded the launch rules"):
        aggregator.wait_until_succeeds(
            "curl -sf http://127.0.0.1:3100/loki/api/v1/rules", timeout=60
        )
        rules = aggregator.succeed(
            "curl -sf http://127.0.0.1:3100/loki/api/v1/rules"
        )
        for rule in ["VpsDeployRejected", "Run0Escalation", "FirewallFailed"]:
            assert rule in rules, f"{rule} missing from loaded ruler rules"

    with subtest("shipper's alloy starts and reads the journal"):
        shipper.wait_for_unit("alloy.service")
        # any parse error in the River config is fatal at startup, but give
        # the unit a moment to prove it stays up
        shipper.succeed("sleep 5")
        shipper.succeed("systemctl is-active alloy.service")

    with subtest("a journal line reaches Loki with the expected labels"):
        shipper.succeed("logger -t pipelinetest loki-pipeline-canary-line")
        aggregator.wait_until_succeeds(
            "logcli --addr=http://127.0.0.1:3100 query --limit=5 "
            "'{host=\"shipper\", identifier=\"pipelinetest\"}' 2>/dev/null "
            "| grep -q loki-pipeline-canary-line",
            timeout=120,
        )

    with subtest("a matching event raises an alert in Alertmanager"):
        # the Run0Escalation rule matches this PAM line text on any host
        shipper.succeed(
            "logger 'pam_unix(systemd-run0:session): session opened for user root(uid=0) by (uid=0)'"
        )
        aggregator.wait_until_succeeds(
            "curl -sf http://127.0.0.1:9093/api/v2/alerts | grep -q Run0Escalation",
            timeout=240,
        )

    with subtest("alloy memory data point on a 1GB node"):
        mem = shipper.succeed(
            "systemctl show alloy.service -p MemoryCurrent --value"
        ).strip()
        print(f"alloy MemoryCurrent on 1GB shipper: {mem} bytes")
  '';
}

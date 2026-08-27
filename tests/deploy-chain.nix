# Does a *skipped* scheduled switch still trigger the follow-on deploy?
#
# It used to. homelab wired `systemd.services.auto-switch.onSuccess =
# [ "push-deploy-vps.service" ]`, and every guard in deployGuardsScript ends
# in `exit 0`, so systemd could not tell a deferred run from a real one.
# Caught live on homelab, 2026-08-25T13:18:15:
#
#   auto-switch-start: Last switch activated 23 seconds ago
#     (minimum 604800), skipping this scheduled run.
#   systemd: auto-switch.service: Deactivated successfully.
#   systemd: auto-switch.service: Triggering OnSuccess= dependencies.
#   systemd: Starting Build locally and push+activate vps on vps-deploy@vps...
#
# The min-interval guard deferred the switch and systemd started the vps
# closure build anyway — the contention that guard exists to avoid
# (F-P7-09, consequence 1).
#
# The replacement gates the follow-on on a flag the switch script only
# writes after a real activation. This test drives the *rendered*
# ExecStartPost script out of the built system rather than a copy of it, so
# it cannot pass against a version of the logic that is not the one shipped.
{ pkgs, autoUpdateModule }:
pkgs.testers.runNixOSTest {
  name = "deploy-chain";

  nodes.machine =
    { lib, ... }:
    {
      imports = [ autoUpdateModule ];

      myAutoUpdate = {
        enable = true;
        hostAttr = "machine";
        onDeployUnits = [ "chained.service" ];
      };

      # Stands in for push-deploy-vps: records that it was started, and
      # nothing else. Not wanted by anything, so only an explicit start
      # (or the OnSuccess= regression) can run it.
      systemd.services.chained = {
        description = "Follow-on deploy stand-in";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/touch /run/chained-ran";
        };
      };

      # The timers would never fire inside a test run anyway (default
      # OnCalendar is Sun 02:00/04:00), but leaving them off removes any
      # chance of a scheduled run racing the assertions below.
      systemd.timers.auto-switch.enable = lib.mkForce false;
      systemd.timers.flake-update-test.enable = lib.mkForce false;
    };

  testScript = ''
    import shlex

    machine.wait_for_unit("multi-user.target")

    def exec_start_post(unit):
        """The rendered ExecStartPost command lines, in order."""
        raw = machine.succeed(f"systemctl show {unit} -p ExecStartPost --value")
        return [
            tok[len("path=") :]
            for line in raw.splitlines()
            for tok in shlex.split(line)
            if tok.startswith("path=")
        ]

    with subtest("the OnSuccess= that caused the bug is gone"):
        # A regression guard on the specific wiring, not on behaviour:
        # re-adding OnSuccess= would reintroduce the live failure above
        # while every other assertion here still passed.
        for prop in ["OnSuccess", "OnSuccessJobMode"]:
            out = machine.succeed(
                f"systemctl show auto-switch.service -p {prop} --value"
            ).strip()
            assert "chained" not in out, \
                f"auto-switch still chains via {prop}=: {out!r}"

    with subtest("the follow-on is wired as a gated ExecStartPost instead"):
        posts = exec_start_post("auto-switch.service")
        assert any("start-on-deploy" in p for p in posts), \
            f"no start-on-deploy in ExecStartPost: {posts}"
        # Ordering is load-bearing: the reboot check must come first, so a
        # kernel-changing deploy asks for the reboot before we queue more
        # work onto a machine that is going down.
        reboot_at = next(i for i, p in enumerate(posts) if "reboot-if-kernel" in p)
        chain_at = next(i for i, p in enumerate(posts) if "start-on-deploy" in p)
        assert reboot_at < chain_at, \
            f"start-on-deploy runs before the reboot check: {posts}"

    trigger = next(p for p in exec_start_post("auto-switch.service")
                   if "start-on-deploy" in p)

    # RuntimeDirectory= is what makes the flag un-stale-able: systemd
    # recreates it on every start. Assert it is actually set, since the
    # gate silently fails open-ish (never chains) if RUNTIME_DIRECTORY is
    # empty, and that would look like "works" in a passing test.
    with subtest("the flag lives in a per-unit RuntimeDirectory"):
        for unit, want in [
            ("auto-switch.service", "auto-switch"),
            ("auto-switch-now.service", "auto-switch-now"),
        ]:
            got = machine.succeed(
                f"systemctl show {unit} -p RuntimeDirectory --value"
            ).strip()
            assert got == want, f"{unit}: RuntimeDirectory={got!r}, wanted {want!r}"

    machine.succeed("mkdir -p /run/auto-switch")

    with subtest("a skipped run does not start the follow-on"):
        machine.succeed("rm -f /run/chained-ran /run/auto-switch/switched")
        out = machine.succeed(f"RUNTIME_DIRECTORY=/run/auto-switch {trigger} 2>&1")
        assert "not starting" in out, f"unexpected output: {out!r}"
        # Give a wrongly-queued job a chance to actually run before
        # concluding it did not — asserting on absence immediately would
        # pass even if the start had been issued.
        machine.sleep(2)
        machine.fail("test -e /run/chained-ran")
        machine.succeed("test $(systemctl show chained.service -p NRestarts --value) = 0")

    with subtest("a real switch does start the follow-on"):
        machine.succeed("rm -f /run/chained-ran")
        machine.succeed("touch /run/auto-switch/switched")
        machine.succeed(f"RUNTIME_DIRECTORY=/run/auto-switch {trigger} 2>&1")
        machine.wait_for_file("/run/chained-ran")

    with subtest("the trigger exits 0 on both paths"):
        # It runs as ExecStartPost, so any non-zero exit marks the whole
        # deploy failed and pages for it. Both paths must be clean: the
        # skip path (nothing to do) and the chain path (the follow-on has
        # been queued, and whether *it* succeeds is its own business).
        for flag in ["rm -f", "touch"]:
            machine.succeed(f"{flag} /run/auto-switch/switched")
            machine.succeed(
                "RUNTIME_DIRECTORY=/run/auto-switch "
                + shlex.quote(trigger)
                + " >/dev/null 2>&1"
            )

    with subtest("auto-switch-now deliberately does not chain"):
        posts = exec_start_post("auto-switch-now.service")
        assert not any("start-on-deploy" in p for p in posts), \
            f"manual-trigger unit should not chain: {posts}"
  '';
}

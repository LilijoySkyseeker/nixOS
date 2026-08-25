# Integration test for modules/nixos/zfs-space-guard.nix.
#
# `nixos-rebuild build` only proves the generated units parse -- it can't
# prove any of the actual pruning logic, because the real pools/datasets
# don't exist at build time. This module has been enabled on torrent and
# thinkpad since the zrepl migration but was never exercised (see the
# still-open "sanity-check zfs-space-guard.timer" item in TODO.md). This
# test builds a throwaway VM with a real zpool and exercises the parts that
# only fail at runtime:
#
#   * a healthy pool leaves every snapshot alone
#   * crossing freeThresholdPercent prunes the oldest snapshots down to
#     exactly keepMin, per dataset
#   * a second run at the same pressure destroys nothing further (the
#     keepMin floor, not just a one-time trim)
#   * a zrepl-style hold on a snapshot makes its `zfs destroy` fail, and the
#     script tolerates that (`|| true`) rather than aborting the run --
#     other prunable snapshots still get destroyed
#   * zfs-emergency-prune.service ignores the threshold and keepMin
#     entirely, keeping only the single newest snapshot per dataset
#   * a `zpool list` failure (bad pool name, exported pool, transient
#     hiccup) now aborts the run instead of silently falling through to an
#     unconditional prune -- this is the regression test for a real bug
#     found while reviewing the module: `[ "$cap" -lt N ]` on an
#     empty/garbage `$cap` errors, and bash treats a failed `[ ]` as the
#     `if` being false, so the *old* script fell through to the prune
#     branch on any zpool-list hiccup. Confirmed directly:
#       $ bash -c 'cap=""; if [ "$cap" -lt 85 ]; then echo skip; else echo PRUNE; fi'
#       bash: line 1: [: : integer expected
#       PRUNE
#     Fixed by validating $cap is non-empty and numeric before the
#     threshold check, and exiting 1 instead of falling through when it
#     isn't.
#
# Kept as a regression test, not a one-off verification: the module is
# still being tuned (freeThresholdPercent/keepMin per host) and its failure
# mode is quiet in both directions -- silently over-pruning local rollback
# points, or silently never pruning and letting a pool fill up -- either of
# which you'd only discover under real space pressure. Delete it if the
# module is ever replaced.
#
# Writing or debugging one of these: docs/procedures/vm-testing.md.
{
  pkgs,
  zfsSpaceGuardModule,
}:
let
  zfsNode = hostId: diskSizeMiB: {
    boot.supportedFilesystems = [ "zfs" ];
    networking.hostId = hostId;
    virtualisation.emptyDiskImages = [ diskSizeMiB ];
    virtualisation.memorySize = 2048;
    # Pools are created by the test script after boot.
    boot.zfs.forceImportRoot = false;
  };
in
pkgs.testers.runNixOSTest {
  name = "zfs-space-guard";

  nodes = {
    # Main functional test bed: a real pool, real pressure, real holds.
    guard =
      { ... }:
      {
        imports = [ zfsSpaceGuardModule ];
        inherit (zfsNode "0badc0de" 1024) boot networking virtualisation;

        myZfsSpaceGuard = {
          enable = true;
          pool = "guardpool";
          datasets = [
            "guardpool/a"
            "guardpool/b"
          ];
          freeThresholdPercent = 20; # trigger once used capacity >= 80%
          keepMin = 2;
        };
      };

    # Dedicated to the fail-safe regression: configured to watch a pool
    # name that doesn't exist, so `zpool list` fails for real.
    badpool =
      { ... }:
      {
        imports = [ zfsSpaceGuardModule ];
        inherit (zfsNode "deadfeed" 256) boot networking virtualisation;

        myZfsSpaceGuard = {
          enable = true;
          pool = "ghostpool"; # deliberately not the pool actually created below
          datasets = [ "realpool/data" ];
          freeThresholdPercent = 20;
          keepMin = 2;
        };
      };
  };

  testScript = ''
    start_all()
    guard.wait_for_unit("multi-user.target")
    badpool.wait_for_unit("multi-user.target")

    def snap_names(node, dataset):
        out = node.succeed(
            f"zfs list -H -o name -t snapshot -s creation {dataset}"
        )
        return [line.split("@", 1)[1] for line in out.strip().splitlines() if line]

    with subtest("pool and datasets exist before any check runs"):
        guard.succeed("zpool create -f guardpool /dev/vdb")
        guard.succeed("zfs create guardpool/a")
        guard.succeed("zfs create guardpool/b")
        # compression=off: /dev/zero writes below would otherwise compress
        # away to almost nothing and never actually raise pool capacity.
        guard.succeed("zfs create -o compression=off guardpool/filler")
        for ds in ["a", "b"]:
            for i in range(1, 6):
                guard.succeed(f"zfs snapshot guardpool/{ds}@s{i}")

    with subtest("healthy pool: nothing pruned under the free-space threshold"):
        guard.succeed("systemctl start zfs-space-guard.service")
        assert snap_names(guard, "guardpool/a") == ["s1", "s2", "s3", "s4", "s5"]
        assert snap_names(guard, "guardpool/b") == ["s1", "s2", "s3", "s4", "s5"]

    with subtest("pressure: oldest snapshots pruned down to keepMin, newest survive"):
        # Fill in small steps and tolerate ENOSPC near the end -- the pool's
        # actual writable ceiling is a bit below 100% capacity (slop space,
        # metadata overhead), so it can refuse a write before the capacity
        # reading itself reaches the target.
        cap = 0
        i = 0
        while cap < 82:
            i += 1
            assert i < 200, f"pool did not reach the pressure threshold -- adjust disk size or fill step (stuck at {cap}%)"
            status, _ = guard.execute(f"dd if=/dev/zero of=/guardpool/filler/blob{i} bs=1M count=10 status=none")
            cap = int(guard.succeed("zpool list -Hpo capacity guardpool").strip().rstrip("%"))
            if status != 0:
                break
        assert cap >= 80, f"pool must be over the 20%-free threshold (80% used) for this subtest: got {cap}%"
        guard.succeed("systemctl start zfs-space-guard.service")
        assert snap_names(guard, "guardpool/a") == ["s4", "s5"]
        assert snap_names(guard, "guardpool/b") == ["s4", "s5"]

    with subtest("keepMin floor: a second run under the same pressure destroys nothing further"):
        guard.succeed("systemctl start zfs-space-guard.service")
        assert snap_names(guard, "guardpool/a") == ["s4", "s5"]

    with subtest("a zrepl-style hold is tolerated, not fatal to the run"):
        guard.succeed("zfs snapshot guardpool/a@s6")
        guard.succeed("zfs snapshot guardpool/a@s7")
        guard.succeed("zfs hold keepme guardpool/a@s4")
        guard.succeed("systemctl start zfs-space-guard.service")
        names = snap_names(guard, "guardpool/a")
        assert "s4" in names, f"held snapshot should survive a failed destroy: {names}"
        assert "s5" not in names, f"non-held prunable snapshot should still be destroyed: {names}"
        status = guard.succeed(
            "systemctl show zfs-space-guard.service -p ExecMainStatus --value"
        ).strip()
        assert status == "0", f"a tolerated destroy failure should not fail the unit: {status}"
        guard.succeed("zfs release keepme guardpool/a@s4")

    with subtest("emergency-prune ignores the threshold and keepMin, keeps only the newest"):
        guard.succeed("systemctl start zfs-emergency-prune.service")
        assert snap_names(guard, "guardpool/a") == ["s7"]
        assert snap_names(guard, "guardpool/b") == ["s5"]

    with subtest("fail-safe: a zpool list failure skips the run instead of pruning everything"):
        badpool.succeed("zpool create -f realpool /dev/vdb")
        badpool.succeed("zfs create realpool/data")
        badpool.succeed("zfs snapshot realpool/data@one")
        badpool.succeed("zfs snapshot realpool/data@two")
        badpool.execute("systemctl start zfs-space-guard.service")
        journal_output = badpool.succeed("journalctl -u zfs-space-guard --no-pager")
        assert "zpool list failed" in journal_output, (
            f"expected the new guard message in the log: {journal_output}"
        )
        assert snap_names(badpool, "realpool/data") == ["one", "two"], (
            "a zpool list failure must not destroy any snapshot"
        )
  '';
}

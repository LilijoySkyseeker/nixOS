# VM test: modules/nixos/zfs-space-guard.nix on a real zpool
# zfs-emergency-prune (manual break-glass) destroys every snapshot except
# `@blank` (impermanence rollback point) and the space comes back; holds are
# tolerated, a leftover zrepl cursor bookmark doesn't pin space, and the
# unit works under its sandbox (a broken sandbox fails here, not at 2am)
#
# Writing or debugging one of these: .claude/skills/verify-a-change/vm-testing.md.
{
  pkgs,
  zfsSpaceGuardModule,
}:
pkgs.testers.runNixOSTest {
  name = "zfs-space-guard";

  nodes.guard =
    { ... }:
    {
      imports = [ zfsSpaceGuardModule ];
      boot.supportedFilesystems = [ "zfs" ];
      networking.hostId = "0badc0de";
      virtualisation.emptyDiskImages = [ 512 ];
      # Pool is created by the test script after boot.
      boot.zfs.forceImportRoot = false;

      myZfsSpaceGuard = {
        enable = true;
        datasets = [
          "guardpool/a"
          "guardpool/b"
        ];
      };
    };

  testScript = ''
    start_all()
    guard.wait_for_unit("multi-user.target")

    def snap_names(dataset):
        out = guard.succeed(f"zfs list -H -o name -t snapshot -s creation {dataset}")
        return [line.split("@", 1)[1] for line in out.strip().splitlines() if line]

    def unit_prop(name):
        return guard.succeed(
            f"systemctl show zfs-emergency-prune.service -p {name} --value"
        ).strip()

    with subtest("the sandbox is actually applied to the unit"):
        # docs/hardening.md's sandboxing stack; dropping it must fail here
        for prop, want in [
            ("NoNewPrivileges", "yes"),
            ("ProtectSystem", "strict"),
            ("ProtectHome", "yes"),
            ("ProtectKernelModules", "yes"),
            ("ProtectKernelTunables", "yes"),
            ("ProtectKernelLogs", "yes"),
            ("ProtectControlGroups", "yes"),
        ]:
            got = unit_prop(prop)
            assert got == want, f"{prop} should be {want}, got {got!r}"
        # PrivateTmp renders as yes/no on some systemd versions and
        # connected/disconnected on others -- assert only that it is on.
        assert unit_prop("PrivateTmp") not in ("no", ""), (
            f"PrivateTmp should be enabled, got {unit_prop('PrivateTmp')!r}"
        )
        # PrivateDevices must stay OFF: the unit needs /dev/zfs, and
        # turning it on would hide it. This is the one piece of the stack
        # that is deliberately absent, so pin that too.
        assert unit_prop("PrivateDevices") == "no", (
            "PrivateDevices must stay off -- the unit needs /dev/zfs"
        )

    with subtest("pool and datasets exist before any check runs"):
        guard.succeed("zpool create -f guardpool /dev/vdb")
        # compression=off: /dev/zero writes below would otherwise compress
        # away to almost nothing and never actually use real pool space.
        guard.succeed("zfs create -o compression=off guardpool/a")
        guard.succeed("zfs create guardpool/b")
        # @blank stands in for the impermanence rollback point, taken
        # before the "game" ever existed -- it must never be destroyed.
        guard.succeed("zfs snapshot guardpool/a@blank")
        guard.succeed("dd if=/dev/zero of=/guardpool/a/game.bin bs=1M count=60 status=none")
        # A later, ordinary periodic snapshot that captures the game.
        guard.succeed("zfs snapshot guardpool/a@s1")
        # guardpool/b has no @blank at all -- stands in for a host not yet
        # migrated to impermanence.
        guard.succeed("zfs snapshot guardpool/b@s1")
        guard.succeed("zfs snapshot guardpool/b@s2")

    with subtest("deleting the file does not free space while @s1 still holds it"):
        avail_before = int(guard.succeed("zfs list -Hp -o avail guardpool/a").strip())
        guard.succeed("rm /guardpool/a/game.bin")
        avail_after_rm = int(guard.succeed("zfs list -Hp -o avail guardpool/a").strip())
        assert avail_after_rm - avail_before < 5 * 1024 * 1024, (
            "deleting the file alone should not free real pool space while "
            f"@s1 still holds it: before={avail_before}, after rm={avail_after_rm}"
        )

    with subtest("a zrepl-style hold on @s1 is tolerated, not fatal to the run"):
        guard.succeed("zfs hold keepme guardpool/a@s1")
        guard.succeed("systemctl start zfs-emergency-prune.service")
        assert snap_names("guardpool/a") == ["blank", "s1"], (
            "the held snapshot should survive this run, @blank always does"
        )
        status = guard.succeed(
            "systemctl show zfs-emergency-prune.service -p ExecMainStatus --value"
        ).strip()
        assert status == "0", f"a tolerated destroy failure should not fail the unit: {status}"
        guard.succeed("zfs release keepme guardpool/a@s1")

    with subtest("emergency-prune keeps @blank, destroys @s1, and space comes back"):
        avail_before = int(guard.succeed("zfs list -Hp -o avail guardpool/a").strip())
        guard.succeed("systemctl start zfs-emergency-prune.service")
        assert snap_names("guardpool/a") == ["blank"], "only @blank should survive"
        avail_after = int(guard.succeed("zfs list -Hp -o avail guardpool/a").strip())
        assert avail_after - avail_before > 50 * 1024 * 1024, (
            "destroying @s1 should free back close to the full 60MB: "
            f"before={avail_before}, after={avail_after}"
        )

    with subtest("a dataset with no @blank gets everything destroyed"):
        assert snap_names("guardpool/b") == [], (
            "guardpool/b has no @blank to protect, so the fallback is to "
            "destroy every snapshot -- this is the documented behavior, not a bug"
        )

    with subtest("a zrepl-style cursor bookmark does not pin space after its snapshot is gone"):
        # zrepl's replication cursor is a *bookmark*, not a snapshot -- this
        # checks that claim actually holds: does leaving the bookmark behind
        # (as emergency-prune does; it only ever destroys snapshots) still
        # let a deleted file's space come back, or does the bookmark itself
        # pin those blocks the same way a snapshot would?
        guard.succeed("zfs create -o compression=off guardpool/d")
        guard.succeed("dd if=/dev/zero of=/guardpool/d/bigfile bs=1M count=60 status=none")
        guard.succeed("zfs snapshot guardpool/d@cursor")
        guard.succeed("zfs bookmark guardpool/d@cursor guardpool/d#cursor")
        avail_before = int(guard.succeed("zfs list -Hp -o avail guardpool/d").strip())
        # Simulate what emergency-prune actually does: destroy the snapshot,
        # leave the bookmark alone (it isn't a snapshot, so the module's
        # `zfs list -t snapshot` never even sees it).
        guard.succeed("zfs destroy guardpool/d@cursor")
        guard.succeed("rm /guardpool/d/bigfile")
        # ZFS defers actually freeing blocks to its own background txg
        # processing -- `avail` right after destroy+rm can still reflect
        # the old, not-yet-reclaimed usage for a moment. Force a sync and
        # poll briefly so the assertion reflects steady state, not a race.
        guard.succeed("zpool sync guardpool")
        avail_after = None
        for _ in range(20):
            avail_after = int(guard.succeed("zfs list -Hp -o avail guardpool/d").strip())
            if avail_after - avail_before > 50 * 1024 * 1024:
                break
            guard.succeed("sleep 1")
        assert avail_after - avail_before > 50 * 1024 * 1024, (
            "a bookmark alone must not keep the deleted file's blocks alive "
            f"-- otherwise the whole point of this module breaks: before={avail_before}, after={avail_after}"
        )
        bookmarks = guard.succeed("zfs list -Hp -t bookmark -o name guardpool/d").strip()
        assert bookmarks == "guardpool/d#cursor", (
            f"the bookmark itself should survive destroying its originating snapshot: {bookmarks}"
        )
  '';
}

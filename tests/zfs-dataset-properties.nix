# Integration test for modules/nixos/zfs-dataset-properties.nix.
#
# The module exists to close a real, live-verified exposure:
# `/nix/state/.zfs` was world-traversable (0777) on homelab, letting any
# local uid read old snapshot contents at whatever permissions they had at
# snapshot time -- proven live and how the factorio credentials leaked
# (2026-08-28-nix-state-zfs-snapshot-dir-is-world-traversable-ex.md).
# `snapdir=disabled` closes it, but only if the property actually reaches
# the dataset and actually blocks access -- `nixos-rebuild build` can't
# prove either, since there's no real pool at build time. This builds a
# throwaway VM with a real zpool and checks:
#
#   * the systemd sandbox is applied to the unit (matches
#     zfs-space-guard's precedent, docs/hardening.md's baseline)
#   * the property is actually applied to the dataset after boot, not just
#     rendered into a script nobody ran
#   * an unprivileged uid can read a snapshot file by explicit path under
#     the default (snapdir=hidden) -- the baseline this is fixing
#   * the same read is fully blocked (ENOENT, not just EACCES) once the
#     module applies snapdir=disabled to a dataset whose .zfs was never
#     touched beforehand
#   * a second dataset with no myZfsDatasetProperties entry is untouched
#     -- this is an opt-in mechanism, not a blanket policy
#   * re-running the service is a no-op (idempotent), matching the
#     module's own "zfs set is idempotent" claim
#   * the documented caveat is real, not just claimed: if .zfs was already
#     accessed before the property flips to disabled, that specific
#     already-mounted snapshot view stays reachable until the dataset is
#     unmounted+remounted -- proven live on homelab during this fix's own
#     research, and asserted here so nobody "fixes" this test by making it
#     pass without the property module or deploy story accounting for it
#
# Writing or debugging one of these: docs/procedures/vm-testing.md.
{
  pkgs,
  zfsDatasetPropertiesModule,
}:
pkgs.testers.runNixOSTest {
  name = "zfs-dataset-properties";

  nodes.guard =
    { ... }:
    {
      imports = [ zfsDatasetPropertiesModule ];
      boot.supportedFilesystems = [ "zfs" ];
      networking.hostId = "0badc0de";
      virtualisation.emptyDiskImages = [ 512 ];
      boot.zfs.forceImportRoot = false;

      myZfsDatasetProperties."guardpool/secured" = {
        snapdir = "disabled";
      };
    };

  testScript = ''
    start_all()
    guard.wait_for_unit("multi-user.target")

    def unit_prop(name):
        return guard.succeed(
            f"systemctl show zfs-dataset-properties.service -p {name} --value"
        ).strip()

    with subtest("the sandbox is actually applied to the unit"):
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
        assert unit_prop("PrivateTmp") not in ("no", ""), (
            f"PrivateTmp should be enabled, got {unit_prop('PrivateTmp')!r}"
        )

    with subtest("pool and datasets exist, one configured, one not"):
        guard.succeed("zpool create -f guardpool /dev/vdb")
        guard.succeed("zfs create -o snapdir=hidden guardpool/secured")
        guard.succeed("zfs create -o snapdir=hidden guardpool/untouched")
        for ds in ("secured", "untouched"):
            guard.succeed(f"echo 'topsecret' > /guardpool/{ds}/secret.txt")
            guard.succeed(f"chmod 644 /guardpool/{ds}/secret.txt")
            guard.succeed(f"zfs snapshot guardpool/{ds}@s1")

    def can_read_as_nobody(path):
        result = guard.execute(
            f"setpriv --reuid=65534 --regid=65534 --clear-groups cat {path}"
        )
        return result[0] == 0

    with subtest("baseline: snapdir=hidden still allows explicit-path reads"):
        # Deliberately checked against guardpool/untouched, not
        # guardpool/secured -- touching secured's .zfs here would cache an
        # automount that survives the property change below, contaminating
        # the "fresh access is blocked" subtest with exactly the caveat
        # the later subtest exists to test on purpose instead.
        assert can_read_as_nobody("/guardpool/untouched/.zfs/snapshot/s1/secret.txt"), (
            "hidden only hides .zfs from readdir -- explicit-path access "
            "should still work before the module runs, confirming the test "
            "actually exercises the exposure this module closes"
        )

    with subtest("running the service applies snapdir=disabled to the configured dataset only"):
        guard.succeed("systemctl start zfs-dataset-properties.service")
        status = guard.succeed(
            "systemctl show zfs-dataset-properties.service -p ExecMainStatus --value"
        ).strip()
        assert status == "0", f"the unit should succeed: ExecMainStatus={status}"

        secured_val = guard.succeed("zfs get -H -o value snapdir guardpool/secured").strip()
        assert secured_val == "disabled", f"guardpool/secured snapdir should be disabled, got {secured_val!r}"

        untouched_val = guard.succeed("zfs get -H -o value snapdir guardpool/untouched").strip()
        assert untouched_val == "hidden", (
            f"guardpool/untouched has no myZfsDatasetProperties entry and must be "
            f"left alone -- this is opt-in, not blanket policy; got {untouched_val!r}"
        )

    with subtest("a fresh access attempt is fully blocked, not just permission-denied"):
        # /guardpool/secured/.zfs was never traversed before the property
        # changed, so there is no stale automount to invalidate -- this is
        # the clean case the fix is meant for.
        result = guard.execute(
            "cat /guardpool/secured/.zfs/snapshot/s1/secret.txt 2>&1"
        )
        assert result[0] != 0, "root itself should no longer be able to reach the snapshot by this path"
        assert "No such file or directory" in result[1], (
            f"expected ENOENT (the .zfs entry point itself gone), got: {result[1]!r}"
        )
        assert not can_read_as_nobody("/guardpool/secured/.zfs/snapshot/s1/secret.txt"), (
            "an unprivileged uid must not be able to read the snapshot file "
            "by explicit path once snapdir=disabled is applied"
        )

    with subtest("the untouched dataset is unaffected"):
        assert can_read_as_nobody("/guardpool/untouched/.zfs/snapshot/s1/secret.txt"), (
            "guardpool/untouched should behave exactly as it did at baseline"
        )

    with subtest("caveat: an already-cached automount survives the property changing"):
        # This is not the module's job to fix -- it is a real ZFS
        # behavior, verified live on homelab during this fix's research.
        # Documented in the module's own option description; this
        # subtest exists so a future change that silently "fixes" it
        # either updates that claim with real evidence or gets caught
        # here first.
        guard.succeed("zfs set snapdir=hidden guardpool/untouched")
        assert can_read_as_nobody("/guardpool/untouched/.zfs/snapshot/s1/secret.txt"), (
            "sanity check: untouched should still be readable before this subtest's own toggle"
        )
        guard.succeed("zfs set snapdir=disabled guardpool/untouched")
        assert can_read_as_nobody("/guardpool/untouched/.zfs/snapshot/s1/secret.txt"), (
            "the already-established automount from the earlier baseline "
            "subtest should still be reachable -- flipping the property "
            "alone must NOT retroactively close it, or this fix's "
            "documented deploy caveat (needs a remount/reboot to fully "
            "close pre-existing access) would be wrong"
        )
        guard.succeed("umount /guardpool/untouched/.zfs/snapshot/s1")
        guard.succeed("zfs unmount guardpool/untouched")
        guard.succeed("zfs mount guardpool/untouched")
        assert not can_read_as_nobody("/guardpool/untouched/.zfs/snapshot/s1/secret.txt"), (
            "after a real unmount/mount cycle of the dataset, disabled "
            "must be fully honored -- this is the remediation for the "
            "caveat above, and it needs to actually work"
        )

    with subtest("re-running the service is idempotent"):
        guard.succeed("systemctl start zfs-dataset-properties.service")
        status = guard.succeed(
            "systemctl show zfs-dataset-properties.service -p ExecMainStatus --value"
        ).strip()
        assert status == "0", f"a second run should still succeed cleanly: ExecMainStatus={status}"
  '';
}

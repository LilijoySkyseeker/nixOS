# Integration test for modules/nixos/zrepl.nix.
#
# The per-host `nixos-rebuild build` only proves the generated YAML parses
# (`myZrepl.validateConfig` runs `zrepl configcheck`). It cannot prove that
# a pull actually lands data, because the real datasets do not exist at
# build time. This test builds two throwaway VMs with real zpools and
# exercises the parts that only fail at runtime:
#
#   * a `serve` host answering a pull over ssh+stdinserver, through the
#     forced command the module writes into root's authorized_keys, and
#     that same key being unable to get a shell
#   * `recv.placeholder.encryption` being set, without which the receiver
#     cannot create the intermediate placeholder datasets the layout
#     implies -- configcheck passes either way, so this is only ever
#     visible from a real receive. This test is what caught it missing.
#   * received data appearing at the deeper `root_fs/<full source path>`
#     layout that replaced syncoid's flatter names, and still holding the
#     payload when recovered the way backup-restore.md prescribes
#   * `myZrepl.protectRegexes` keeping a foreign `@blank` snapshot that an
#     unguarded grid rule would condemn (see docs/backups.md "Gotchas")
#   * a `snap` job snapshotting on its own, with no puller involved
#   * `zrepl-protect-blank` making `@blank` genuinely undestroyable on the
#     source, which `protectRegexes` cannot do -- that is the puller's
#     pruning policy, and the source endpoint evaluates no keep rules
#     (F-P6-04)
#   * the receiver ignoring properties a *hostile sender* puts in the
#     stream, simulated by poisoning the dataset and editing the source's
#     own zrepl.yml the way an attacker with root there would (F-P6-03).
#     Not covered: a resumed receive, which the finding also asks for --
#     `-o` on resume has historically been fussy and orchestrating an
#     interrupted send here is a separate piece of work
#
# This is kept as a regression test, not a one-off verification: the
# module still has planned edits (turning off preserveLegacySnapshots,
# and the tcp/tls transports that are wired but unexercised), and its
# failure mode is a backup that silently stops working -- which you find
# out about when you need a restore. Delete it if zrepl is ever replaced.
#
# Writing or debugging one of these: docs/procedures/vm-testing.md.
{
  pkgs,
  zreplModule,
}:
let
  # nixpkgs' own throwaway test keys, so no private key lives in this
  # repo. They grant nothing outside the ephemeral VMs below; the real
  # puller key is the homelab_zrepl_key sops secret.
  inherit (import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs)
    snakeOilEd25519PrivateKey
    snakeOilEd25519PublicKey
    ;

  # Shared across both nodes: ZFS support plus a spare disk to build a
  # pool on. The nixos test framework exposes emptyDiskImages as /dev/vdb.
  zfsNode = hostId: {
    boot.supportedFilesystems = [ "zfs" ];
    networking.hostId = hostId;
    virtualisation.emptyDiskImages = [ 4096 ];
    virtualisation.memorySize = 2048;
    # The pools are created by the test script after boot, so nothing
    # should try to import them during activation.
    boot.zfs.forceImportRoot = false;
  };
in
pkgs.testers.runNixOSTest {
  name = "zrepl-replication";

  nodes = {
    # Passive sender, standing in for torrent/thinkpad.
    sourcehost =
      { ... }:
      {
        imports = [ zreplModule ];
        inherit (zfsNode "deadbeef") boot networking virtualisation;

        services.openssh = {
          enable = true;
          settings.PermitRootLogin = "forced-commands-only";
        };

        myZrepl = {
          enable = true;
          # Keep the check off: configcheck at build time cannot see the
          # pools, and the daemon starting in the test proves the parse.
          validateConfig = false;
          snapshot.interval = "10s";
          snap = {
            enable = true;
            datasets = [ "tank/data" ];
          };
          serve = {
            enable = true;
            datasets = [ "tank/data" ];
            clients.puller.publicKey = snakeOilEd25519PublicKey;
          };
        };
      };

    # Active receiver, standing in for homelab.
    puller =
      { ... }:
      {
        imports = [ zreplModule ];
        inherit (zfsNode "feedface") boot networking virtualisation;

        myZrepl = {
          enable = true;
          validateConfig = false;
          pull.remotes.sourcehost = {
            host = "sourcehost";
            identityFile = "/etc/zrepl/snakeoil";
            rootFs = "backup/backup/sourcehost";
            interval = "10s";
            # Host keys are generated fresh per VM boot, so there is
            # nothing to pin. Production pins nothing either -- the
            # forced command on the far side is the real boundary.
            sshOptions = [
              "StrictHostKeyChecking=no"
              "UserKnownHostsFile=/dev/null"
            ];
          };
        };

        # zrepl runs as root and ssh insists on 0600 on the identity file.
        environment.etc."zrepl/snakeoil" = {
          source = snakeOilEd25519PrivateKey;
          mode = "0600";
        };
      };
  };

  testScript = ''
    start_all()
    sourcehost.wait_for_unit("multi-user.target")
    puller.wait_for_unit("multi-user.target")

    with subtest("pools exist before zrepl is asked to do anything"):
        sourcehost.succeed("zpool create -f tank /dev/vdb")
        sourcehost.succeed("zfs create tank/data")
        sourcehost.succeed("echo canary-payload > /tank/data/canary")
        # The impermanence rollback point the module must never destroy.
        sourcehost.succeed("zfs snapshot tank/data@blank")
        puller.succeed("zpool create -f backup /dev/vdb")
        puller.succeed("zfs create backup/backup")
        # zrepl does not create root_fs itself -- it only creates children
        # underneath it -- so a missing root_fs fails every pull with
        # "root_fs does not exist". In production these containers are
        # declared in hosts/homelab/disko.nix.
        puller.succeed("zfs create backup/backup/sourcehost")

        # zrepl started before the pools existed, so give both daemons a
        # clean start now that the datasets are there.
        sourcehost.succeed("systemctl restart zrepl")
        puller.succeed("systemctl restart zrepl")
        sourcehost.wait_for_unit("zrepl.service")
        puller.wait_for_unit("zrepl.service")

    with subtest("the snap job takes its own snapshots"):
        sourcehost.wait_until_succeeds(
            "zfs list -t snapshot -o name -H tank/data | grep -q '@zrepl_'", timeout=120
        )

    with subtest("the module pinned a forced command to the puller's key"):
        # Both halves of the ssh wiring come from one `clients` entry, so
        # check the half that lands on disk: the key may only ever run
        # `zrepl stdinserver puller`, and `restrict` strips the rest.
        # NixOS renders declarative keys to /etc/ssh/authorized_keys.d/<user>
        # rather than ~/.ssh/authorized_keys.
        keys = sourcehost.succeed("cat /etc/ssh/authorized_keys.d/root")
        assert "stdinserver puller" in keys, (
            f"forced command missing or wrong identity: {keys!r}"
        )
        assert "restrict" in keys, f"restrict option missing: {keys!r}"

    with subtest("that key cannot get a shell"):
        # Must be bounded: on success the forced command is `zrepl
        # stdinserver`, which waits on stdin and would otherwise hang the
        # test rather than fail it. -n closes stdin, timeout is the belt.
        out = puller.succeed(
            "timeout 15 ssh -n -i /etc/zrepl/snakeoil "
            "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
            "-o ConnectTimeout=5 root@sourcehost 'id -u' 2>&1 || true"
        )
        assert "uid=" not in out, f"got a shell instead of the forced command: {out!r}"

    with subtest("a pull lands data at root_fs/<full source path>"):
        puller.succeed("zrepl signal wakeup sourcehost")
        puller.wait_until_succeeds(
            "zfs list -H -o name backup/backup/sourcehost/tank/data", timeout=180
        )
        # The layout change that trips people up: the source's full
        # dataset path is preserved under root_fs, so this is
        # .../sourcehost/tank/data and not .../sourcehost/data.
        puller.fail("zfs list -H -o name backup/backup/sourcehost/data")

    with subtest("the replicated copy holds the real payload"):
        # Received datasets carry no mountpoint, so getting at the data
        # means cloning the snapshot rather than mounting the backup --
        # the path docs/procedures/backup-restore.md prescribes. Doing it
        # that way here gives that procedure its first real exercise.
        snap = puller.succeed(
            "zfs list -t snapshot -o name -H -s creation "
            "backup/backup/sourcehost/tank/data | tail -1"
        ).strip()
        assert "@zrepl_" in snap, f"no replicated zrepl snapshot found: {snap!r}"
        puller.succeed(f"zfs clone -o mountpoint=/restore {snap} backup/restore-scratch")
        content = puller.succeed("cat /restore/canary").strip()
        assert content == "canary-payload", f"payload mismatch: {content!r}"
        puller.succeed("zfs destroy backup/restore-scratch")

    with subtest("protectRegexes keeps the foreign @blank snapshot"):
        # An unguarded grid rule condemns every snapshot it does not
        # match rather than ignoring it, so without protectRegexes this
        # is exactly what a prune would destroy first.
        puller.succeed("zrepl signal wakeup sourcehost")
        # Both jobs run on a 10s interval here, so 20s covers at least one
        # full prune cycle on each side -- long enough that a missing
        # protect rule would have destroyed @blank by the assert below.
        sourcehost.succeed("sleep 20")
        sourcehost.succeed("zfs list -t snapshot -o name -H | grep -q 'tank/data@blank'")

    with subtest("zrepl-protect-blank makes @blank undestroyable locally (F-P6-04)"):
        # protectRegexes above is the puller's *pruning policy*, and a
        # policy is not a control: Sender.DestroySnapshots evaluates no
        # keep rules, and a source job has no Pruning field at all, so a
        # compromised or merely misconfigured puller can destroy @blank
        # here. A foreign `zfs hold` is the backstop, because zrepl only
        # recognises and releases its own zrepl_STEP_/zrepl_last_received_
        # tags and cannot release this one over any RPC.
        #
        # restart, not start: the unit is wantedBy multi-user.target and
        # already ran once at boot, before the pool existed, where it
        # correctly skipped and exited 0.
        sourcehost.succeed("systemctl restart zrepl-protect-blank.service")
        holds = sourcehost.succeed("zfs holds -H tank/data@blank")
        assert "protect" in holds, f"@blank should carry a foreign hold: {holds!r}"

        # The point of the hold: destroy now fails. This is the same call
        # the puller's endpoint makes, so if it fails locally it fails
        # over RPC too.
        sourcehost.fail("zfs destroy tank/data@blank")

        # Must be idempotent -- it runs on every boot and an existing hold
        # would otherwise make `zfs hold` error and fail the unit.
        sourcehost.succeed("systemctl restart zrepl-protect-blank.service")
        status = sourcehost.succeed(
            "systemctl show zrepl-protect-blank.service -p ExecMainStatus --value"
        ).strip()
        assert status == "0", f"second run should succeed, got {status}"

    with subtest("the receiver ignores properties a hostile sender sends (F-P6-03)"):
        # The sender alone decides whether properties travel, so a source
        # whose root is compromised turns send.properties on in its own
        # zrepl.yml and the puller has no say. Simulated faithfully: poison
        # the dataset, then edit the source's config the way an attacker
        # with root there would.
        #
        # mountpoint is deliberately /hostile rather than the /etc that
        # makes this a real finding -- mounting a dataset over /etc on the
        # source would wreck the node running the test. The receiver-side
        # assertion is identical either way.
        sourcehost.succeed("zfs set mountpoint=/hostile tank/data")
        sourcehost.succeed("zfs set canmount=on tank/data")
        sourcehost.succeed("zfs set setuid=on tank/data")
        sourcehost.succeed("zfs set exec=on tank/data")
        sourcehost.succeed("zfs set devices=on tank/data")

        # /etc/zrepl/zrepl.yml is a store symlink. Replace it with a
        # mutable copy: the forced command runs
        # `zrepl --config /etc/zrepl/zrepl.yml stdinserver`, so this file
        # is what the serving process actually reads.
        sourcehost.succeed("cp -L /etc/zrepl/zrepl.yml /run/hostile.yml")
        # The source job is rendered last, so `send:` can simply be
        # appended as a sibling key. Guarded, because that ordering is the
        # module's business and could change.
        last = sourcehost.succeed("tail -1 /run/hostile.yml").strip()
        assert last == "type: source", f"expected the source job last, got {last!r}"
        # `send_properties`, not `properties`. F-P6-03 writes it as
        # "send.properties: true"; the actual key in zrepl 0.7.0 is
        # SendOptions.SendProperties `yaml:"send_properties"`
        # (internal/config/config.go:95). The wrong spelling is not
        # silently ignored -- zrepl unmarshals strictly and refuses to
        # start with "field properties not found in type
        # config.SendOptions" -- which is how this was caught.
        sourcehost.succeed("echo '  send: {send_properties: true}' >> /run/hostile.yml")
        sourcehost.succeed("rm -f /etc/zrepl/zrepl.yml")
        sourcehost.succeed("cp /run/hostile.yml /etc/zrepl/zrepl.yml")
        sourcehost.succeed("systemctl restart zrepl")
        sourcehost.wait_for_unit("zrepl.service")

        # Force a fresh receive and wait for it to actually land, so the
        # assertions below describe a stream sent *after* the poisoning.
        n_before = int(
            puller.succeed(
                "zfs list -t snapshot -H -o name "
                "backup/backup/sourcehost/tank/data | wc -l"
            ).strip()
        )
        puller.succeed("zrepl signal wakeup sourcehost")
        puller.wait_until_succeeds(
            "test $(zfs list -t snapshot -H -o name "
            "backup/backup/sourcehost/tank/data | wc -l) -gt %d" % n_before,
            timeout=180,
        )

        # recv.properties.override: pinned to a specific safe value.
        for prop, want in [("mountpoint", "none"), ("canmount", "off")]:
            got = puller.succeed(
                f"zfs get -H -o value {prop} backup/backup/sourcehost/tank/data"
            ).strip()
            assert got == want, (
                f"a hostile sender set {prop}; receiver should pin it to "
                f"{want}, got {got!r}"
            )

        # recv.properties.inherit: must not arrive from the wire at all.
        # `-x` makes the property inherited/default rather than received,
        # so the source column is the assertion, not the value.
        for prop in ["exec", "setuid", "devices"]:
            src = puller.succeed(
                f"zfs get -H -o source {prop} backup/backup/sourcehost/tank/data"
            ).strip()
            assert "received" not in src, (
                f"{prop} arrived from the sender (source={src!r}); "
                "recv.properties.inherit should have stripped it"
            )
  '';
}

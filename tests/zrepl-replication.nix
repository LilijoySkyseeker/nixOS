# Integration test for modules/nixos/zrepl.nix.
#
# The per-host `nixos-rebuild build` only proves the generated YAML parses
# (`myZrepl.validateConfig` runs `zrepl configcheck`). It cannot prove that
# a pull actually lands data, because the real datasets do not exist at
# build time. This test builds two throwaway VMs with real zpools and
# exercises the parts that only fail at runtime:
#
#   * a `serve` host answering a pull over ssh+stdinserver, through the
#     forced command the module writes into root's authorized_keys
#   * received data appearing at the deeper `root_fs/<full source path>`
#     layout that replaced syncoid's flatter names
#   * `myZrepl.protectRegexes` keeping a foreign `@blank` snapshot that an
#     unguarded grid rule would condemn (see docs/backups.md "Gotchas")
#   * a `snap` job pruning on its own, with no puller involved
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
        sourcehost.succeed("sleep 20")
        sourcehost.succeed("zfs list -t snapshot -o name -H | grep -q 'tank/data@blank'")

    with subtest("zrepl status is queryable on both sides"):
        puller.succeed("zrepl status --mode raw >/dev/null")
        sourcehost.succeed("zrepl status --mode raw >/dev/null")
  '';
}

# VM test: deploy guards survive root's global git config being a read-only
# store symlink (home-manager); the first subtest proves the env still
# reproduces that, so the test can't silently stop testing it
{ pkgs, deployGuardsScript }:
let
  # stand-in for the home-manager config: a read-only store path
  storeGitconfig = pkgs.writeText "hm-gitconfig" ''
    [user]
      name = root
      email = root@example.invalid
  '';

  # the guards as the real services consume them: interpolated verbatim
  guardRunner = pkgs.writeShellScript "guard-runner" ''
    set -euo pipefail
    cd "$1"
    ${deployGuardsScript}
    require_clean_master
    echo "GUARD-PASSED"
  '';
in
pkgs.testers.runNixOSTest {
  name = "deploy-guards";

  nodes.machine = _: {
    environment.systemPackages = [ pkgs.git ];
    users.users.alice = {
      isNormalUser = true;
      home = "/home/alice";
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Reproduce the real hosts: root's global git config is a symlink
    # into the (read-only) store.
    machine.succeed("mkdir -p /root/.config/git")
    machine.succeed("ln -sf ${storeGitconfig} /root/.config/git/config")

    # A flake dir owned by someone other than root, which is what makes
    # git demand safe.directory in the first place.
    machine.succeed("mkdir -p /home/alice/dotfiles")
    machine.succeed("chown -R alice:users /home/alice/dotfiles")
    machine.succeed(
        "su alice -c 'cd /home/alice/dotfiles && "
        "git init -b master -q . && "
        "git config user.email a@example.invalid && "
        "git config user.name alice && "
        "touch flake.nix && git add flake.nix && "
        "git commit -qm initial'"
    )

    with subtest("the environment still reproduces the original failure"):
        # If this ever stops failing, the rest of this test is no longer
        # exercising the bug and should be re-examined rather than trusted.
        err = machine.fail(
            "git config --global --add safe.directory /tmp/whatever 2>&1"
        )
        assert "Read-only file system" in err, \
            f"expected a read-only global config, got: {err!r}"

    with subtest("root really is refused without safe.directory"):
        # The other half of the premise: dubious ownership is real here.
        err = machine.fail(
            "cd /home/alice/dotfiles && git status --porcelain 2>&1"
        )
        assert "dubious ownership" in err, \
            f"expected git to refuse the repo, got: {err!r}"

    with subtest("the guard passes on a clean master, despite both"):
        out = machine.succeed("${guardRunner} /home/alice/dotfiles 2>&1")
        assert "GUARD-PASSED" in out, f"guard did not complete: {out!r}"
        assert "could not lock config file" not in out, \
            f"guard still tried to write the global config: {out!r}"

    with subtest("the guard still skips a dirty tree"):
        machine.succeed("su alice -c 'touch /home/alice/dotfiles/dirty'")
        out = machine.succeed("${guardRunner} /home/alice/dotfiles 2>&1")
        assert "Working tree dirty" in out, f"dirty tree not detected: {out!r}"
        assert "GUARD-PASSED" not in out, "guard continued past a dirty tree"
        machine.succeed("rm /home/alice/dotfiles/dirty")

    with subtest("the guard still skips a non-master branch"):
        machine.succeed(
            "su alice -c 'cd /home/alice/dotfiles && git checkout -q -b side'"
        )
        out = machine.succeed("${guardRunner} /home/alice/dotfiles 2>&1")
        assert "Not on master" in out, f"branch guard did not fire: {out!r}"
        assert "GUARD-PASSED" not in out, "guard continued off master"
        machine.succeed(
            "su alice -c 'cd /home/alice/dotfiles && git checkout -q master'"
        )

    with subtest("nothing was written to the global config"):
        # The whole point: the guard must not mutate a file another part
        # of the system owns declaratively.
        target = machine.succeed("readlink /root/.config/git/config").strip()
        assert target.startswith("/nix/store/"), \
            f"global config is no longer the store symlink: {target}"
        machine.succeed("test ! -e /root/.config/git/config.lock")
  '';
}

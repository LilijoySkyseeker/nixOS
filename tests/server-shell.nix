# VM test: root's interactive shell on a server, as profile-server sets it up.
# The prompt collapses a run command to one transcript line and prints a
# result line after a failure or a slow command; the wiped-at-boot mark shows
# off the persisted paths only; history lands on the persisted disk; the
# login summary runs. ble.sh only attaches on a terminal, so the shell runs
# in tmux.
{
  pkgs,
  specialArgs,
  impermanenceModule,
  homeManagerModule,
  loginSummaryModule,
  toolingModule,
}:
pkgs.testers.runNixOSTest {
  name = "server-shell";

  node.specialArgs = specialArgs;

  nodes.machine =
    { vars, ... }:
    {
      imports = [
        impermanenceModule
        homeManagerModule
        loginSummaryModule
      ];
      # a persistence root on its own filesystem, as on homelab and vps
      virtualisation.emptyDiskImages = [ 256 ];
      virtualisation.fileSystems."/persist" = {
        device = "/dev/vdb";
        fsType = "ext4";
        autoFormat = true;
        neededForBoot = true;
      };
      environment.persistence."/persist" = {
        hideMounts = true;
        users.root.directories = vars.rootShellState;
      };
      home-manager = {
        extraSpecialArgs = specialArgs;
        useGlobalPkgs = true;
        users.root = {
          imports = [ toolingModule ];
          home.stateVersion = "23.11";
          programs.bash.historyFile = "/root/.local/state/bash/history";
        };
      };
      environment.systemPackages = [ pkgs.tmux ];
    };

  testScript = ''
    import time

    def screen():
        return machine.succeed("tmux capture-pane -p -t t")

    def run(cmd, wait=2):
        machine.succeed(f"tmux send-keys -t t -l {cmd!r} && tmux send-keys -t t Enter")
        time.sleep(wait)

    def live_prompt():
        # the frame's first line: the last line holding its top-left corner
        return [l for l in screen().splitlines() if "╭─" in l][-1]

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("home-manager-root.service")

    with subtest("root's shell state is on the persisted disk"):
        for d in ["state/bash", "share/atuin", "share/zoxide", "share/direnv"]:
            src = machine.succeed(f"findmnt -no SOURCE /root/.local/{d}").strip()
            assert src.startswith("/dev/vdb"), f"/root/.local/{d} is on {src!r}"

    with subtest("the login summary runs"):
        status, out = machine.execute("login-summary 2>&1")
        assert status == 0, out
        print(out)
        assert " · up " in out, out
        assert "none failed" in out or "failed:" in out, out
        assert "/persist" in out, out

    with subtest("the prompt draws"):
        machine.succeed("tmux new-session -d -s t -x 120 -y 40 'bash -l'")
        machine.wait_until_succeeds("tmux capture-pane -p -t t | grep -q '╰─'", timeout=60)
        run("cd /root")

    with subtest("a run command collapses to one transcript line"):
        run("true | false")
        s = screen()
        assert "root@machine:~# true | false" in s, s
        assert "[exit 0|1 · " in s, s
        assert "[ble: exit" not in s, s

    with subtest("a slow command gets a result line"):
        run("sleep 3.5", wait=6)
        s = screen()
        assert "[done · 3." in s, s

    with subtest("the wiped-at-boot mark follows the persisted paths"):
        assert "" in live_prompt(), live_prompt()
        run("cd /root/.local/state/bash")
        assert "" not in live_prompt(), live_prompt()

    with subtest("history is written to the persisted disk"):
        run("exit")
        machine.wait_until_succeeds("grep -q 'sleep 3.5' /persist/root/.local/state/bash/history")
  '';
}

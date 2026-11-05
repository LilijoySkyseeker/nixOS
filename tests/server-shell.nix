# VM test: root's interactive shell on a server, as profile-server sets it up.
# The prompt collapses a run command to one transcript line and prints a
# result line after a failure or a slow command; up and down walk history with
# the cursor at the end; Ctrl-C clears the line; history lands on the persisted
# disk. ble.sh only attaches on a terminal, so the shell runs in tmux.
{
  pkgs,
  specialArgs,
  impermanenceModule,
  homeManagerModule,
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

    def key(name):
        machine.succeed(f"tmux send-keys -t t {name}")
        time.sleep(1)

    def assert_input(text):
        # what's typed on the prompt's second line, with the cursor right after it
        y, x = machine.succeed("tmux display -p -t t '#{cursor_y} #{cursor_x}'").split()
        line = screen().splitlines()[int(y)]
        typed = line[line.index("❯") + 2 :].removesuffix("─╯").rstrip()
        assert typed == text, f"{typed!r} != {text!r} in {line!r}"
        assert int(x) == line.index("❯") + 2 + len(text), f"cursor at {x} in {line!r}"

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("home-manager-root.service")

    with subtest("root's shell state is on the persisted disk"):
        for d in ["state/bash", "share/atuin", "share/zoxide"]:
            src = machine.succeed(f"findmnt -no SOURCE /root/.local/{d}").strip()
            assert src.startswith("/dev/vdb"), f"/root/.local/{d} is on {src!r}"

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

    with subtest("the transcript line names the git branch"):
        run("git init -q -b demo /tmp/repo && cd /tmp/repo")
        run("true")
        s = screen()
        assert "root@machine:/tmp/repo (demo)# true" in s, s
        run("cd /root")

    with subtest("a slow command gets a result line"):
        run("sleep 3.5", wait=6)
        s = screen()
        assert "[done · 3." in s, s

    with subtest("Ctrl-C ends a command and returns to a prompt"):
        run("sleep 100")
        machine.succeed("tmux send-keys -t t C-c")
        time.sleep(2)
        s = screen()
        assert "[exit 130 SIGINT · " in s, s
        run("cat")
        machine.succeed("tmux send-keys -t t C-c")
        time.sleep(2)
        run("echo after-ctrl-c")
        s = screen()
        assert "root@machine:~# echo after-ctrl-c" in s, s

    with subtest("up and down walk history with the cursor at the end"):
        run("echo aaa")
        run("echo bbb-longer")
        key("Up")
        assert_input("echo bbb-longer")
        key("Up")
        assert_input("echo aaa")
        key("Down")
        assert_input("echo bbb-longer")
        key("Down")
        assert_input("")

    with subtest("up searches for what was typed, across repeated presses"):
        run("echo needle-one")
        run("echo other")
        run("echo needle-two")
        machine.succeed("tmux send-keys -t t -l needle")
        time.sleep(1)
        key("Up")
        assert_input("echo needle-two")
        key("Up")
        assert_input("echo needle-one")
        key("C-c")

    with subtest("Ctrl-C clears the line and stays in insert mode"):
        machine.succeed("tmux send-keys -t t -l 'echo discarded'")
        time.sleep(1)
        key("C-c")
        assert_input("")
        run("echo typed-after-ctrl-c")
        s = screen()
        assert "\ntyped-after-ctrl-c" in s, s

    with subtest("history is written to the persisted disk"):
        run("exit")
        machine.wait_until_succeeds("grep -q 'sleep 3.5' /persist/root/.local/state/bash/history")
  '';
}

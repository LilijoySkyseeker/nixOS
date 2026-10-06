# Does the agent user actually live in its own place?
#
# The agent's place is a separate Unix user on torrent: everything
# non-sensitive runs there with no prompts, so the boundary has to hold
# without anyone watching. A build can't show that — a home dir's mode, a
# group membership or a nix-daemon allow-list only exist at runtime — so
# this boots a VM with a stand-in for the real user's home and asserts
# from the agent's side.
# plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md
{ pkgs, agentUserModule }:
pkgs.testers.runNixOSTest {
  name = "agent-user";

  nodes.machine =
    { ... }:
    {
      imports = [ agentUserModule ];

      # stand-in for lilijoy: the home the agent must never see into
      users.users.lilijoy = {
        isNormalUser = true;
        homeMode = "700";
      };
      # mirror profile-pc: only wheel may talk to the nix daemon
      nix.settings.allowed-users = [ "@wheel" ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("su lilijoy -s /bin/sh -c 'echo private > /home/lilijoy/secret'")

    def as_agent(cmd):
        return f"su agent -s /bin/sh -c '{cmd}'"

    with subtest("user boundary"):
        machine.fail(as_agent("ls /home/lilijoy"))
        machine.fail(as_agent("cat /home/lilijoy/secret"))
        groups = machine.succeed("id -nG agent").strip()
        assert groups == "agent", f"agent groups: {groups!r}"
        for d in ["/home/agent", "/home/agent/work", "/home/agent/repos"]:
            got = machine.succeed(f"stat -c '%a %U' {d}").strip()
            assert got == "700 agent", f"{d}: {got!r}"
        machine.succeed(as_agent("nix-store --query --hash /run/current-system"))

    with subtest("research mount"):
        src = "/home/lilijoy/Documents/Vault/Research"
        # the user makes this folder once; the module never writes into their home
        machine.succeed(f"su lilijoy -s /bin/sh -c 'mkdir -p {src}'")
        # a sibling vault folder the agent must never reach
        machine.succeed("install -d -o lilijoy -g users /home/lilijoy/Documents/Vault/Library")
        machine.succeed("su lilijoy -s /bin/sh -c 'echo mine > /home/lilijoy/Documents/Vault/Library/x.md'")
        # agent writes land as lilijoy-owned files in the real vault folder
        machine.succeed(as_agent("echo found > /home/agent/research/note.md"))
        got = machine.succeed(f"stat -c %U:%G {src}/note.md").strip()
        assert got == "lilijoy:users", f"note.md owner: {got!r}"
        # a note lilijoy writes is editable by the agent through the mount
        machine.succeed(f"su lilijoy -s /bin/sh -c 'echo seed > {src}/seed.md'")
        machine.succeed(as_agent("echo edited >> /home/agent/research/seed.md"))
        machine.succeed(f"grep -q edited {src}/seed.md")
        # nothing beyond Research is reachable
        machine.fail(as_agent("cat /home/lilijoy/Documents/Vault/Library/x.md"))
        listing = machine.succeed(as_agent("ls -a /home/agent/research/.."))
        assert "Library" not in listing, f"parent listing: {listing!r}"
  '';
}

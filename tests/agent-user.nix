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
      # mirror torrent: iptables firewall backend
      networking.nftables.enable = false;
      environment.systemPackages = [ pkgs.curl ];
    };

  # a LAN host the agent must not reach (the test net is 192.168.1.0/24)
  nodes.lan =
    { pkgs, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 8000 ];
      systemd.services.http = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8000 --directory /etc";
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    lan.wait_for_open_port(8000)
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

    with subtest("egress"):
        # root still reaches the LAN; the agent uid does not
        machine.succeed("curl --fail --max-time 5 http://lan:8000/hostname")
        machine.fail(as_agent("curl --fail --max-time 5 http://lan:8000/hostname"))
        v4 = machine.succeed("iptables -S agent-egress")
        for net in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16"]:
            assert f"-d {net}" in v4 and "REJECT" in v4, f"missing v4 {net}: {v4!r}"
        v6 = machine.succeed("ip6tables -S agent-egress")
        for net in ["fc00::/7", "fe80::/10"]:
            assert f"-d {net}" in v6, f"missing v6 {net}: {v6!r}"

    with subtest("egress survives a firewall restart without duplicating"):
        machine.succeed("systemctl restart firewall")
        n4 = machine.succeed("iptables -S OUTPUT | grep -c agent-egress").strip()
        n6 = machine.succeed("ip6tables -S OUTPUT | grep -c agent-egress").strip()
        assert n4 == "1" and n6 == "1", f"jumps after restart: v4={n4} v6={n6}"
        machine.fail(as_agent("curl --fail --max-time 5 http://lan:8000/hostname"))
  '';
}

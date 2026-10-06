# VM test: agent-user's boundary, asserted from the agent's side
# plan: 2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md#F11
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
      services.openssh.enable = true;
      # a fixed-output build: runs as nixbld with host networking
      environment.etc."fod.nix".text = ''
        { url }:
        derivation {
          name = "egress-probe";
          system = "x86_64-linux";
          builder = builtins.storePath "${pkgs.bash}/bin/bash";
          args = [ "-c" "''${builtins.storePath "${pkgs.curl}"}/bin/curl -sS --max-time 5 ''${url} >&2; exit 1" ];
          outputHashMode = "flat";
          outputHashAlgo = "sha256";
          outputHash = "0000000000000000000000000000000000000000000000000000";
        }
      '';
    };

  # a LAN host the agent must not reach (the test net is 192.168.1.0/24)
  nodes.lan =
    { pkgs, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 8000 ];
      environment.etc."marker".text = "LAN-MARKER-7f3a";
      # dual-stack: python's http.server binds IPv4 only by default
      systemd.services.http = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8000 --bind :: --directory /etc";
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    lan.wait_for_open_port(8000)
    machine.succeed("su lilijoy -s /bin/sh -c 'echo private > /home/lilijoy/secret'")

    def as_agent(cmd):
        return f"su agent -s /bin/sh -c '{cmd}'"

    # review-fix checks report every failure, not just the first
    failures = []

    def check(ok, msg):
        if not ok:
            failures.append(msg)

    with subtest("user boundary"):
        machine.fail(as_agent("ls /home/lilijoy"))
        machine.fail(as_agent("cat /home/lilijoy/secret"))
        groups = machine.succeed("id -nG agent").strip()
        assert groups == "agent", f"agent groups: {groups!r}"
        for d in ["/home/agent", "/home/agent/work"]:
            got = machine.succeed(f"stat -c '%a %U' {d}").strip()
            assert got == "700 agent", f"{d}: {got!r}"
        machine.succeed(as_agent("nix-store --query --hash /run/current-system"))

    with subtest("research mount"):
        src = "/home/lilijoy/Documents/Vault/Research"
        # before the user creates the folder, access fails visibly but must
        # not hit the start limit and wedge the automount until reboot
        for _ in range(8):
            machine.execute(as_agent("ls /home/agent/research"))
        # the user makes this folder once; the module never writes into their home
        machine.succeed(f"su lilijoy -s /bin/sh -c 'mkdir -p {src}'")
        rc, out = machine.execute(as_agent("touch /home/agent/research/after-missing.md 2>&1"))
        check(rc == 0, f"mount wedged after missing source: {out!r}")
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
        assert "-A agent-egress -j REJECT" in v6, f"v6 not refused by default: {v6!r}"

    with subtest("egress survives a firewall restart without duplicating"):
        machine.succeed("systemctl restart firewall")
        n4 = machine.succeed("iptables -S OUTPUT | grep -c -- '--uid-owner .* agent-egress'").strip()
        n6 = machine.succeed("ip6tables -S OUTPUT | grep -c -- '--uid-owner .* agent-egress'").strip()
        assert n4 == "1" and n6 == "1", f"jumps after restart: v4={n4} v6={n6}"
        machine.fail(as_agent("curl --fail --max-time 5 http://lan:8000/hostname"))

    with subtest("review fixes: egress, builds, reload, sandbox, sshd"):
        # IPv6: all but loopback rejected (F1)
        machine.succeed("curl -6 --fail --max-time 5 http://lan:8000/marker")
        rc, _ = machine.execute(as_agent("curl -6 --fail --max-time 5 http://lan:8000/marker"))
        check(rc != 0, "agent reached the LAN over IPv6")
        v4 = machine.succeed("iptables -S agent-egress")
        for net in ["224.0.0.0/4", "255.255.255.255/32"]:
            check(f"-d {net} -j REJECT" in v4, f"v4 missing {net}")
        # fixed-output builds run as nixbld with host networking
        rc, out = machine.execute(as_agent("nix-build /etc/fod.nix --argstr url http://lan:8000/marker 2>&1"))
        check("LAN-MARKER-7f3a" not in out, "a fixed-output build reached the LAN")
        # switch reloads the firewall; the walls must survive a reload too
        machine.succeed("systemctl reload firewall")
        for cmd in ["iptables", "ip6tables"]:
            for match in ["--uid-owner", "--gid-owner"]:
                n = machine.succeed(f"{cmd} -S OUTPUT | grep -c -- '{match} .* agent-egress' || true").strip()
                check(n == "1", f"{cmd} {match} jumps after reload: {n}")
        rc, _ = machine.execute(as_agent("curl --fail --max-time 5 http://lan:8000/marker"))
        check(rc != 0, "agent reached the LAN after a firewall reload")

        def sprop(p):
            return machine.succeed(f"systemctl show claude-remote-control -p {p} --value").strip()
        for p, want in [("NoNewPrivileges", "yes"), ("PrivateTmp", "yes"), ("PrivateDevices", "yes"), ("ProtectSystem", "strict")]:
            check(sprop(p) == want, f"{p}={sprop(p)!r}")
        check("/home/agent" in sprop("ReadWritePaths"), f"ReadWritePaths={sprop('ReadWritePaths')!r}")
        inacc = sprop("InaccessiblePaths")
        for sock in ["/run/mullvad-vpn", "/run/tailscale", "/run/libvirt"]:
            check(sock in inacc, f"{sock} not inaccessible: {inacc!r}")
        check(sprop("MemoryMax") not in ("infinity", ""), f"MemoryMax={sprop('MemoryMax')!r}")
        check("firewall.service" in sprop("BindsTo"), f"BindsTo={sprop('BindsTo')!r}")
        check("firewall.service" in sprop("After"), "not ordered after firewall.service")
        # sshd denies agent (F8)
        sshd = machine.succeed("sshd -T -C user=agent,host=x,addr=127.0.0.1 | grep -i '^denyusers' || true")
        check("agent" in sshd, f"sshd denyusers: {sshd!r}")

        assert not failures, "review-fix checks failed:\n" + "\n".join(failures)

    with subtest("orientation"):
        # the agent reads where it is from a declared CLAUDE.md
        md = machine.succeed(as_agent("cat /home/agent/.claude/CLAUDE.md"))
        for phrase in ["torrent", "~/research", "~/work/repos", "pull request"]:
            assert phrase in md, f"CLAUDE.md lacks {phrase!r}"
        # the unused ~/repos is gone; clones live in ~/work/repos
        machine.fail("test -e /home/agent/repos")

    with subtest("remote control service"):
        def prop(p):
            return machine.succeed(f"systemctl show claude-remote-control -p {p} --value").strip()
        # before the one-time login there's no credential: skipped, not crash-looping
        assert prop("ConditionResult") == "no", f"ConditionResult: {prop('ConditionResult')!r}"
        assert prop("ActiveState") != "failed", f"ActiveState: {prop('ActiveState')!r}"
        assert prop("User") == "agent", f"User: {prop('User')!r}"
        assert prop("WorkingDirectory") == "/home/agent/work", f"WorkingDirectory: {prop('WorkingDirectory')!r}"
        unit = machine.succeed("systemctl cat claude-remote-control")
        for flag in ["remote-control", "--spawn same-dir", "--name torrent-agent", "--permission-mode bypassPermissions"]:
            assert flag in unit, f"missing {flag!r} in unit"
        env = prop("Environment")
        assert "ENABLE_CLAUDEAI_MCP_SERVERS=false" in env, f"Environment: {env!r}"
        assert "HOME=/home/agent" in env, f"Environment: {env!r}"
  '';
}

# VM test: agent-user's boundary, asserted from the agent's side
{ pkgs, agentUserModule }:
let
  # a one-page PDF for web-fetch's non-HTML path
  markerPdf = pkgs.runCommand "marker-pdf" { } ''
    mkdir $out
    ${pkgs.python3}/bin/python3 - > $out/marker.pdf <<'PY'
    import sys
    text = b"BT /F1 12 Tf 10 50 Td (PDF-MARKER-9c2e) Tj ET"
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 100] /Contents 4 0 R"
        b" /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n%s\nendstream" % (len(text), text),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out, offsets = b"%PDF-1.4\n", []
    for n, body in enumerate(objs, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n%s\nendobj\n" % (n, body)
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    out += b"".join(b"%010d 00000 n \n" % o for o in offsets)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    sys.stdout.buffer.write(out)
    PY
  '';
  # a Codex session file's usage record, and the hook event pointing at it
  codexSession = pkgs.writeText "rollout-t.jsonl" (
    builtins.toJSON {
      payload = {
        type = "token_count";
        info = {
          last_token_usage = {
            input_tokens = 95000;
            output_tokens = 0;
          };
          model_context_window = 475000;
        };
        rate_limits = {
          primary = {
            used_percent = 12.0;
            resets_at = 4102444800;
          };
          secondary = {
            used_percent = 40.0;
            resets_at = 4102444800;
          };
        };
      };
    }
    + "\n"
  );
  usageEvent = pkgs.writeText "usage-event.json" (
    builtins.toJSON {
      hook_event_name = "UserPromptSubmit";
      session_id = "t";
      transcript_path = "/home/agent/.codex/sessions/2026/01/01/rollout-t.jsonl";
    }
  );
in
pkgs.testers.runNixOSTest {
  name = "agent-user";

  # agent-user sets nixpkgs options of its own, so the node imports nixpkgs
  # itself and needs torrent's unfree setting
  node.pkgsReadOnly = false;
  defaults.nixpkgs.config.allowUnfree = true;

  nodes.machine = {
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
    environment.systemPackages = [
      pkgs.curl
      pkgs.git
      pkgs.jq
      pkgs.socat
    ];
    services.openssh.enable = true;
    # a switch that changes the task unit and an egress rule
    specialisation.update.configuration = {
      systemd.services."agent-task@".environment.SWITCH_PROBE = "1";
      networking.firewall.extraCommands = pkgs.lib.mkAfter "# changed";
    };
    # serves markerPdf on loopback, which the agent may reach
    systemd.services.pdf-server = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8001 --bind 127.0.0.1 --directory ${markerPdf}";
    };
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

    # agent-task refuses a cwd in /tmp, where the driver runs
    def task(cmd):
        return as_agent(f"cd /home/agent/work && agent-task {cmd}")

    # report every failure, not just the first
    failures = []

    def check(ok, msg):
        if not ok:
            failures.append(msg)

    with subtest("user boundary"):
        machine.fail(as_agent("ls /home/lilijoy"))
        machine.fail(as_agent("cat /home/lilijoy/secret"))
        groups = machine.succeed("id -nG agent").strip()
        assert groups == "agent", f"agent groups: {groups!r}"
        # lilijoy joins agent's group, never the other way round
        groups = machine.succeed("id -nG lilijoy").strip().split()
        assert "agent" in groups, f"lilijoy groups: {groups!r}"
        for d, mode in [("/home/agent", "711"), ("/home/agent/work", "2770")]:
            got = machine.succeed(f"stat -c '%a %U' {d}").strip()
            assert got == f"{mode} agent", f"{d}: {got!r}"
        machine.succeed(as_agent("nix-store --query --hash /run/current-system"))

    with subtest("shared work folder"):
        def as_user(cmd):
            return f"su lilijoy -s /bin/sh -c '{cmd}'"

        # lilijoy drops a file in ~/work; the agent can edit it
        machine.succeed(as_user("umask 077 && echo drop > /home/agent/work/drop.md"))
        machine.succeed(as_agent("echo edited >> /home/agent/work/drop.md"))
        got = machine.succeed("stat -c %G /home/agent/work/drop.md").strip()
        assert got == "agent", f"drop.md group: {got!r}"
        # an agent-made folder stays writable for lilijoy
        machine.succeed(as_agent("umask 077 && mkdir /home/agent/work/proj && echo a > /home/agent/work/proj/a.md"))
        machine.succeed(as_user("echo b >> /home/agent/work/proj/a.md && touch /home/agent/work/proj/b.md"))
        # the rest of the agent's home stays closed to lilijoy
        machine.fail(as_user("ls /home/agent"))
        machine.fail(as_user("ls /home/agent/.claude"))
        # git as lilijoy refuses an agent-owned repo, so its hooks never run as lilijoy
        machine.succeed(as_agent("git init -q /home/agent/work/proj"))
        rc, out = machine.execute(as_user("git -C /home/agent/work/proj status 2>&1"))
        assert rc != 0 and "dubious ownership" in out, f"git ran as lilijoy in an agent repo: {out!r}"

    with subtest("vault mounts"):
        src = "/home/lilijoy/Documents/Vault/Library"
        # before the user creates the folder, access fails visibly but must
        # not hit the start limit and wedge the automount until reboot
        for _ in range(8):
            machine.execute(as_agent("ls /home/agent/vault/Library"))
        # the user makes this folder once; the module never writes into their home
        machine.succeed(f"su lilijoy -s /bin/sh -c 'mkdir -p {src}'")
        rc, out = machine.execute(as_agent("touch /home/agent/vault/Library/after-missing.md 2>&1"))
        check(rc == 0, f"mount wedged after missing source: {out!r}")
        # a sibling vault folder the agent must never reach
        machine.succeed("install -d -o lilijoy -g users /home/lilijoy/Documents/Vault/Private")
        machine.succeed("su lilijoy -s /bin/sh -c 'echo mine > /home/lilijoy/Documents/Vault/Private/x.md'")
        # agent writes land as lilijoy-owned files in the real vault folder
        machine.succeed(as_agent("echo found > /home/agent/vault/Library/note.md"))
        got = machine.succeed(f"stat -c %U:%G {src}/note.md").strip()
        assert got == "lilijoy:users", f"note.md owner: {got!r}"
        # a note lilijoy writes is editable by the agent through the mount
        machine.succeed(f"su lilijoy -s /bin/sh -c 'echo seed > {src}/seed.md'")
        machine.succeed(as_agent("echo edited >> /home/agent/vault/Library/seed.md"))
        machine.succeed(f"grep -q edited {src}/seed.md")
        # the other shared folders mount too
        for folder in ["Areas", "Projects", "Old"]:
            machine.succeed(f"su lilijoy -s /bin/sh -c 'mkdir -p /home/lilijoy/Documents/Vault/{folder}'")
            machine.succeed(as_agent(f"touch /home/agent/vault/{folder}/probe.md"))
        # nothing beyond the shared folders is reachable
        machine.fail(as_agent("cat /home/lilijoy/Documents/Vault/Private/x.md"))
        listing = machine.succeed(as_agent("ls -a /home/agent/vault"))
        assert "Private" not in listing, f"parent listing: {listing!r}"

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
        # IPv6: all but loopback and Google's ranges rejected
        machine.succeed("curl -6 --fail --max-time 5 http://lan:8000/marker")
        rc, _ = machine.execute(as_agent("curl -6 --fail --max-time 5 http://lan:8000/marker"))
        check(rc != 0, "agent reached the LAN over IPv6")
        # stand-in for Google: an address in one of its ranges, added only for
        # this check (in the node's config it would also become `lan` in /etc/hosts)
        lan.succeed("ip -6 addr add 2607:f8b0:4001::8000/64 dev eth1 nodad")
        machine.succeed("ip -6 route replace 2607:f8b0:4001::/64 dev eth1")
        rc, out = machine.execute(as_agent("curl -6 --fail --max-time 5 http://[2607:f8b0:4001::8000]:8000/marker"))
        check(rc == 0 and "LAN-MARKER-7f3a" in out, f"agent can't reach a Google IPv6 range: rc={rc} {out!r}")
        # builds go through the same chain: in for Google, out for the rest
        rc, out = machine.execute(as_agent("nix-build /etc/fod.nix --argstr url http://[2607:f8b0:4001::8000]:8000/marker 2>&1"))
        check("LAN-MARKER-7f3a" in out, f"a fixed-output build can't reach a Google IPv6 range: {out[-300:]!r}")
        lan.succeed("ip -6 addr del 2607:f8b0:4001::8000/64 dev eth1")
        machine.succeed("ip -6 route del 2607:f8b0:4001::/64 dev eth1")
        # a public address outside Google's ranges, like the household LAN's
        lan.succeed("ip -6 addr add 2a01:4f8:1::8000/64 dev eth1 nodad")
        machine.succeed("ip -6 route replace 2a01:4f8:1::/64 dev eth1")
        machine.succeed("curl -6 --fail --max-time 5 http://[2a01:4f8:1::8000]:8000/marker")
        rc, _ = machine.execute(as_agent("curl -6 --fail --max-time 5 http://[2a01:4f8:1::8000]:8000/marker"))
        check(rc != 0, "agent reached a public non-Google IPv6 address")
        rc, out = machine.execute(as_agent("nix-build /etc/fod.nix --argstr url http://[2a01:4f8:1::8000]:8000/marker 2>&1"))
        check("LAN-MARKER-7f3a" not in out, "a fixed-output build reached a public non-Google IPv6 address")
        lan.succeed("ip -6 addr del 2a01:4f8:1::8000/64 dev eth1")
        machine.succeed("ip -6 route del 2a01:4f8:1::/64 dev eth1")
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

        # GPU and KVM bound in and allowed, tun and display nodes refused: the
        # agent sandbox's device rules on a probe process (the unit itself,
        # paseo, is checked in tests/local-ai.nix)
        probe = ("systemd-run --wait --pipe --quiet -p User=agent -p PrivateDevices=yes "
                 "-p BindPaths=-/dev/kvm -p BindPaths=-/dev/dri -p 'DeviceAllow=/dev/kvm rw' "
                 "-p SupplementaryGroups=kvm -- sh -c ")
        if machine.execute("test -c /dev/kvm")[0] == 0:
            rc, out = machine.execute(probe + "'exec 3<>/dev/kvm && echo kvm-ok'")
            check("kvm-ok" in out, f"probe can't open /dev/kvm: {out!r}")
        rc, out = machine.execute(probe + "'exec 3<>/dev/net/tun && echo tun-open'")
        check("tun-open" not in out, "probe opened /dev/net/tun")
        rc, card = machine.execute("ls /dev/dri/card* 2>/dev/null | head -1")
        if card.strip():
            # visible in the bound /dev/dri, refused by the device cgroup:
            # probe as root, which file permissions wouldn't stop
            rc, out = machine.execute(probe.replace("User=agent", "User=root") + f"'test -c {card.strip()} && echo card-seen; exec 3<>{card.strip()} && echo card-open'")
            check("card-seen" in out, f"probe can't see {card.strip()}: {out!r}")
            check("card-open" not in out, "probe opened a display node")
        mem = machine.succeed("systemctl show agent.slice -p MemoryMax --value").strip()
        check(mem not in ("infinity", ""), f"agent.slice MemoryMax={mem!r}")
        # sshd denies agent
        sshd = machine.succeed("sshd -T -C user=agent,host=x,addr=127.0.0.1 | grep -i '^denyusers' || true")
        check("agent" in sshd, f"sshd denyusers: {sshd!r}")

        assert not failures, "review-fix checks failed:\n" + "\n".join(failures)

    with subtest("orientation"):
        # the user's working rule, the same file their own CLAUDE.md uses
        with open("${../modules/home-manager/claude-code/user-claude.md}") as f:
            rule = f.read()
        # every harness reads the same text
        with open("${../modules/nixos/agent-user-AGENTS.md}") as f:
            shared = f.read()
        harnesses = {
            "Claude Code": (".claude/CLAUDE.md", ".claude/skills"),
            "Codex": (".codex/AGENTS.md", ".agents/skills"),
        }
        for name, (instructions, skills) in harnesses.items():
            text = machine.succeed(as_agent(f"cat /home/agent/{instructions}"))
            assert text.startswith(shared), f"{name}: doesn't start with the shared instructions"
            assert rule in text, f"{name}: lacks the user's working rule"
            # the same skills: the user's and the agent-only ones
            for skill in ["doghouse-review", "torrent-machine", "other-agents"]:
                machine.succeed(as_agent(f"test -f /home/agent/{skills}/{skill}/SKILL.md"))
        # bot-wall fetcher on the agent's PATH (no network in the VM to run it)
        machine.succeed(as_agent("command -v web-fetch"))
        rc, out = machine.execute(as_agent("web-fetch 2>&1"))
        assert rc == 2 and "usage: web-fetch" in out, f"web-fetch usage: rc={rc} {out!r}"
        # a PDF comes back as its text from the curl tier, not sent to the browser
        machine.wait_for_open_port(8001)
        rc, out = machine.execute(as_agent("web-fetch http://127.0.0.1:8001/marker.pdf 2>&1"))
        assert rc == 0 and "PDF-MARKER-9c2e" in out and "web-fetch: curl" in out, f"web-fetch PDF: rc={rc} {out!r}"
        # account-level tools stay out: remote session/routine tools would run
        # cloud work with the user's GitHub App and connectors
        machine.wait_for_unit("claude-agent-settings.service")
        cfg = machine.succeed("cat /home/agent/.claude/settings.json")
        assert '"disableClaudeAiConnectors": true' in cfg, f"connectors not off: {cfg!r}"
        # the built-in twins: routines (cloud, with the user's authority) and
        # cross-session messages into the user's sessions
        deny = machine.succeed("jq -c .permissions.deny /home/agent/.claude/settings.json").strip()
        for tool in ["RemoteTrigger", "SendMessage"]:
            assert f'"{tool}"' in deny, f"{tool} not denied: {deny!r}"
        # notes live in AGENTS.local.md, not in Claude's own memory
        mem = machine.succeed("jq -c .autoMemoryEnabled /home/agent/.claude/settings.json").strip()
        assert mem == "false", f"autoMemoryEnabled={mem!r}"
        # the rm check's prompt, which bypass mode keeps, is answered with allow
        # in bypass mode only
        hook = machine.succeed("jq -r '.hooks.PermissionRequest[0] | .matcher + \" \" + .hooks[0].type + \" \" + .hooks[0].command' /home/agent/.claude/settings.json").split()
        assert hook[:2] == ["Bash|Monitor", "command"], f"PermissionRequest hook: {hook!r}"
        out = machine.succeed(f"echo '{{\"permission_mode\":\"bypassPermissions\",\"tool_name\":\"Bash\"}}' | {hook[2]} | jq -c .").strip()
        assert out == '{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}', f"bypass: {out!r}"
        out = machine.succeed(f"echo '{{\"permission_mode\":\"default\",\"tool_name\":\"Bash\"}}' | {hook[2]}").strip()
        assert out == "", f"default mode got an answer: {out!r}"
        # the plan-limits hook: the same command for Claude and (managed) Codex,
        # answering from a Codex session file even with no Claude login
        usage = machine.succeed("jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' /home/agent/.claude/settings.json").strip()
        req = machine.succeed("cat /etc/codex/requirements.toml")
        assert usage in req and "PostToolUse" in req, f"codex managed hooks: {req!r}"
        machine.succeed(
            "install -D -o agent -g agent ${codexSession} /home/agent/.codex/sessions/2026/01/01/rollout-t.jsonl && "
            "chown -R agent:agent /home/agent/.codex/sessions && install -m 644 ${usageEvent} /tmp/ev.json"
        )
        out = machine.succeed(f"su -s /bin/sh agent -c '{usage} < /tmp/ev.json' | jq -r .hookSpecificOutput.additionalContext").strip()
        assert "Codex 5h 12%" in out and "week 40%" in out and "20% of 475k" in out, f"usage line: {out!r}"
        out = machine.succeed(f"{usage} < /tmp/ev.json").strip()
        assert out == "", f"answered for root: {out!r}"
        # a CLI-owned key survives the merge
        # as_agent() single-quotes its command, so write the CLI key as root
        machine.succeed("""jq '.theme = "dark"' /home/agent/.claude/settings.json > /tmp/s && install -o agent -g agent -m 600 /tmp/s /home/agent/.claude/settings.json""")
        machine.succeed("systemctl restart claude-agent-settings")
        cfg = machine.succeed("cat /home/agent/.claude/settings.json")
        assert '"theme": "dark"' in cfg and '"disableClaudeAiConnectors": true' in cfg, f"merge clobbered: {cfg!r}"

    with subtest("codex config"):
        machine.wait_for_unit("codex-agent-config.service")
        cfg = machine.succeed("cat /home/agent/.codex/config.toml")
        for line in ['sandbox_mode = "danger-full-access"', 'approval_policy = "never"', "memories = false"]:
            assert line in cfg, f"missing {line!r}: {cfg!r}"
        # a CLI-owned key survives the merge
        machine.succeed("""printf 'model = "m"\\n' >> /home/agent/.codex/config.toml""")
        machine.succeed("systemctl restart codex-agent-config")
        cfg = machine.succeed("cat /home/agent/.codex/config.toml")
        assert 'model = "m"' in cfg and "danger-full-access" in cfg, f"merge clobbered: {cfg!r}"
        mode = machine.succeed("stat -c %a /home/agent/.codex/config.toml").strip()
        assert mode == "600", f"config.toml mode {mode}"

    with subtest("git identity is declared"):
        name = machine.succeed(as_agent("git config user.name")).strip()
        email = machine.succeed(as_agent("git config user.email")).strip()
        assert name == "LilijoySkyseeker-agent", f"user.name: {name!r}"
        assert email == "338765425+LilijoySkyseeker-agent@users.noreply.github.com", f"user.email: {email!r}"
        hooks = machine.succeed(as_agent("git hook list prepare-commit-msg"))
        assert "agent-trailer" in hooks, f"the commit trailer hook isn't declared: {hooks!r}"

    with subtest("agent-task"):
        st = "/home/agent/.local/state/agent-task"
        sock = "UNIX-CONNECT:/run/agent-task.sock"
        machine.wait_for_unit("agent-task-broker.socket")
        machine.succeed(task("start t1 -- sh -c \"echo task-hi; pwd; id -un; setsid sleep 700 & sleep 600\""))
        machine.wait_until_succeeds(f"grep -qx task-hi {st}/t1/log")
        out = machine.succeed(f"cat {st}/t1/log").split()
        check("/home/agent/work" in out and "agent" in out, f"cwd or user: {out!r}")
        unit = "agent-task@t1.service"
        got = machine.succeed(f"systemctl show -p ActiveState,Slice,User,ProtectSystem,PrivateDevices {unit}")
        for want in ["ActiveState=active", "Slice=agent.slice", "User=agent", "ProtectSystem=strict", "PrivateDevices=yes"]:
            check(want in got, f"{unit}: no {want} in {got!r}")
        check("t1" in machine.succeed(task("ls")), "agent-task ls doesn't list t1")

        # the agent's boundary holds inside a task: no root files, no LAN
        machine.succeed(task("start t2 -- sh -c \"touch /etc/agent-task-probe 2>/dev/null; echo ETC-RC=\\$?; curl -sS --max-time 5 http://lan:8000/marker >/dev/null 2>&1; echo LAN-RC=\\$?\""))
        machine.wait_until_succeeds(f"grep -q ^LAN-RC= {st}/t2/log")
        out = machine.succeed(f"grep -E '^(ETC|LAN)-RC=' {st}/t2/log")
        check("ETC-RC=0" not in out and "LAN-RC=0" not in out, f"a task got out: {out!r}")
        machine.fail("test -e /etc/agent-task-probe")
        machine.wait_until_succeeds(f"grep -q '^=== .* exited 0' {st}/t2/log")

        # root never opens the task's files: a log symlinked at a root-only
        # file fails the task instead of writing there (started through the
        # broker directly, past the CLI's own header write)
        machine.succeed("echo root-only > /root/target && chmod 600 /root/target")
        machine.succeed(as_agent(f"mkdir -p {st}/t3 && printf \"echo pwned\\n\" > {st}/t3/run && ln -sf /root/target {st}/t3/log"))
        out = machine.succeed(as_agent(f"printf \"start t3\\n\" | socat - {sock}"))
        check(out.strip().splitlines()[-1:] == ["ok"], f"the broker didn't start t3: {out!r}")
        machine.wait_until_succeeds("! systemctl is-active -q agent-task@t3.service")
        check(machine.succeed("cat /root/target").strip() == "root-only", "a task's log reached a root-owned file")

        # only start and stop of a task, through the broker
        for req in ["mask t1", "restart t1", "start ../x", "start sshd.service x", "start t1;id"]:
            out = machine.succeed(as_agent(f"printf \"{req}\\n\" | socat - {sock}"))
            check(out.strip().splitlines()[-1:] != ["ok"], f"broker accepted {req!r}: {out!r}")
        # and no way to systemd's job queue past it (--job-mode=flush cancels others' jobs)
        machine.fail(as_agent("systemctl --job-mode=flush start agent-task@t4.service"))
        machine.fail(as_agent("systemctl start agent-task@t4.service"))
        machine.fail(as_agent("systemctl restart sshd.service"))
        machine.fail(task("start ../x -- true"))
        machine.fail(task("start t1 -- true"))  # already running
        # a task has its own /tmp, so a path in the caller's is refused
        machine.fail(as_agent("cd /tmp && agent-task start t8 -- true"))
        machine.fail(task("start t8 -- bash /tmp/x.sh"))

        # the caller's environment goes with the task, its credentials don't
        machine.succeed(as_agent("cd /home/agent/work && FOO=bar MY_API_KEY=x agent-task start t7 -- sh -c \"echo FOO=\$FOO K=[\$MY_API_KEY]\""))
        machine.wait_until_succeeds(f"grep -q ^FOO= {st}/t7/log")
        out = machine.succeed(f"grep ^FOO= {st}/t7/log").strip()
        check(out == "FOO=bar K=[]", f"task environment: {out!r}")

        # from inside the sandbox, as a live session would: a task starts a task
        machine.succeed(task("start t9 -- agent-task start t10 -- echo inner-hi"))
        machine.wait_until_succeeds(f"grep -qx inner-hi {st}/t10/log", timeout=30)

        # a stop ends the task and everything it started, detached or not
        machine.succeed(task("stop t1"))
        machine.wait_until_fails("pgrep -u agent -x sleep")
        # and the log still gets its last line
        last = machine.succeed(f"tail -n 1 {st}/t1/log").strip()
        check(last.startswith("=== ") and " exited TERM " in last, f"no exit line after stop: {last!r}")
        check(machine.succeed(f"systemctl show -p ActiveState --value {unit}").strip() == "inactive",
              f"{unit} still running after stop")
        # an oversized request gets nothing from root
        out = machine.succeed(as_agent(f"base64 -w0 /dev/urandom | head -c 100000 | socat -t 10 - {sock} || true"))
        check(out.strip().splitlines()[-1:] != ["ok"], f"broker accepted a 100 kB line: {out[:80]!r}")
        assert not failures, "agent-task checks failed:\n" + "\n".join(failures)

    with subtest("agent-setup --check"):
        rc, out = machine.execute(as_agent("agent-setup --check 2>&1"))
        assert rc == 2 and "run0 agent-setup" in out, f"non-root: rc={rc} {out!r}"
        # run0 keeps the caller's cwd; the agent can't read /root (like ~lilijoy)
        rc, out = machine.execute("cd /root && agent-setup --check 2>&1")
        # no logins can exist in the VM, so it must report failures, not fix them
        assert rc == 1, f"rc={rc}: {out}"
        for good in ["✓ agent-user module deployed", "✓ vault folders", "✓ vault mounts",
                     "✓ LAN/tailnet egress blocked"]:
            assert good in out, f"missing {good!r} in:\n{out}"
        for missing in ["✗ gh logged in as LilijoySkyseeker-agent", "✗ Claude login and workspace trust"]:
            assert missing in out, f"missing {missing!r} in:\n{out}"
        machine.fail("test -e /home/agent/.config/gh/hosts.yml")

    with subtest("agent-task: a switch leaves it running, stopping agent.slice ends it"):
        machine.succeed(task("start t6 -- sleep 800"))
        machine.wait_for_unit("agent-task@t6.service")
        pid = lambda: machine.succeed("systemctl show -P MainPID agent-task@t6.service").strip()
        before = pid()
        out = machine.succeed("/run/current-system/specialisation/update/bin/switch-to-configuration test 2>&1")
        machine.sleep(5)
        assert pid() == before, f"agent-task@t6 restarted by a switch: {before} -> {pid()}\n{out}"
        # the owner's kill switch for every agent session and task
        machine.succeed("systemctl stop agent.slice")
        machine.wait_until_fails("pgrep -u agent -x sleep")

    with subtest("agent-task stays stopped after a reboot"):
        machine.succeed(task("start t5 -- sleep 900"))
        machine.wait_for_unit("agent-task@t5.service")
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.sleep(10)
        # nothing started it again this boot
        machine.fail("pgrep -u agent -f \"sleep 900\"")
        machine.fail("journalctl -b 0 -u agent-task@t5.service -o cat | grep -q Started")
  '';
}

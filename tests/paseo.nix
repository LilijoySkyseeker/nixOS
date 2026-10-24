# VM test: Paseo auth, provider migration and the shared agent sandbox
{
  pkgs,
  agentUserModule,
  paseoModule,
}:
pkgs.testers.runNixOSTest {
  name = "paseo";

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        agentUserModule
        paseoModule
      ];
      users.users.lilijoy.isNormalUser = true;
      # mirror torrent: iptables firewall backend
      networking.nftables.enable = false;
      # no tailnet in the VM
      systemd.services.paseo-tailscale-serve.wantedBy = lib.mkForce [ ];
      # stands in for torrent's sops secret: bcrypt of "vm-secret"
      environment.etc."paseo-test-hash".text =
        "$2b$10$6uKC1atpyRerzGiJpPO.EuRdbYW2bfwXkdKbNKqvGrugpC4fA1K0O";
      systemd.services.paseo-agent-config.serviceConfig.LoadCredential =
        "paseo-password-hash:/etc/paseo-test-hash";
      systemd.services.paseo-agent-config.preStart = ''
        mkdir -p /home/agent/.paseo
        echo '{"agents":{"providers":{"local":{"extends":"claude"},"local-codex":{"extends":"codex"}}}}' > /home/agent/.paseo/config.json
      '';
      virtualisation.memorySize = 4096;
      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("tailscale serve waits for the password to be written"):
        deps = machine.succeed("systemctl show paseo-tailscale-serve -p After -p Requires --value")
        assert deps.count("paseo-agent-config.service") == 2, deps

    with subtest("paseo is never published without a password"):
        # with the hash removed from the config, the serve unit must decline
        machine.wait_for_unit("paseo-agent-config.service")
        machine.succeed("""jq 'del(.daemon.auth)' /home/agent/.paseo/config.json > /tmp/c && install -o agent -g agent -m 600 /tmp/c /home/agent/.paseo/config.json""")
        machine.succeed("systemctl start paseo-tailscale-serve || true")
        res = machine.succeed("systemctl show paseo-tailscale-serve -p ActiveState -p ConditionResult --value")
        assert "active" not in res.split()[0:1], res
        machine.succeed("systemctl restart paseo-agent-config")

    with subtest("paseo: agent sandbox, relay off, loopback"):
        machine.wait_for_unit("paseo-agent-config.service")
        cfg = machine.succeed("cat /home/agent/.paseo/config.json")
        assert machine.succeed("""jq -r '.agents.providers | has("local") or has("local-codex")' /home/agent/.paseo/config.json""").strip() == "false", cfg
        assert machine.succeed("jq -r .daemon.relay.enabled /home/agent/.paseo/config.json").strip() == "false", cfg
        assert machine.succeed("jq -r .agents.providers.copilot.enabled /home/agent/.paseo/config.json").strip() == "false", cfg
        # the hash comes from the credential, and the merge writes it back over a stale one
        want = machine.succeed("cat /etc/paseo-test-hash").strip()
        assert machine.succeed("jq -r .daemon.auth.password /home/agent/.paseo/config.json").strip() == want, cfg
        machine.succeed("""jq '.daemon.auth.password = "x"' /home/agent/.paseo/config.json > /tmp/c && install -o agent -g agent -m 600 /tmp/c /home/agent/.paseo/config.json""")
        machine.succeed("systemctl restart paseo-agent-config")
        assert machine.succeed("jq -r .daemon.auth.password /home/agent/.paseo/config.json").strip() == want
        assert machine.succeed("stat -c %a /home/agent/.paseo/config.json").strip() == "600"
        prop = lambda p: machine.succeed(f"systemctl show paseo -p {p} --value").strip()
        for p, want in [("User", "agent"), ("Slice", "agent.slice"), ("PrivateDevices", "yes"), ("NoNewPrivileges", "yes")]:
            assert prop(p) == want, f"paseo {p}={prop(p)!r}"
        assert "firewall.service" in prop("BindsTo"), prop("BindsTo")
        # no password (the hash removed): the daemon declines to start
        machine.succeed("systemctl stop paseo")
        machine.succeed("""jq 'del(.daemon.auth)' /home/agent/.paseo/config.json > /tmp/c && install -o agent -g agent -m 600 /tmp/c /home/agent/.paseo/config.json""")
        machine.succeed("systemctl start paseo || true")
        assert prop("ActiveState") != "active", "paseo ran without a password"
        # with the credential's hash back it starts, on loopback, and refuses anonymous clients
        machine.succeed("systemctl restart paseo-agent-config")
        machine.succeed("systemctl start paseo")
        machine.wait_for_open_port(6767, timeout=120)
        listen = machine.succeed("ss -Hltn 'sport = :6767' | awk '{print $4}'").split()
        assert listen == ["127.0.0.1:6767"], listen
        machine.succeed("curl -sf 127.0.0.1:6767/api/health")
        anon = machine.succeed("curl -s -o /dev/null -w '%{http_code}' 127.0.0.1:6767/api/agents").strip()
        assert anon == "401", f"anonymous /api/agents: {anon}"
        authed = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer vm-secret' 127.0.0.1:6767/api/agents").strip()
        assert authed != "401", f"authenticated /api/agents: {authed}"
  '';
}

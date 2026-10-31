# VM test: local-ai's services without a GPU: llama-swap's routing and the
# gamemode hook's block, paseo in the agent sandbox, the model store's access
{
  pkgs,
  agentUserModule,
  localAiModule,
}:
pkgs.testers.runNixOSTest {
  name = "local-ai";

  # agent-user sets nixpkgs options of its own, so the node imports nixpkgs
  # itself and needs torrent's unfree setting
  node.pkgsReadOnly = false;
  defaults.nixpkgs.config.allowUnfree = true;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        agentUserModule
        localAiModule
      ];
      users.users.lilijoy.isNormalUser = true;
      # mirror torrent: iptables firewall backend
      networking.nftables.enable = false;
      programs.gamemode.enable = true;
      # no tailnet in the VM
      systemd.services.paseo-tailscale-serve.wantedBy = lib.mkForce [ ];
      # stands in for torrent's sops secret: bcrypt of "vm-secret"
      environment.etc."paseo-test-hash".text =
        "$2b$10$6uKC1atpyRerzGiJpPO.EuRdbYW2bfwXkdKbNKqvGrugpC4fA1K0O";
      systemd.services.paseo-agent-config.serviceConfig.LoadCredential =
        "paseo-password-hash:/etc/paseo-test-hash";
      virtualisation.memorySize = 4096;
      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];
    };

  testScript =
    { nodes, ... }:
    let
      custom = nodes.machine.programs.gamemode.settings.custom;
      paseoRoot = builtins.head (
        pkgs.lib.splitString "/bin/paseo" nodes.machine.systemd.services.paseo.serviceConfig.ExecStart
      );
      resumeExec = nodes.machine.systemd.services.paseo-resume.serviceConfig.ExecStart;
      resumeScript = builtins.elemAt (pkgs.lib.splitString " " resumeExec) 1;
    in
    ''
      machine.wait_for_unit("multi-user.target")

      with subtest("llama-swap: loopback, all models listed"):
          machine.wait_for_unit("llama-swap.service")
          machine.wait_for_open_port(8080)
          ids = machine.succeed("curl -sf 127.0.0.1:8080/v1/models | jq -r '.data[].id' | sort").split()
          assert ids == ["qwen3.8-27b"], ids
          listen = machine.succeed("ss -Hltn 'sport = :8080' | awk '{print $4}'").split()
          assert listen == ["127.0.0.1:8080"], listen
          prop = lambda p: machine.succeed(f"systemctl show llama-swap -p {p} --value").strip()
          assert prop("PrivateDevices") == "yes", prop("PrivateDevices")
          assert prop("MemoryMax") != "infinity", prop("MemoryMax")

      with subtest("llama-swap: no cross-origin reads, no stored captures"):
          hdrs = machine.succeed("curl -s -D - -o /dev/null -H 'Origin: https://evil.example' 127.0.0.1:8080/v1/models")
          assert "evil.example" not in hdrs and "access-control-allow-origin: *" not in hdrs.lower(), hdrs
          hdrs = machine.succeed("curl -s -D - -o /dev/null -H 'Origin: http://127.0.0.1:8080' 127.0.0.1:8080/v1/models")
          assert "http://127.0.0.1:8080" in hdrs, hdrs

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

      with subtest("gamemode hook blocks loads, and its end lifts the block"):
          def status(model):
              return machine.succeed(
                  "curl -s -o /dev/null -w '%{http_code}' -m 30 127.0.0.1:8080/v1/chat/completions "
                  "-H 'content-type: application/json' "
                  f"""-d '{{"model":"{model}","messages":[{{"role":"user","content":"hi"}}]}}'"""
              ).strip()
          # the hooks run as the user who started the game
          machine.succeed("su lilijoy -s /bin/sh -c ${custom.start}")
          active = machine.succeed("curl -sf 127.0.0.1:8080/api/profiles | jq -r .active").strip()
          assert active == "gaming", active
          assert status("qwen3.8-27b") == "404", "a model loaded while gaming"
          # a llama-swap restart mid-game keeps the block
          machine.succeed("systemctl restart llama-swap")
          machine.wait_for_open_port(8080)
          active = machine.succeed("curl -sf 127.0.0.1:8080/api/profiles | jq -r .active").strip()
          assert active == "gaming", f"block lost on restart: {active}"
          machine.succeed("su lilijoy -s /bin/sh -c ${custom.end}")
          active = machine.succeed("curl -sf 127.0.0.1:8080/api/profiles | jq -r .active").strip()
          assert active == "null", active
          machine.succeed("systemctl restart llama-swap")
          machine.wait_for_open_port(8080)
          active = machine.succeed("curl -sf 127.0.0.1:8080/api/profiles | jq -r .active").strip()
          assert active == "null", f"block reapplied after the game ended: {active}"
          # no model files in the VM: the load is attempted and fails, it isn't 404
          assert status("qwen3.8-27b") != "404", "still blocked after the game ended"

      with subtest("model store: the agent units write, llama-swap's user reads"):
          got = machine.succeed("stat -c '%a %G' /srv/models").strip()
          assert got == "2775 models", got
          # the agent units' extra group and path, on a probe like agent-user's test
          probe = ("systemd-run --wait --pipe --quiet -E PATH=/run/current-system/sw/bin -p User=agent -p SupplementaryGroups=models "
                   "-p ProtectSystem=strict -p ReadWritePaths=/srv/models -- sh -c ")
          machine.succeed(probe + "'umask 077 && mkdir -p /srv/models/x && echo w > /srv/models/x/m.gguf'")
          machine.succeed("su lilijoy -s /bin/sh -c 'echo more >> /srv/models/x/m.gguf'")
          machine.succeed("systemd-run --wait --pipe --quiet -p DynamicUser=yes -- /run/current-system/sw/bin/cat /srv/models/x/m.gguf")
          # outside the units the agent has no write access
          machine.fail("su agent -s /bin/sh -c 'touch /srv/models/y'")
          for unit in ["paseo"]:
              rw = machine.succeed(f"systemctl show {unit} -p ReadWritePaths --value")
              assert "/srv/models" in rw, f"{unit}: {rw!r}"

      with subtest("paseo: agent sandbox, relay off, loopback"):
          machine.wait_for_unit("paseo-agent-config.service")
          cfg = machine.succeed("cat /home/agent/.paseo/config.json")
          assert machine.succeed("jq -r .daemon.relay.enabled /home/agent/.paseo/config.json").strip() == "false", cfg
          assert machine.succeed("jq -r .agents.providers.copilot.enabled /home/agent/.paseo/config.json").strip() == "false", cfg
          # the hash comes from the credential, and the merge writes it back over a
          # stale one
          want = machine.succeed("cat /etc/paseo-test-hash").strip()
          assert machine.succeed("jq -r .daemon.auth.password /home/agent/.paseo/config.json").strip() == want, cfg
          machine.succeed("""jq '.daemon.auth.password = "x" | .agents.providers.local = {"extends":"claude"} | .agents.providers["local-codex"].models += [{"id":"qwen3.8-flash-next"}]' /home/agent/.paseo/config.json > /tmp/c && install -o agent -g agent -m 600 /tmp/c /home/agent/.paseo/config.json""")
          machine.succeed("systemctl restart paseo-agent-config")
          assert machine.succeed("jq -r .daemon.auth.password /home/agent/.paseo/config.json").strip() == want
          # the local model runs only in the codex harness
          assert machine.succeed("jq -r '.agents.providers | has(\"local\")' /home/agent/.paseo/config.json").strip() == "false"
          ids = machine.succeed("jq -r '.agents.providers[\"local-codex\"].models[].id' /home/agent/.paseo/config.json").split()
          assert ids == ["qwen3.8-27b"], ids
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

      with subtest("paseo defaults bypass permissions and preserve explicit modes"):
          machine.succeed("${pkgs.nodejs}/bin/node ${./paseo-permissions.mjs} ${paseoRoot}")

      with subtest("paseo-resume: decides on recorded limit messages, polls the daemon as agent"):
          machine.succeed("${pkgs.nodejs}/bin/node ${./paseo-resume.mjs} ${resumeScript}")
          machine.wait_for_unit("paseo-resume.service")
          prop = lambda p: machine.succeed(f"systemctl show paseo-resume -p {p} --value").strip()
          for p, want in [("User", "agent"), ("Slice", "agent.slice"), ("ProtectHome", "read-only")]:
              assert prop(p) == want, f"paseo-resume {p}={prop(p)!r}"
          # one poll in the unit's own sandbox, with its local credential
          machine.succeed("systemd-run --wait --pipe --quiet -p User=agent -p ProtectSystem=strict -p ProtectHome=read-only "
                          "-p ReadWritePaths=/home/agent/.paseo -E HOME=/home/agent -- ${resumeExec} --once")
    '';
}

# VM test: local-ai's services without a GPU: llama-swap's routing and the
# gamemode hook's block, paseo in the agent sandbox, the model store's access
{
  pkgs,
  agentUserModule,
  localAiModule,
}:
pkgs.testers.runNixOSTest {
  name = "local-ai";

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
    in
    ''
      machine.wait_for_unit("multi-user.target")

      with subtest("llama-swap: loopback, all models listed"):
          machine.wait_for_unit("llama-swap.service")
          machine.wait_for_open_port(8080)
          ids = machine.succeed("curl -sf 127.0.0.1:8080/v1/models | jq -r '.data[].id' | sort").split()
          assert ids == ["paddleocr-vl", "qwen3.8-27b", "qwen3.8-flash-next"], ids
          listen = machine.succeed("ss -Hltn 'sport = :8080' | awk '{print $4}'").split()
          assert listen == ["127.0.0.1:8080"], listen
          prop = lambda p: machine.succeed(f"systemctl show llama-swap -p {p} --value").strip()
          assert prop("PrivateDevices") == "yes", prop("PrivateDevices")
          assert prop("MemoryMax") != "infinity", prop("MemoryMax")

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
          machine.succeed("su lilijoy -s /bin/sh -c ${custom.end}")
          active = machine.succeed("curl -sf 127.0.0.1:8080/api/profiles | jq -r .active").strip()
          assert active == "null", active
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
          for unit in ["claude-remote-control", "codex-remote-control", "paseo"]:
              rw = machine.succeed(f"systemctl show {unit} -p ReadWritePaths --value")
              assert "/srv/models" in rw, f"{unit}: {rw!r}"

      with subtest("paseo: agent sandbox, relay off, loopback"):
          machine.wait_for_unit("paseo-agent-config.service")
          cfg = machine.succeed("cat /home/agent/.paseo/config.json")
          assert machine.succeed("jq -r .daemon.relay.enabled /home/agent/.paseo/config.json").strip() == "false", cfg
          assert machine.succeed("jq -r .agents.providers.copilot.enabled /home/agent/.paseo/config.json").strip() == "false", cfg
          # an existing key (the owner's password hash) survives the merge
          machine.succeed("""jq '.daemon.auth.password = "x"' /home/agent/.paseo/config.json > /tmp/c && install -o agent -g agent -m 600 /tmp/c /home/agent/.paseo/config.json""")
          machine.succeed("systemctl restart paseo-agent-config")
          assert machine.succeed("jq -r .daemon.auth.password /home/agent/.paseo/config.json").strip() == "x"
          assert machine.succeed("stat -c %a /home/agent/.paseo/config.json").strip() == "600"
          prop = lambda p: machine.succeed(f"systemctl show paseo -p {p} --value").strip()
          for p, want in [("User", "agent"), ("Slice", "agent.slice"), ("PrivateDevices", "yes"), ("NoNewPrivileges", "yes")]:
              assert prop(p) == want, f"paseo {p}={prop(p)!r}"
          assert "firewall.service" in prop("BindsTo"), prop("BindsTo")
          machine.succeed("systemctl stop paseo")
          # without a password set in the VM, start it bare and check it binds loopback only
          machine.succeed("""jq 'del(.daemon.auth)' /home/agent/.paseo/config.json > /tmp/c && install -o agent -g agent -m 600 /tmp/c /home/agent/.paseo/config.json""")
          machine.succeed("systemctl start paseo")
          machine.wait_for_open_port(6767, timeout=120)
          listen = machine.succeed("ss -Hltn 'sport = :6767' | awk '{print $4}'").split()
          assert listen == ["127.0.0.1:6767"], listen
          machine.succeed("curl -sf 127.0.0.1:6767/api/health")
    '';
}

# VM test: local-ai's services without a GPU: llama-swap's routing and the
# gamemode hook's block, paseo in the agent sandbox
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
      # mirror torrent: the agent jobs' schedules use it
      time.timeZone = "America/Los_Angeles";
      # no tailnet in the VM
      systemd.services.paseo-tailscale-serve.wantedBy = lib.mkForce [ ];
      # stands in for torrent's sops secret: bcrypt of "vm-secret"
      environment.etc."paseo-test-hash".text =
        "$2b$10$6uKC1atpyRerzGiJpPO.EuRdbYW2bfwXkdKbNKqvGrugpC4fA1K0O";
      systemd.services.paseo-agent-config.serviceConfig.LoadCredential =
        "paseo-password-hash:/etc/paseo-test-hash";
      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];
    };

  testScript =
    { nodes, ... }:
    let
      custom = nodes.machine.programs.gamemode.settings.custom;
      resumeExec = nodes.machine.systemd.services.paseo-resume.serviceConfig.ExecStart;
      resumeScript = builtins.elemAt (pkgs.lib.splitString " " resumeExec) 1;
    in
    ''
      machine.wait_for_unit("multi-user.target")

      machine.wait_for_unit("llama-swap.service")
      machine.wait_for_open_port(8080)

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

      with subtest("paseo: agent sandbox"):
          machine.wait_for_unit("paseo-agent-config.service")
          cfg = machine.succeed("cat /home/agent/.paseo/config.json")
          assert machine.succeed("jq -r .daemon.mcp.injectIntoAgents /home/agent/.paseo/config.json").strip() == "false", cfg
          # the hash comes from the credential, and the merge writes it back over a
          # stale one
          want = machine.succeed("cat /etc/paseo-test-hash").strip()
          assert machine.succeed("jq -r .daemon.auth.password /home/agent/.paseo/config.json").strip() == want, cfg
          machine.succeed("""jq '.daemon.auth.password = "x" | .agents.providers.opencode.enabled = true | .agents.providers.antigravity.enabled = true' /home/agent/.paseo/config.json > /tmp/c && install -o agent -g agent -m 600 /tmp/c /home/agent/.paseo/config.json""")
          machine.succeed("systemctl restart paseo-agent-config")
          assert machine.succeed("jq -r .daemon.auth.password /home/agent/.paseo/config.json").strip() == want
          for p in ["opencode", "antigravity"]:
              assert machine.succeed(f"jq -r .agents.providers.{p}.enabled /home/agent/.paseo/config.json").strip() == "false", p
          prop = lambda p: machine.succeed(f"systemctl show paseo -p {p} --value").strip()
          # every agent session and scheduled job runs in this unit
          for p, want in [("User", "agent"), ("Slice", "agent.slice"), ("PrivateDevices", "yes"), ("NoNewPrivileges", "yes"),
                          ("PrivateTmp", "yes"), ("ProtectSystem", "strict")]:
              assert prop(p) == want, f"paseo {p}={prop(p)!r}"
          assert "/home/agent" in prop("ReadWritePaths"), prop("ReadWritePaths")
          for sock in ["/run/mullvad-vpn", "/run/tailscale", "/run/libvirt"]:
              assert sock in prop("InaccessiblePaths"), f"{sock} not inaccessible: {prop('InaccessiblePaths')!r}"
          assert "firewall.service" in prop("BindsTo"), prop("BindsTo")
          assert "firewall.service" in prop("After"), prop("After")
          allow, binds = prop("DeviceAllow"), prop("BindPaths")
          for dev in ["/dev/kvm", "/dev/kfd", "/dev/dri/by-path/"]:
              assert dev in allow, f"{dev} not allowed: {allow!r}"
          assert "/dev/dri" in binds and "/dev/kvm" in binds, binds
          assert "tun" not in allow + binds, "tun exposed"
          # no password (the hash removed): the daemon declines to start
          machine.succeed("systemctl stop paseo")
          machine.succeed("""jq 'del(.daemon.auth)' /home/agent/.paseo/config.json > /tmp/c && install -o agent -g agent -m 600 /tmp/c /home/agent/.paseo/config.json""")
          machine.succeed("systemctl start paseo || true")
          assert prop("ActiveState") != "active", "paseo ran without a password"
          # with the credential's hash back it starts, and refuses anonymous clients
          machine.succeed("systemctl restart paseo-agent-config")
          machine.succeed("systemctl start paseo")
          machine.wait_for_open_port(6767, timeout=120)
          anon = machine.succeed("curl -s -o /dev/null -w '%{http_code}' 127.0.0.1:6767/api/agents").strip()
          assert anon == "401", f"anonymous /api/agents: {anon}"
          authed = machine.succeed("curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer vm-secret' 127.0.0.1:6767/api/agents").strip()
          assert authed != "401", f"authenticated /api/agents: {authed}"

      with subtest("paseo-resume: decides on recorded limit messages"):
          machine.succeed("${pkgs.nodejs}/bin/node ${./paseo-resume.mjs} ${resumeScript}")

      with subtest("agent-schedules: the jobs declared in the daemon, kept in step"):
          paseo = "runuser -u agent -- env HOME=/home/agent /etc/profiles/per-user/agent/bin/paseo"
          names = lambda: machine.succeed(f"{paseo} schedule ls --json | jq -r '[.[].name] | sort | join(\" \")'").strip()
          by_id = lambda n: machine.succeed(f"{paseo} schedule ls --json | jq -r --arg n {n} 'map(select(.name == $n))[0].id'").strip()
          # inspect, not ls: ls flattens cadence to a string and has no prompt
          field = lambda n, q: machine.succeed(f"{paseo} schedule inspect {by_id(n)} --json | jq -r '{q}'").strip()
          want = "job:flake-update job:maintenance job:security-watch"
          machine.succeed("systemctl restart agent-schedules")
          assert names() == want, names()
          # a stray job, a hand-edited prompt; an untouched cadence keeps its next run
          machine.succeed(f"{paseo} schedule create --name job:old --cron '0 1 * * *' --provider claude --cwd /home/agent/work old")
          machine.succeed(f"{paseo} schedule update {by_id('job:maintenance')} --prompt drift --cwd /tmp")
          next_run = field("job:security-watch", ".nextRunAt")
          machine.succeed("systemctl restart agent-schedules")
          assert names() == want, names()
          prompt = field("job:maintenance", '.prompt | split("\\n")[0]')
          assert "agent-maintenance" in prompt, prompt
          assert field("job:maintenance", ".target.config.cwd") == "/home/agent/work"
          assert field("job:security-watch", ".nextRunAt") == next_run
          tz = field("job:flake-update", ".cadence.timezone")
          assert tz == "America/Los_Angeles", tz
    '';
}

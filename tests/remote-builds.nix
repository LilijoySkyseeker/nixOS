{
  pkgs,
  buildHostModule,
  remoteBuildsModule,
}:
let
  # nixpkgs' own throwaway test keys, so no private key lives in this repo
  inherit (import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs)
    snakeOilPrivateKey
    snakeOilPublicKey
    snakeOilEd25519PrivateKey
    snakeOilEd25519PublicKey
    ;

  # a derivation with no inputs: the VMs have no network, and the nonce
  # gives every subtest its own store path
  probe = pkgs.writeText "probe.nix" ''
    { nonce, sleep ? "0" }:
    derivation {
      name = "remote-build-probe-''${nonce}";
      system = "x86_64-linux";
      builder = "/bin/sh";
      args = [ "-c" "${pkgs.coreutils}/bin/sleep ''${sleep} && echo ''${nonce} > $out" ];
    }
  '';

  common = {
    # offline VMs: don't wait on cache.nixos.org
    nix.settings.substituters = pkgs.lib.mkForce [ ];
    # the probe calls coreutils' sleep by store path, with no input context
    nix.settings.sandbox = false;
    system.extraDependencies = [ pkgs.coreutils ];
    environment.etc."probe.nix".source = probe;
  };
in
pkgs.testers.runNixOSTest {
  name = "remote-builds";

  nodes = {
    builder =
      { ... }:
      {
        imports = [
          buildHostModule
          common
        ];
        myBuildHost.clientKeys = [ snakeOilEd25519PublicKey ];

        # like torrent: daemon access is limited, nix-builder is trusted
        nix.settings.allowed-users = [ "@wheel" ];

        services.openssh = {
          enable = true;
          settings.PermitRootLogin = "forced-commands-only";
          settings.PasswordAuthentication = false;
          hostKeys = [
            {
              path = "/etc/ssh/test_host_key";
              type = "ecdsa";
            }
          ];
        };
        environment.etc."ssh/test_host_key" = {
          source = snakeOilPrivateKey;
          mode = "0600";
        };
      };

    client =
      { ... }:
      {
        imports = [
          remoteBuildsModule
          common
        ];
        myRemoteBuilds = {
          hostName = "builder";
          hostKey = snakeOilPublicKey;
          sshKey = "/etc/ssh/test_client_key";
        };
        environment.etc."ssh/test_client_key" = {
          source = snakeOilEd25519PrivateKey;
          mode = "0600";
        };

        # stands in for the owner running `nix run` as themselves
        users.users.alice = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
        };
        nix.settings.allowed-users = [ "@wheel" ];
      };
  };

  testScript = ''
    import time

    start_all()
    builder.wait_for_unit("sshd.service")
    client.wait_for_unit("multi-user.target")

    def build(machine, nonce, sleep=0, user=None):
        cmd = (
            f"nix-build /etc/probe.nix --no-out-link "
            f"--argstr nonce {nonce} --argstr sleep {sleep} 2>&1"
        )
        if user:
            cmd = f"su - {user} -c '{cmd}'"
        out = machine.succeed(cmd)
        return out, out.strip().splitlines()[-1]

    with subtest("a user's build runs on the build host"):
        blog, path = build(client, "first", user="alice")
        assert "ssh-ng://nix-builder@builder" in blog, blog
        builder.succeed(f"nix-store --check-validity {path}")
        assert client.succeed(f"cat {path}").strip() == "first"

    with subtest("an output the build host already has is copied, not rebuilt"):
        start = time.monotonic()
        build(builder, "prebuilt", sleep=60)
        assert time.monotonic() - start >= 60, "the probe didn't sleep"
        start = time.monotonic()
        _, path = build(client, "prebuilt", sleep=60)
        took = time.monotonic() - start
        assert took < 30, f"took {took:.0f}s: rebuilt instead of copied"
        assert client.succeed(f"cat {path}").strip() == "prebuilt"

    with subtest("root's builds need ssh on PATH, as in pull-deploy's unit"):
        # root builds in-process, not through the daemon, so the hook finds
        # ssh on the caller's PATH; pull-deploy's unit adds openssh for this
        base = "${pkgs.nix}/bin:${pkgs.coreutils}/bin"
        for nonce, path_ in (("rootpath", f"{base}:${pkgs.openssh}/bin"), ("rootnossh", base)):
            out = client.succeed(
                f"env -i PATH={path_} nix-build /etc/probe.nix "
                f"--no-out-link --argstr nonce {nonce} 2>/dev/null"
            ).strip()
            remote = builder.execute(f"nix-store --check-validity {out}")[0] == 0
            assert remote == (nonce == "rootpath"), f"{nonce}: built remotely={remote}"

    with subtest("the client's key logs in but runs only nix-daemon"):
        accepted = lambda: int(builder.succeed(
            "journalctl -u sshd --no-pager | grep -c 'Accepted publickey for nix-builder' || true"
        ).strip())
        before = accepted()
        client.succeed(
            "timeout 15 ssh -n -i /etc/ssh/test_client_key -o ConnectTimeout=5 "
            "nix-builder@builder 'touch /tmp/escaped' >/dev/null 2>&1 || true"
        )
        builder.wait_until_succeeds(f"test $(journalctl -u sshd --no-pager | grep -c 'Accepted publickey for nix-builder') -gt {before}", timeout=10)
        builder.fail("test -e /tmp/escaped")

    with subtest("remote builds run at idle CPU and IO priority"):
        client.succeed(
            "systemd-run --unit sched-probe -p Environment=PATH=/run/current-system/sw/bin "
            "nix-build /etc/probe.nix --no-out-link --argstr nonce sched --argstr sleep 30"
        )
        pid = builder.wait_until_succeeds("pgrep -f '^/nix/store/[^ ]*/bin/sleep 30'", timeout=20).split()[0]
        cpu = builder.succeed(f"${pkgs.util-linux}/bin/chrt -p {pid}")
        io = builder.succeed(f"${pkgs.util-linux}/bin/ionice -p {pid}")
        assert "SCHED_IDLE" in cpu, cpu
        assert io.strip().startswith("idle"), io

    with subtest("with the build host unreachable, it builds locally"):
        builder.block()
        start = time.monotonic()
        _, path = build(client, "offline")
        took = time.monotonic() - start
        assert took < 60, f"fallback took {took:.0f}s"
        assert client.succeed(f"cat {path}").strip() == "offline"
        builder.unblock()
        builder.fail(f"nix-store --check-validity {path}")
  '';
}

# push-deploy-vps's systemd sandbox under a real `nixos-rebuild switch
# --target-host`: `deployer` (the module's real hardening) must switch
# `target`; `deployer-broken` (PrivateTmp off) must fail
# nixos-rebuild-ng runs its ssh ControlMaster from a tempdir under $TMPDIR,
# so ProtectSystem = "strict" needs PrivateTmp
#
# the pushed flake has no nixpkgs input: a `path:` input re-copies nixpkgs
# under a new hash and the offline VM rebuilds the toolchain. it exposes the
# prebuilt toplevel/nixos-rebuild as locked non-flake `path:` inputs instead
# (storePath, getFlake and bare paths are rejected in pure eval)
#
# targetToplevel comes from `nixos.evalTest`, not `nixosSystem`, so it keeps
# the test framework's node wiring (eth1 vlan, store overlay, backdoor);
# without it the switch tears down eth1 and the store overlay
#
# deployer-broken is a separate node: deriving it from
# config.systemd.services.push-deploy-target in the same set recurses forever
{
  pkgs,
  pushDeployModule,
  nixpkgsUnstableFlake,
}:
let
  # path concatenation, not "${pkgs.path}/..." interpolation: the interpolated
  # copy can be GC'd, after which eval dies with "path ... is not valid"
  inherit (import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs)
    snakeOilEd25519PrivateKey
    snakeOilEd25519PublicKey
    ;

  # shared by the pushed toplevel and target's boot config so the switch
  # doesn't restart sshd or delete the deploy user carrying its own ssh session
  targetAccessConfig = {
    services.openssh.enable = true;
    users.users.deploy = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ snakeOilEd25519PublicKey ];
    };
    # test nodes default this off, dropping bin/switch-to-configuration,
    # which nixos-rebuild invokes remotely
    system.switch.enable = true;
    # same elevation as vps's deploy user: sudo aliased to run0, polkit
    # allowing the unit actions switch-to-configuration and nix-env --set need
    security.sudo.enable = false; # required alongside enableSudoAlias below
    security.run0 = {
      enable = true;
      enableSudoAlias = true;
    };
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.user == "deploy") {
          return polkit.Result.YES;
        }
      });
    '';
    nix.settings.trusted-users = [ "deploy" ];
  };

  # the evalTest runNixOSTest itself uses to build nodes, with the same
  # hostPkgs/node.pkgs; only `.config.nodes.target` is used, so no testScript
  targetEvalTest = nixpkgsUnstableFlake.lib.nixos.evalTest {
    hostPkgs = pkgs;
    node.pkgs = pkgs;
    testScript = "";
    # placeholders so the alphabetical node numbering gives target the same
    # eth1 address (.3) as in the real test; alone it would take deployer's .1
    nodes.deployer = { };
    nodes."deployer-broken" = { };
    nodes.target =
      { ... }:
      {
        imports = [ targetAccessConfig ];
        # test VMs boot without a bootloader; grub's installer fails on the
        # virtio disk during a real switch
        boot.loader.grub.enable = false;
        environment.etc."push-deploy-test-marker".text = "after";
        # docs pull in nixos-render-docs, which isn't needed in the closure
        documentation.enable = false;
      };
  };
  targetSystem = targetEvalTest.config.nodes.target;
  targetToplevel = targetSystem.system.build.toplevel;
  targetNixosRebuild = targetSystem.system.build.nixos-rebuild;

  # the entire pushed flake: the prebuilt paths as locked non-flake `path:`
  # inputs, exposed as the two attributes nixos-rebuild queries
  targetFlake = ''
    {
      inputs.prebuiltToplevel = { url = "path:${targetToplevel}"; flake = false; };
      inputs.prebuiltNixosRebuild = { url = "path:${targetNixosRebuild}"; flake = false; };
      outputs = { self, prebuiltToplevel, prebuiltNixosRebuild }: {
        nixosConfigurations.target.config.system.build = {
          # A non-flake input resolves to its sourceInfo attrset, not a
          # bare path -- .outPath is the actual store path.
          toplevel = prebuiltToplevel.outPath;
          nixos-rebuild = prebuiltNixosRebuild.outPath;
        };
      };
    }
  '';

  deployerNode =
    { ... }:
    {
      imports = [ pushDeployModule ];
      virtualisation.memorySize = 3072;
      virtualisation.diskSize = 8192;

      environment.systemPackages = [ pkgs.git ];

      # registers the prebuilt closures in the VM's nix db at boot so nix
      # doesn't try to build them offline; never read, only presence counts
      environment.etc."push-deploy-test-prebuilt-target".source = targetToplevel;
      environment.etc."push-deploy-test-prebuilt-nixos-rebuild".source = targetNixosRebuild;

      myPushDeploy = {
        enable = true;
        flakeDir = "/root/flakeDir";
        hostAttr = "target";
        targetHost = "deploy@target";
        identityFile = "/root/.ssh/deploy_test_key";
        scheduleEnable = false;
        minSwitchInterval = 1; # positive-integer type; effectively "no wait"
        operation = "switch";
        rebootIfKernelChanged = false;
        elevate = "sudo";
      };
    };

  targetNode =
    { ... }:
    {
      imports = [ targetAccessConfig ];
      environment.etc."push-deploy-test-marker".text = "before";
    };
in
pkgs.testers.runNixOSTest {
  name = "push-deploy-sandbox";

  nodes = {
    deployer = deployerNode;

    # Identical to `deployer` except PrivateTmp is forced off, proving it
    # is load-bearing rather than merely present.
    deployer-broken =
      { lib, ... }:
      {
        imports = [ deployerNode ];
        systemd.services.push-deploy-target.serviceConfig.PrivateTmp = lib.mkForce false;
      };

    target = targetNode;
  };

  testScript = ''
    TARGET_FLAKE = ${builtins.toJSON targetFlake}

    def push_flake(node):
        node.succeed(f"cat > /root/flakeDir/flake.nix <<'FLAKE'\n{TARGET_FLAKE}\nFLAKE")
        node.succeed(
            "cd /root/flakeDir && git add flake.nix && "
            "git -c user.email=a@example.invalid -c user.name=deployer "
            "commit -qm 'push target toplevel' && git push -q origin master"
        )

    def setup_deployer(node):
        node.succeed("mkdir -p -m 700 /root/.ssh")
        node.succeed(
            "install -m 600 ${snakeOilEd25519PrivateKey} /root/.ssh/deploy_test_key"
        )
        # A bare "origin" so fetch_and_merge_master (git fetch + ff-only
        # merge) has something real to talk to, entirely locally -- what's
        # under test is the ssh/nix machinery against `target`, not this
        # repo's actual git remote.
        node.succeed("git init -q --bare /root/origin.git")
        node.succeed("git clone -q /root/origin.git /root/flakeDir")
        push_flake(node)

    start_all()
    deployer.wait_for_unit("multi-user.target")
    deployer_broken.wait_for_unit("multi-user.target")
    target.wait_for_unit("multi-user.target")
    target.wait_for_unit("sshd.service")

    with subtest("the marker starts at its pre-deploy value"):
        assert target.succeed("cat /etc/push-deploy-test-marker").strip() == "before"

    with subtest("target has a real profile symlink, like an installed host would"):
        # A VM test node boots straight from its built closure and never
        # runs a real `nixos-rebuild switch`/install, so
        # /nix/var/nix/profiles/system -- which myPushDeploy's own script
        # stats over ssh before it will proceed -- doesn't exist yet.
        # Every real, already-installed host has this; recreate it so the
        # test target matches that reality instead of a boot-only VM's.
        target.succeed("mkdir -p /nix/var/nix/profiles")
        target.succeed("ln -sfn /run/current-system /nix/var/nix/profiles/system")
        # `stat` (no -L) reports the symlink's own mtime, which would
        # otherwise be "just now" and risk tripping minSwitchInterval's
        # skip guard on a same-second race. Pin it far enough in the past
        # that elapsed time is unambiguous either way.
        target.succeed("touch -h -d @0 /nix/var/nix/profiles/system")

    with subtest("the properly-hardened unit pushes and activates for real"):
        setup_deployer(deployer)
        deployer.succeed("timeout 300 systemctl start push-deploy-target.service 2>&1")
        status = deployer.succeed(
            "systemctl show push-deploy-target.service -p ExecMainStatus --value"
        ).strip()
        assert status == "0", (
            f"push-deploy-target did not exit 0 (ExecMainStatus={status}); "
            + deployer.succeed(
                "journalctl -u push-deploy-target.service --no-pager -n 100"
            )
        )

    with subtest("the push actually reached target -- not just a clean exit"):
        marker = target.succeed("cat /etc/push-deploy-test-marker").strip()
        assert marker == "after", f"target's marker did not flip: {marker!r}"

    with subtest("PrivateTmp is load-bearing: without it, the same unit fails"):
        # no marker reset: /etc is read-only after a real switch; the marker
        # staying "after" proves the broken unit never touched target
        setup_deployer(deployer_broken)

        deployer_broken.fail(
            "timeout 300 systemctl start push-deploy-target.service 2>&1"
        )
        status = deployer_broken.succeed(
            "systemctl show push-deploy-target.service -p ExecMainStatus --value"
        ).strip()
        assert status != "0", "the mis-hardened unit should not have succeeded"

        unit_journal = deployer_broken.succeed(
            "journalctl -u push-deploy-target.service --no-pager -n 200"
        )
        assert "Permission" in unit_journal or "Read-only" in unit_journal, (
            "expected a permission/read-only failure from nixos-rebuild-ng's "
            f"own tmpdir creation, got:\n{unit_journal}"
        )

        # And target must genuinely be untouched -- the failure has to be
        # before activation, not a partial/broken push.
        marker = target.succeed("cat /etc/push-deploy-test-marker").strip()
        assert marker == "after", f"target changed despite the deploy failing: {marker!r}"
  '';
}

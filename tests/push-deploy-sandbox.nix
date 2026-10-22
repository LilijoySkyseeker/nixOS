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
        # still behind head after the push, so deployer-broken gets as far
        # as nixos-rebuild instead of stopping at "manual"; head itself
        # can't be named here, its commit contains this toplevel
        system.configurationRevision = originRev originBase "base";
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

  # the origin the unit mirrors: `base` is what target runs before and after
  # the push, `head` (the target flake) what the deployer runs and so
  # pushes. base is its own derivation: the pushed toplevel names it, and
  # head's commit contains that toplevel
  originBase = pkgs.runCommand "push-deploy-test-origin-base" { nativeBuildInputs = [ pkgs.git ]; } ''
    export HOME=$TMPDIR
    git init -q -b master $out
    git -C $out -c user.email=t@example.invalid -c user.name=test commit -q --allow-empty -m base
    git -C $out rev-parse HEAD > $TMPDIR/base
    mv $TMPDIR/base $out/base
  '';
  # a rev-pinned flake can't have its lock written, so origin commits one,
  # as the real repo does; a path: input locks to its NAR hash
  lockedPath = path: ''
    {
      "flake": false,
      "locked": {
        "lastModified": 1,
        "narHash": "$(nix --extra-experimental-features nix-command --store dummy:// hash path --sri ${path})",
        "path": "${path}",
        "type": "path"
      },
      "original": { "path": "${path}", "type": "path" }
    }
  '';
  origin =
    pkgs.runCommand "push-deploy-test-origin"
      {
        nativeBuildInputs = [
          pkgs.git
          pkgs.nix
        ];
      }
      ''
        export HOME=$TMPDIR
        # the store isn't owned by the build user
        git -c safe.directory='*' clone -q ${originBase} work
        cd work
        cat > flake.nix <<'FLAKE'
        ${targetFlake}
        FLAKE
        cat > flake.lock <<LOCK
        {
          "nodes": {
            "prebuiltToplevel": ${lockedPath targetToplevel},
            "prebuiltNixosRebuild": ${lockedPath targetNixosRebuild},
            "root": {
              "inputs": {
                "prebuiltToplevel": "prebuiltToplevel",
                "prebuiltNixosRebuild": "prebuiltNixosRebuild"
              }
            }
          },
          "root": "root",
          "version": 7
        }
        LOCK
        git add flake.nix flake.lock
        git -c user.email=t@example.invalid -c user.name=test commit -q -m head
        mkdir $out
        git rev-parse HEAD > $out/head
        git clone -q --bare . $out/repo.git
      '';
  # import-from-derivation: the revisions exist only once these are built
  originRev = drv: name: pkgs.lib.removeSuffix "\n" (builtins.readFile "${drv}/${name}");

  deployerNode =
    { ... }:
    {
      imports = [ pushDeployModule ];
      virtualisation.memorySize = 3072;
      virtualisation.diskSize = 8192;

      # what the deployer "switched to itself", so it pushes head
      system.configurationRevision = originRev origin "head";

      # registers the prebuilt closures in the VM's nix db at boot so nix
      # doesn't try to build them offline; never read, only presence counts
      environment.etc."push-deploy-test-prebuilt-target".source = targetToplevel;
      environment.etc."push-deploy-test-prebuilt-nixos-rebuild".source = targetNixosRebuild;

      myPushDeploy = {
        enable = true;
        repoUrl = "file://${origin}/repo.git";
        hostAttr = "target";
        targetHost = "deploy@target";
        identityFile = "/root/.ssh/deploy_test_key";
        scheduleEnable = false;
        operation = "switch";
        rebootIfKernelChanged = false;
        elevate = "sudo";
      };
    };

  targetNode =
    { ... }:
    {
      imports = [ targetAccessConfig ];
      # an ancestor of head, so the push counts as behind, not manual
      system.configurationRevision = originRev originBase "base";
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
    def setup_deployer(node):
        node.succeed("mkdir -p -m 700 /root/.ssh")
        node.succeed(
            "install -m 600 ${snakeOilEd25519PrivateKey} /root/.ssh/deploy_test_key"
        )

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
        # /nix/var/nix/profiles/system -- whose nixos-version myPushDeploy
        # asks over ssh before it will proceed -- doesn't exist yet.
        # Every real, already-installed host has this; recreate it so the
        # test target matches that reality instead of a boot-only VM's.
        target.succeed("mkdir -p /nix/var/nix/profiles")
        target.succeed("ln -sfn /run/current-system /nix/var/nix/profiles/system")

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
        # the mirror and the marker live in the StateDirectory, through
        # ProtectSystem=strict
        deployer.succeed("test -d /var/lib/push-deploy/mirror.git/objects")
        deployer.succeed("test /var/lib/push-deploy/deployed-target -nt /var/lib/push-deploy/mirror.git/HEAD")

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
        # python 3.14's tempfile reports an unwritable /tmp as "No usable
        # temporary directory"; older ones as a permission/read-only error
        assert any(
            s in unit_journal
            for s in ["Permission", "Read-only", "No usable temporary directory"]
        ), (
            "expected a permission/read-only failure from nixos-rebuild-ng's "
            f"own tmpdir creation, got:\n{unit_journal}"
        )

        # And target must genuinely be untouched -- the failure has to be
        # before activation, not a partial/broken push.
        marker = target.succeed("cat /etc/push-deploy-test-marker").strip()
        assert marker == "after", f"target changed despite the deploy failing: {marker!r}"
  '';
}

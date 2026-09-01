# Does push-deploy-vps's systemd sandbox survive a REAL `nixos-rebuild
# switch --target-host`, not just a build?
#
# F-P7-06 / wave 2 item 2.6's deferred third: modules/nixos/push-deploy.nix
# shipped with only NoNewPrivileges for a long time, because a wrong guess
# at the rest of the hardening stack means vps silently stops updating.
# `nixos-rebuild --target-host` shells out to ssh and nix-copy-closure, and
# nixos-rebuild-ng's own source (nixos_rebuild/tmpdir.py, process.py) says
# why that matters: it runs its own SSH ControlMaster through a tempdir
# under `$TMPDIR`/`/tmp`, created once at import time. `ProtectSystem =
# "strict"` alone makes `/tmp` read-only and that fails immediately;
# `PrivateTmp = true` fixes it, since the socket only ever needs to be
# reachable from this unit's own process tree, which shares one mount
# namespace for the life of a single oneshot run.
#
# This test imports the real `push-deploy` module (not a copy) against a
# throwaway setup: `deployer` runs the real `push-deploy-target.service`
# under the module's own real hardening, `target` stands in for vps (an
# unprivileged `deploy` user, real ssh, the same run0-alias-plus-polkit
# elevation vps's own dispatcher uses). The flake being pushed is not this
# repo's real flake -- a tiny `nixosSystem` pinned via `path:${pkgs.path}`
# so no network fetch is needed, evaluated for real by `nixos-rebuild`
# inside the deployer VM.
#
# Positive and negative control, so a pass here is not an accident:
# `deployer` (the module's real, unmodified hardening) must succeed and
# flip target's marker file, and `deployer-broken` -- a second, otherwise
# identical node with only `PrivateTmp` forced off -- must fail. A second
# node rather than a same-VM clone deliberately: referencing
# `config.systemd.services.push-deploy-target` to build a sibling entry in
# the same `systemd.services` set is a real infinite-recursion trap (the
# merged set's evaluation depends on the very entry being defined), caught
# by hitting it here.
{
  pkgs,
  pushDeployModule,
}:
let
  inherit (import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs)
    snakeOilEd25519PrivateKey
    snakeOilEd25519PublicKey
    ;

  # The flake being pushed, templated with a literal `@MARKER@` token (not
  # a Nix interpolation) so the Python test script can substitute it at
  # runtime and prove *which* revision actually landed. Not this repo's
  # real flake -- a minimal standalone one pinned to the same nixpkgs
  # already in the VMs' own store, so evaluating it needs no network fetch.
  targetFlakeTemplate = ''
    {
      inputs.nixpkgs.url = "path:${pkgs.path}";
      outputs = { self, nixpkgs }: {
        nixosConfigurations.target = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [{
            system.stateVersion = "24.05";
            boot.loader.grub.enable = false;
            fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
            networking.hostName = "target";
            environment.etc."push-deploy-test-marker".text = "@MARKER@";
            # Keep this closure buildable purely from what's already in
            # the deployer's own store: NixOS's default
            # documentation.nixos.enable pulls in nixos-render-docs
            # (Python), which isn't pre-cached in the sandboxed test VM
            # and has no network to fetch a source tarball with.
            documentation.enable = false;
          }];
        };
      };
    }
  '';

  deployerNode =
    { config, lib, ... }:
    {
      imports = [ pushDeployModule ];
      virtualisation.memorySize = 3072;
      virtualisation.diskSize = 8192;

      environment.systemPackages = [ pkgs.git ];

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
    { pkgs, ... }:
    {
      services.openssh.enable = true;
      users.users.deploy = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ snakeOilEd25519PublicKey ];
      };
      # Same elevation path vps's real vps-deploy user uses: sudo aliased
      # to run0, authorized via polkit for the systemd-unit actions
      # switch-to-configuration and nix-env --set both need.
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
    FLAKE_TEMPLATE = ${builtins.toJSON targetFlakeTemplate}

    def push_flake(node, marker):
        flake = FLAKE_TEMPLATE.replace("@MARKER@", marker)
        node.succeed(f"cat > /root/flakeDir/flake.nix <<'FLAKE'\n{flake}\nFLAKE")
        node.succeed(
            "cd /root/flakeDir && git add flake.nix && "
            "git -c user.email=a@example.invalid -c user.name=deployer "
            f"commit -qm 'revision {marker}' && git push -q origin master"
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
        push_flake(node, "after")

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
        # Reset the marker so a false pass (the broken unit somehow
        # succeeding) would be caught by the same assertion shape as above.
        target.succeed("echo before > /etc/push-deploy-test-marker")
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
        assert marker == "before", f"target changed despite the deploy failing: {marker!r}"
  '';
}

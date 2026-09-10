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
# repo's real flake -- a tiny one whose only output is a prebuilt
# toplevel (see below for why), evaluated for real by `nixos-rebuild`
# inside the deployer VM, then copied to `target` over real ssh and
# activated there via real `switch-to-configuration`.
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
#
# Why the pushed flake doesn't call `nixpkgs.lib.nixosSystem` at all: an
# earlier version pinned nixpkgs via `inputs.nixpkgs.url =
# "path:${pkgs.path}"`, reasoning that pointing at the exact same nixpkgs
# already in the VMs' own store would mean nothing new to build. It
# doesn't work: nix's `path:` fetcher *re-copies* even an
# already-store-resident tree into a fresh, differently-hashed location
# (confirmed empirically -- `builtins.path { path = pkgs.path; }`
# reproduces the exact rehashed name nix picks). Nixpkgs' own internal
# `./relative` imports then resolve against *that* copy, so every
# derivation that embeds one of them -- which reaches all the way down to
# glibc/stdenv's own patches -- gets a different store path than what's
# already built and registered on the host, and since the VM has no
# network, nix falls back to building the whole toolchain from source.
#
# The fix: nixos-rebuild only ever asks nix to build specific, known
# attribute paths under `.config.system.build` -- confirmed both from
# this test's own failure logs and from nixos-rebuild-ng's own source
# (nixos_rebuild/services.py): `reexec()` queries `config.system.build.
# nixos-rebuild` *first*, to self-update into whatever nixos-rebuild
# version the target flake carries, before the real `switch` flow
# queries `config.system.build.toplevel`. Neither has to be *computed*
# by a real `nixosSystem` call inside the VM at all; each only has to
# *evaluate to a valid derivation*. So `targetToplevel`/
# `targetNixosRebuild` below are built the normal way, out here -- then
# the pushed flake's only content is a `path:`-pinned, non-flake
# (`flake = false`) input for each, re-exposed as the two attributes
# nixos-rebuild needs (a non-flake input resolves to its `sourceInfo`
# attrset, not a bare path -- `.outPath` is the real store path).
# `builtins.storePath`, `builtins.getFlake` on a store path, and a bare
# unquoted path literal were all tried first and rejected outright with
# "forbidden in pure evaluation mode" -- nixos-rebuild's own `nix build`
# never passes `--impure`, and nix treats any absolute path that isn't a
# declared, locked flake input as impure regardless of syntax. A `path:`
# input's own re-copy is harmless here (unlike for nixpkgs above) because
# a *leaf* derivation output -- a finished system closure, a package --
# has no internal relative-path references left to re-root; it's already
# fully realized files and symlinks to other store paths, so re-copying
# it is a filesystem copy, not a rebuild.
#
# `path:`'s locking also fixes a *second* problem for free: nix inside
# the VM only *trusts* a path once it's registered in that VM's own
# local database, and only the closure of the booted node's own
# `system.build.toplevel` gets registered at boot -- physical presence on
# the shared 9p-mounted store isn't enough. Pulling `targetToplevel`/
# `targetNixosRebuild` into `deployer`'s own config (see
# `environment.etc."push-deploy-test-prebuilt-*"` below) puts their whole
# closures -- glibc included -- in that registration.
#
# Why `targetToplevel` is built via `nixpkgsUnstableFlake.lib.nixos.
# evalTest` (the same low-level machinery `pkgs.testers.runNixOSTest`
# itself calls, not a plain `nixosSystem`): a plain `nixosSystem` call
# produces a config with none of the test framework's own
# per-node wiring (inter-VM vlan networking on `eth1`, the 9p-mounted-
# store overlay at /nix/store, `backdoor.service` for the driver's own
# control channel) -- all only ever injected via `runNixOSTest`'s own
# node-building path (confirmed directly: `virtualisation.vlans` doesn't
# even exist as an option on a plain `nixosSystem`, "qemu-vm.nix" isn't
# imported). Activating a toplevel missing all of that made switch-to-
# configuration's own unit-diffing correctly try to stop
# network-addresses-eth1.service (severing the very ssh session driving
# the switch, hanging it for the full 300s) and reload the actively-
# mounted store overlay (which the kernel's overlayfs refuses --
# "No changes allowed in reconfigure" -- making switch-to-configuration's
# own exit code non-zero even though activation otherwise completed).
# Hand-reconstructing each piece (a static `eth1` address, matching
# `fileSystems` entries for the store overlay) fixed each symptom in
# turn but is exactly the kind of drift-prone duplication this whole
# problem is made of, and overlayfs's reconfigure restriction means even
# a near-exact reconstruction still fails. `evalTest` sidesteps all of
# it: it's the *same* function `runNixOSTest` uses internally to build
# each node (`pkgs/build-support/testers/default.nix`'s own
# `runNixOSTest = testModule: nixos.runTest {...}`, `nixos/lib/testing/
# default.nix`'s own `evalTest`/`runTest`), so a node built through it
# gets the exact same wiring as `target`'s own real boot config, byte
# for byte, with nothing to hand-copy or drift out of sync.
{
  pkgs,
  pushDeployModule,
  nixpkgsUnstableFlake,
}:
let
  inherit (import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs)
    snakeOilEd25519PrivateKey
    snakeOilEd25519PublicKey
    ;

  # Shared between the pushed toplevel and target's own pre-deploy boot
  # config, so switching doesn't reconfigure -- and in restarting,
  # disrupt -- the very sshd socket/deploy user carrying the switch's own
  # ssh connection. An earlier version only set this on the boot config;
  # the pushed toplevel had no `services.openssh`/`users.users.deploy` at
  # all, so activating it respectively disabled sshd and deleted the
  # user mid-deploy, and the switch hung for the full 300s timeout
  # instead of failing fast -- a real trap, not specific to this test:
  # any two flake revisions that disagree on how sshd/the deploy user are
  # configured would hit the same thing against a real target.
  targetAccessConfig = {
    services.openssh.enable = true;
    users.users.deploy = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ snakeOilEd25519PublicKey ];
    };
    # VM test nodes default `system.switch.enable = false` (a throwaway
    # test VM is never meant to switch itself), which drops
    # `${toplevel}/bin/switch-to-configuration` entirely -- confirmed
    # directly (`nixos.evalTest`'s own resolved config has
    # `system.switch.enable == false` even with nothing here disabling
    # it). nixos-rebuild-ng invokes exactly that path remotely, so
    # without this override the deploy fails fast with "Failed to find
    # executable .../bin/switch-to-configuration: No such file or
    # directory" -- on `target`, which really is meant to be switched
    # into, this needs to be forced back on.
    system.switch.enable = true;
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
  };

  # Same `nixos.evalTest` machinery `pkgs.testers.runNixOSTest` itself
  # calls to build every node -- see the top-of-file comment for why a
  # plain `nixosSystem` call doesn't work here. `hostPkgs`/`node.pkgs`
  # match what `runNixOSTest` passes (`pkgs.testers.runNixOSTest`'s own
  # implementation: `hostPkgs = pkgs; node.pkgs = pkgsLinux;` --
  # `pkgsLinux` and `pkgs` are the same package set on `x86_64-linux`).
  # `testScript = ""` because only `.config.nodes.target` is used; no
  # actual test driver runs from this evaluation.
  targetEvalTest = nixpkgsUnstableFlake.lib.nixos.evalTest {
    hostPkgs = pkgs;
    node.pkgs = pkgs;
    testScript = "";
    # Empty placeholders for the real test's other two nodes, present
    # *only* so `nixos/lib/testing/network.nix`'s own node-numbering
    # (`zipListsWith nameValuePair (attrNames config.allMachines) (range
    # 1 254)`, alphabetical by node name) assigns "target" the same
    # number here as it gets in the real three-node test below --
    # confirmed the hard way: omitting these makes "target" node 1 (the
    # *only* node in this isolated eval), so its eth1 gets
    # 192.168.1.1 instead of .3, colliding with deployer's own real
    # address the moment the switch activates it and pulling the rug out
    # from under the very ssh session driving the switch (a hang, not an
    # error nixos-rebuild can report -- indistinguishable from the wire
    # simply going quiet).
    nodes.deployer = { };
    nodes."deployer-broken" = { };
    nodes.target =
      { ... }:
      {
        imports = [ targetAccessConfig ];
        # `target`'s real boot config never runs a bootloader at all --
        # VM test nodes boot directly from a kernel/initrd qemu is handed
        # on the command line, bypassing grub entirely, so the fact that
        # `boot.loader.grub.enable` defaults true is never actually
        # exercised there. A genuine `switch-to-configuration switch`
        # does try to run the configured bootloader installer, though,
        # and grub's own default fails outright on this test's virtio
        # root disk ("will not proceed with blocklists" -- no dedicated
        # BIOS boot partition). Disabled here since it was never actually
        # providing a real boot mechanism to preserve anyway.
        boot.loader.grub.enable = false;
        environment.etc."push-deploy-test-marker".text = "after";
        # Keep this closure buildable purely from what's already in
        # the deployer's own store: NixOS's default
        # documentation.nixos.enable pulls in nixos-render-docs
        # (Python), which isn't pre-cached in the sandboxed test VM
        # and has no network to fetch a source tarball with. Moot now
        # that the pushed flake never re-evaluates this module inside
        # the VM, but kept -- there's no reason to want it built at all.
        documentation.enable = false;
      };
  };
  targetSystem = targetEvalTest.config.nodes.target;
  targetToplevel = targetSystem.system.build.toplevel;
  targetNixosRebuild = targetSystem.system.build.nixos-rebuild;

  # The entire pushed flake: no `nixpkgs` input, no `nixosSystem` call --
  # just two *non-flake* inputs (`flake = false`) pointing at the
  # already-built paths above, re-exposed as the two attributes
  # nixos-rebuild needs. See the top-of-file comment for why this shape
  # (a declared, locked `path:` input, not `builtins.storePath`/
  # `builtins.getFlake`/a bare path literal) is what actually works
  # purely.
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
    { config, lib, ... }:
    {
      imports = [ pushDeployModule ];
      virtualisation.memorySize = 3072;
      virtualisation.diskSize = 8192;

      environment.systemPackages = [ pkgs.git ];

      # Pulls targetToplevel/targetNixosRebuild's closures into deployer's
      # own, so they're registered as valid in the VM's nix database at
      # boot instead of nix trying (and, with no network, failing) to
      # build them fresh when nixos-rebuild references the identical
      # derivations inside the VM. targetNixosRebuild should already be
      # part of deployer's closure via myPushDeploy's own `path` (same
      # pin), but registering it explicitly here costs nothing and
      # doesn't depend on that staying true. Neither file is ever read --
      # existing in the closure is the point.
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
    { pkgs, ... }:
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
        # No marker reset here -- target's /etc is now the genuine,
        # declarative post-switch one (a real switch just activated it),
        # so it's read-only the same way any real NixOS host's is; an
        # earlier version's "echo before > ..." reset assumed a writable
        # /etc left over from the VM's own boot-only closure, which this
        # never actually has once a real switch has run. Checking the
        # marker *stays* "after" (its already-correct, already-verified
        # value from the subtest above) proves the same thing a
        # before/after reset would have -- that the broken unit doesn't
        # touch target at all -- without needing to write to it first.
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

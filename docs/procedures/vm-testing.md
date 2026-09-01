# VM-testing a change

Booting a change in a throwaway VM, for when building it proves too
little. Two different tools live here and they answer different
questions — pick deliberately, because the second costs minutes.

For where this sits among the cheaper checks (`nixfmt` → `nix flake
check` → `nixos-rebuild build` → `nvd diff` → switch), see
[`testing-changes.md`](testing-changes.md).

## The two kinds

### 1. Boot a real host config — `system.build.vm`

Builds the actual `nixosConfigurations.<host>` and boots it.

```
nix build .#nixosConfigurations.homelab.config.system.build.vm
QEMU_KERNEL_PARAMS="console=ttyS0" QEMU_OPTS="-nographic -m 4096" \
  ./result/bin/run-homelab-vm
```

Answers "does this host still boot, and do its units start?" — the thing
`nixos-rebuild build` cannot tell you. Cheap to reach for, and the
`workflow.md` convention for a remote install or a risky activation.

It does **not** answer whether a service does its job, because the VM has
none of the host's real state: no zpools, no sops host key, no network.
Expect these to fail on every run and don't chase them:

| Unit | Why it fails in a VM |
|---|---|
| `smartd` | qemu exposes no SMART-capable device |
| anything sops-backed | the host key isn't there, so no secret decrypts |
| impermanence rollback | the real root pool doesn't exist |
| `wireguard-*`, container units | depend on the above, or on real networking |

Run it from a scratch directory — the runner drops a `<host>.qcow2` in
`$PWD` and it is not small. Delete it, and any leftover qemu, when done.

### 2. Assert on runtime behavior — `runNixOSTest`

A python-driven test over one or more VMs, in `tests/`, exposed as a
flake check by `modules/flake/checks.nix`.

```
nix build .#checks.x86_64-linux.zrepl-replication -L
```

Answers "does it actually work?" — multi-host interaction, a service
doing its job, a failure mode you can only reach at runtime.
`tests/zrepl-replication.nix` is the worked example: two nodes, real
zpools, a real replication over SSH.

**Write one when a change's failure mode is invisible to a build and the
blast radius justifies the wait.** The zrepl one paid for itself
immediately — it found a missing `recv.placeholder.encryption` that
`zrepl configcheck` accepts, so no build-time check could ever have
caught it, and every remote pull would have failed on first receive with
the tool it replaced already deleted. That is the shape to look for: a
config that is *valid* but *wrong*, where the truth only appears when
something real happens.

Don't write one for anything a build already catches, and don't reach for
it as a first debugging step — it is minutes per iteration.

### Keep it, or delete it?

A VM test earns a permanent place in `tests/` only if it will be *run
again*. Ask what it guards:

- **Keep** when the module it covers is still going to be edited, and its
  failure mode is quiet — a backup that stops replicating, a firewall
  that stops filtering. Those are the cases where the next person's build
  passes and they have no reason to look closer.
- **Delete** when it verified a specific one-off migration that is now
  finished, or when the thing it covered is gone. A passing test nobody
  will ever need again is just a slow check and a file to maintain — once
  the thing it was proving has actually landed and been confirmed
  working, remove `tests/<name>.nix` and its `modules/flake/checks.nix`
  registration rather than leaving it to rot as dead weight in every
  future `nix flake check`.

One-off verification doesn't need a file at all — boot a
`system.build.vm`, read the result, clean up the qcow2. That leaves no
artifact by design.

If a since-deleted one-off test had genuinely reusable scaffolding inside
it — node/pool setup, a snakeoil-key pattern, anything the *next* test
would otherwise have to reinvent — pull just that part out into a shared
location (there's no `tests/lib.nix` yet; start one when the second test
actually needs to share something) instead of keeping the whole one-off
test around to mine later.

## Adding a check

Add `tests/<name>.nix` returning `pkgs.testers.runNixOSTest { ... }`, then
register it in `modules/flake/checks.nix`:

```nix
checks.<name> = import ../../tests/<name>.nix {
  pkgs = config.flake.pkgsUnstable;
  someModule = config.flake.modules.nixos."<module>";
};
```

Pass the module under test in explicitly rather than importing the whole
host — the point is to exercise the module, not to rebuild a host.

## Things that will bite you

- **`nixos-anywhere --vm-test` can't validate a real disko layout or
  `--extra-files`.** Its throwaway test-VM disk size is hardcoded
  internally (confirmed via `nix show-derivation` on the failing
  `vm-test-run-disko-<host>-disko` build — no CLI flag or env var
  overrides it) and is too small for a disko config with large
  fixed-size partitions (e.g. vps's 18G `nix` partition): `sgdisk`
  fails with `Could not create partition N` before the disk is even
  formatted. It also rejects `--extra-files` outright regardless of
  disk size. In practice this means `--vm-test` only proves something
  for hosts whose disko sizes are small/proportional enough to fit its
  built-in disk, and never proves extra-files placement (e.g. an
  impermanence host's pre-seeded SSH host key) either way — that only
  gets a real check during the actual install. Confirmed safe either
  way: with no `--target-host`/ssh-host argument passed, everything it
  does run stays inside its own isolated qemu sandbox.
- **`git add` new files first.** The flake's source is the git tree, so
  an untracked `tests/foo.nix` is invisible to `nix build` and you get a
  confusing "does not provide attribute" error. Staging is enough; no
  commit needed.
- **Never let a subtest block forever.** A command that waits on stdin
  hangs the whole run until the build times out, and a hang gives you
  nothing to debug — unlike a failure, which prints. Bound anything that
  could wait: `timeout N`, `ssh -n`, `ConnectTimeout`. This is easy to
  hit precisely when things are working — e.g. an SSH forced command that
  successfully starts a long-lived server.
- **Don't pipe the build through `tail`.** It buffers, so you watch an
  empty file for ten minutes. Redirect to a log and `grep` that:
  ```
  nix build .#checks.x86_64-linux.<name> -L > test.log 2>&1
  grep -E "subtest:|failed with error" test.log
  ```
- **Read the daemon's own log on failure.** The subtest tells you *what*
  failed; the service's journal lines in the same log say *why*. Both
  zrepl findings came from the daemon's error text, not the assertion.
- **Declarative SSH keys are not in `~/.ssh`.** NixOS renders
  `users.users.<u>.openssh.authorizedKeys.keys` to
  `/etc/ssh/authorized_keys.d/<user>`.
- **Never embed a private key.** The `pre-commit` hook blocks PEM blocks
  and it is right to — use nixpkgs' snakeoil keys instead:
  ```nix
  inherit (import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs)
    snakeOilEd25519PrivateKey snakeOilEd25519PublicKey;
  ```
- **ZFS nodes need three things**: `boot.supportedFilesystems = [ "zfs" ]`,
  a unique `networking.hostId` per node, and
  `virtualisation.emptyDiskImages` for a spare disk (it appears as
  `/dev/vdb`). Set `boot.zfs.forceImportRoot = false` when the test
  script creates the pools after boot.
- **A cancelled run leaves processes behind.** The test driver and its
  qemu children run as a nix build user, so you cannot signal them
  directly — kill your own `nix build` client instead and let the daemon
  reap them.
- **`pgrep -f qemu` matches your own command line.** Check with
  `ps -eo args` before concluding something is still running.
- **The VM's `/nix/store` is a 9p mount of the *host's real store*, but a
  file being physically present there is not the same as nix trusting
  it.** The guest's nix only considers a store path valid once it is
  registered in *that VM's own* local database, and only the closure of
  the booted node's `system.build.toplevel` gets registered at boot —
  everything else on the shared store is invisible to the guest's nix
  even though it's sitting right there on disk. A flake evaluated
  *inside* the VM (e.g. `nixos-rebuild --flake` against a pushed target)
  that references a derivation outside that closure looks unbuilt, and
  since the VM is also network-isolated, nix falls back to building it
  from scratch — a from-source bootstrap of glibc/stdenv if the gap
  reaches that deep, impractically slow on a single-core test VM. Fix:
  evaluate the identical derivation once in the *outer* Nix expression
  that builds the test (same nixpkgs flake input, same modules) and pull
  its `.config.system.build.toplevel` into the booted node's own config
  (`environment.etc.<name>.source = thatToplevel;` is enough — nothing
  needs to read the file, existing in the closure is the point) so its
  whole closure, glibc included, is already registered when the VM
  boots. `tests/push-deploy-sandbox.nix` is the worked example.
- **`ReadWritePaths` does not create the directory it grants access to.**
  On a fresh root user with no prior `.cache`, `ProtectSystem=strict` +
  `ReadWritePaths=[...]` fails mount-namespace setup outright with ENOENT
  before the unit's script even runs — a real trap only a VM test with a
  genuinely fresh user catches, not a build. A `+`-prefixed
  `ExecStartPre: mkdir -p` does **not** fix it: `+` only bypasses
  privilege-dropping (`User=`/`Group=`), not the mount namespace, which is
  set up once for the whole unit before any `ExecStartPre` runs. The
  directory has to exist before the unit starts at all — use
  `systemd.tmpfiles.rules`.
- **`security.run0.enableSudoAlias` needs `security.run0.enable = true`
  *and* `security.sudo.enable = false` set together**, or you get an
  assertion failure. Check the combination already in real use (e.g.
  `modules/profiles/default.nix`) rather than guessing it.
- **A VM test node boots straight from its built closure and never runs a
  real install or `nixos-rebuild switch`.**
  `/nix/var/nix/profiles/system` won't exist unless the test creates it —
  needed by anything that stats a target's "current generation" over ssh.
  Add `ln -sfn /run/current-system /nix/var/nix/profiles/system`, and pin
  its mtime (`touch -h -d @0 ...`, not `-L`) if anything nearby checks
  elapsed time, so the symlink's just-created mtime can't race a
  same-second skip guard.
- **`documentation.nixos.enable` (on by default) needs
  `nixos-render-docs`, which pulls a real Python source fetch** — an
  unexpected network dependency in an isolated test VM. Set
  `documentation.enable = false;` on a minimal pushed/test config unless
  documentation generation is actually what's under test.
- **A restrictive Nix option type is stricter than it looks.** E.g. an
  option typed `ints.positive` rejects `0` — a test that wants "no wait"
  needs `1` instead. Check the option's real type before assuming a
  boundary value like `0` is accepted.
- **A local Python variable can shadow a name the test driver already
  uses** — e.g. naming something `log` shadows the driver's own built-in
  logger. Caught by the driver's static type checker, not a runtime
  failure; the fix is just renaming the local.
- **Pushing a "foreign" config to an already-running test node? Build it
  through `nixpkgs.lib.nixos.evalTest`, not a plain `nixosSystem` call.**
  `pkgs.testers.runNixOSTest`'s own implementation
  (`pkgs/build-support/testers/default.nix`) is a thin wrapper around
  `nixos.runTest`/`evalTest` (`nixos/lib/testing/default.nix`) with the
  same `hostPkgs`/`node.pkgs` you'd pass yourself. Call `evalTest`
  directly with the same args and a `nodes.<name>` shaped like the real
  node, and the result inherits the test framework's own per-node wiring
  automatically — inter-VM vlan networking (`eth1`), the 9p-mounted-store
  overlay, `backdoor.service` — none of which exist on a plain
  `nixosSystem` config and none of which are easy to hand-reconstruct
  correctly (a near-exact `fileSystems`/`networking.interfaces` copy of
  the real config still isn't enough — see the next few points).
  `evalResult.config.nodes.<name>` is the resolved config directly (no
  extra `.config` beneath that). `tests/push-deploy-sandbox.nix` is the
  worked example.
- **Even inheriting the right wiring, a few defaults still need forcing
  back on for a node that's actually meant to be switched into:**
  - `system.switch.enable` (`nixos/modules/system/activation/
    switchable-system.nix`) defaults to `false` on VM test nodes — makes
    sense for a throwaway VM never meant to switch itself, but it deletes
    `${toplevel}/bin/switch-to-configuration` entirely, so a real
    `nixos-rebuild switch --target-host` against it fails immediately
    with "Failed to find executable .../bin/switch-to-configuration".
    Unrelated to `system.tools.nixos-rebuild.enable`, which only controls
    whether the `nixos-rebuild` *package* gets installed into
    `environment.systemPackages`.
  - A real switch attempts real bootloader installation, which a test
    node's own normal boot (straight from a `-kernel`/`-initrd` qemu was
    handed, bypassing any bootloader) never exercises — so
    `boot.loader.grub.enable` defaulting `true` looks harmless until a
    genuine switch tries to run `grub-install` against the test's virtio
    root disk and fails ("will not proceed with blocklists", no BIOS boot
    partition). Set `boot.loader.grub.enable = false;` on the pushed
    config unless bootloader installation is what's under test.
- **An `evalTest` call built with only the one node you care about
  computes different per-node network addresses than the real multi-node
  test.** `nixos/lib/testing/network.nix`'s node-numbering
  (`zipListsWith nameValuePair (attrNames config.allMachines) (range 1
  254)`, alphabetical by node name) depends on *every* node name present
  in that specific `evalTest` call — an isolated single-node call makes
  that one node "node 1", giving it a different `eth1` address than it
  gets in the real test, which can collide with another real node's own
  address. Symptom is a silent hang, not an error: the moment the pushed
  config activates and claims that address, whichever real node already
  had it loses its own network identity mid-connection, with nothing to
  log because the wire just goes quiet. Fix: declare empty placeholder
  nodes for every *other* real node name in the isolated `evalTest` call
  (`nodes.deployer = {};` etc.) purely so the alphabetical numbering
  lines up — their contents don't matter, only their names do.
- **After a real `switch-to-configuration switch`, `/etc` is genuinely
  read-only** — correct, declarative NixOS behavior, not a bug — so a
  test script step that writes to `/etc/<file>` assuming the boot-only
  VM's writable closure will fail with "Read-only file system" once a
  real switch has actually happened. Check state a different way (does a
  value still equal what it should) rather than trying to reset by
  writing to `/etc` again.

## What these still don't cover

A VM test proves the mechanism, not the deployment. It cannot see the
real pools, the real data volumes, or how long a real transfer takes, and
it says nothing about whether a change was actually switched into a
running system. A fix verified only in isolation and never actually
switched is not a fix — this has happened before in this repo, leaving a
broken service running for days. **Check the live unit after deploying,
not just the build.**

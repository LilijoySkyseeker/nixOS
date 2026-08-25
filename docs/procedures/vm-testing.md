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
  will ever need again is just a slow check and a file to maintain.

One-off verification doesn't need a file at all — boot a
`system.build.vm`, read the result, clean up the qcow2. That leaves no
artifact by design.

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

## What these still don't cover

A VM test proves the mechanism, not the deployment. It cannot see the
real pools, the real data volumes, or how long a real transfer takes, and
it says nothing about whether a change was actually switched into a
running system. `TODO.md` records an incident where a fix was verified in
isolation and never switched, and the broken service kept running for two
days. **Check the live unit after deploying, not just the build.**

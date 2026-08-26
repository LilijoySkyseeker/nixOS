# Adding a new host

`hosts/vps/README.md` is a complete worked example of a real install —
read it alongside this for concrete commands. This page is the general
shape; the vps README has the gotchas for a specific real deploy
(DigitalOcean, impermanence, etc.).

## Steps

1. Create `hosts/<name>/configuration.nix` with genuinely host-local
   config only (hostname, hardware config, disko) — it no longer
   imports profiles or shared modules by path. Add a
   `hosts/<name>/hardware-configuration.nix` placeholder — it gets
   overwritten by the real one in step 4.
2. Add a `flake.nixosConfigurations.<name>` entry to
   `modules/flake/hosts.nix`, picking `nixpkgs-stable` or
   `nixpkgs-unstable`, matching `specialArgs` pattern to an existing
   host on the same channel, and listing whichever `flake.modules.nixos.*`
   registration keys the host needs in its `modules = [ ... ]` list
   (see `docs/architecture.md` for how existing hosts are composed and
   its "Navigating" section for how to find a module's actual
   registration key).
3. Before the target is reachable over SSH via a sops-decrypted secret
   (e.g. Tailscale), that host's SSH host key needs pre-generating
   **outside the repo checkout, even gitignored** — never stage key
   material inside a tracked worktree — converting with `ssh-to-age`,
   enrolling as a new named anchor in `.sops.yaml`'s `keys:` block, and
   re-encrypting via `sops updatekeys secrets/secrets.yaml`, so the new
   host can actually decrypt secrets on first boot. If this step is
   skipped, sops can't decrypt anything on the fresh install —
   including whatever secret is needed to reach the box at all.
4. `scripts/bootstrap-host.sh <name> <ip>` automates step 3 and the
   `nixos-anywhere` invocation itself (builds locally rather than on
   the remote target — small/cheap instances can be memory- or
   disk-constrained enough to hang or OOM mid-install if asked to
   build their own closure). Pass DigitalOcean's `--kexec-extra-flags
   -c` (see gotchas below) and any other `nixos-anywhere` flags after
   a `--`. See `hosts/vps/README.md` for a worked example.

## Gotchas seen in practice

- Impermanence hosts need the `--extra-files` persist path placed
  correctly or the enrolled key won't survive a reboot.
- DigitalOcean specifically needs `nixos-anywhere`'s
  `--kexec-extra-flags -c`.
- Verify disko device names and network interface names against the
  real target before running — a stale/scaffolded hardware config can
  silently point at the wrong disk.
- Legacy BIOS vs UEFI boot loader choice needs to match the real
  target, not be assumed from another host.
- **`kexec` can get OOM-killed on a tiny/RAM-constrained target, and
  swap doesn't reliably fix it.** Confirmed live, twice, against a
  fresh 1GB DigitalOcean droplet: first with no swap at all (613MB
  nominally free per `free -h` still wasn't enough headroom), then
  again *with* a 1G swapfile added — the second failure killed `kexec`
  almost instantly with `anon-rss:0kB`, consistent with `kexec_load`
  needing genuinely free, kernel-pinned physical RAM for the new
  kernel+initrd that can't be satisfied by reclaiming swappable pages
  from other processes. The fix that actually works: temporarily
  resize the target to a bigger RAM tier before installing, resize
  back down once it succeeds — document the temporary spec bump in the
  host's own README (see `hosts/vps/README.md`) so it isn't a surprise
  cost next time. `scripts/bootstrap-host.sh` checks the target's
  total RAM against a 1900MB floor before touching anything (comfortably
  clears DigitalOcean's 2GB tier at ~1962MB, rejects its 1GB tier at
  ~956MB) and refuses to proceed if it's short, rather than run
  headlong into the same OOM again.
- **Recreating a droplet that reuses its old IP leaves a stale SSH
  host key in your `known_hosts`**, since the new box's key is
  different even though the address isn't — `ssh` refuses to connect
  with a scary "REMOTE HOST IDENTIFICATION HAS CHANGED" warning until
  you `ssh-keygen -R <ip>` to clear the old entry. Expected in this
  situation, not a sign of anything actually wrong, but don't blindly
  disable host-key checking to work around it — confirm you actually
  just recreated the box first.

Full detail and exact commands for a real deploy: `hosts/vps/README.md`.

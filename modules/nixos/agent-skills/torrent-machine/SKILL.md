---
name: torrent-machine
description: Facts and limits of torrent, the machine agents run on. Use before GPU or ROCm/Vulkan work, a VM, a large build, a long parallel job or anything disk-heavy, and when a system tool behaves oddly (grep, find, podman, zfs, IPv6, DNS, Playwright).
---

# torrent: the machine you run on

## Hardware (as of 2026-10-17)

- GPU: AMD Radeon RX 7900 XTX (24 GB VRAM, RDNA3 gfx1100), plus the CPU's
  iGPU. You get the 7900 XTX's render node in `/dev/dri` (Vulkan, VA-API)
  and `/dev/kfd` (ROCm). The display nodes (`card*`) and the iGPU are
  visible but refused, so a Vulkan program may print a harmless error about
  `renderD129`.

## Resources and caps

- Nix builds run in the nix daemon, outside that cap, with 16 jobs and the
  `kvm` and `nixos-test` features, so NixOS VM tests run.

## The GPU is the owner's desktop card

Nothing caps VRAM, and the owner's desktop and games use the same card;
they come first. Before a big job, check
`/sys/bus/pci/devices/0000:03:00.0/mem_info_vram_used`, and free the GPU
when you're done. Get tools with `nix shell` (`nixpkgs#vulkan-tools`,
ROCm from `rocmPackages`). The shared local model server is in the
`local-ai` skill: use it rather than loading a second copy of a model.

A Nix-built GPU program that finds no Vulkan device but runs elsewhere
probably pins an older nixpkgs: torrent's Mesa needs the system's glibc.
Build it against the system nixpkgs (`--override-input nixpkgs nixpkgs`).

## VMs

`/dev/kvm` works, so QEMU VMs run accelerated. They get user-mode
networking only (`-nic user`): there is no `/dev/net/tun`, and their traffic
leaves as you, through the same egress firewall.

## Network

- No route to the LAN or the tailnet (the egress firewall rejects them),
  and no IPv6 egress.

## Tools and quirks

- **Containers:** rootless podman fails (`NoNewPrivileges` blocks
  `newuidmap`). Unprivileged bubblewrap works and sees the GPU, so run
  upstream binaries or pip wheels in a `bwrap` or `buildFHSEnv` sandbox.
- **direnv:** your shell doesn't load it. In a repo with an `.envrc`, run
  `direnv allow` once, then `direnv exec <repo> <command>`. The nixOS
  repo's clones and worktrees are already allowed, and there it also wires
  up the git hooks (commit through `direnv exec . git commit`).
- **Missing tools:** `nix shell nixpkgs#<pkg>` (for example `pciutils` for
  `lspci`, `sox`, `imagemagick`). `xvfb-run` is only inside `web-fetch`.
- **Playwright:** there is no `/opt/pw-browsers`; launch with
  `executablePath` set to `$(nix build --no-link --print-out-paths nixpkgs#chromium)/bin/chromium`.
- **Claude Code's shell** replaces `grep` with ugrep and `find` with bfs.
  ugrep rejects some bounded repeats under `-i` ("exceeds complexity
  limits"), and bfs rejects GNU find's relative `-newermt '-15 minutes'`
  (use `-mmin -15`). Codex shells have the GNU tools.
- **Python on downloaded data:** run it with `-I`, from a directory that
  holds only your own scripts.

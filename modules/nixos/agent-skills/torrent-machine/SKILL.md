---
name: torrent-machine
description: Facts and limits of torrent, the machine agents run on. Use before GPU or ROCm/Vulkan work, a VM, a large build, a long parallel job or anything disk-heavy, and when a system tool behaves oddly (grep, find, podman, zfs, IPv6, DNS, Playwright).
---

# torrent: the machine you run on

You run as the Unix user `agent` on torrent, the owner's NixOS desktop, in
systemd units with a sandbox. The user, its units and the egress firewall
are the boundary; the agents' own sandboxes are off (no permission prompts).

## Hardware (as of 2026-10-17)

- CPU: AMD Ryzen 7 9800X3D, 8 cores / 16 threads, up to 5.27 GHz, 96 MiB L3
- RAM: 96 GB, plus a 16 GiB swap partition
- GPU: AMD Radeon RX 7900 XTX (24 GB VRAM, RDNA3 gfx1100), plus the CPU's
  iGPU. You get the 7900 XTX's render node in `/dev/dri` (Vulkan, VA-API)
  and `/dev/kfd` (ROCm). The display nodes (`card*`) and the iGPU are
  visible but refused, so a Vulkan program may print a harmless error about
  `renderD129`.
- Disk: one 4 TB Samsung 990 PRO NVMe, a single ZFS pool (`zroot`) shared
  with the owner's home and `/nix`, about 80-90% full
- Board: Gigabyte X870 AORUS ELITE WIFI7 ICE; Linux 6.18, NixOS unstable

## Resources and caps

Use the machine's full resources without asking: builds, tests and jobs in
parallel and as large as the work needs. The limits are hard, so trying
can't hurt the desktop.

- Every agent session shares one `agent.slice`: 64 GiB of memory, 4096
  tasks, a lower CPU weight (it only matters when the CPU is contended).
- Nix builds run in the nix daemon, outside that cap, with 16 jobs and the
  `kvm` and `nixos-test` features, so NixOS VM tests run.
- Disk is the one shared limit. Clean up caches, downloads and build
  outputs you no longer need. `zfs list` doesn't work in the sandbox; use
  `df`.

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
- torrent's DNS blocks some sites (some people-search brokers resolve to
  nothing or to 127.0.0.1). Don't route around the resolver.
- Localhost works: local services (the model server, Paseo) are reachable
  on 127.0.0.1.

## Tools and quirks

- **Containers:** rootless podman fails (`NoNewPrivileges` blocks
  `newuidmap`). Unprivileged bubblewrap works and sees the GPU, so run
  upstream binaries or pip wheels in a `bwrap` or `buildFHSEnv` sandbox.
- **direnv:** your shell doesn't load it. In a repo with an `.envrc`, run
  `direnv allow` once, then `direnv exec <repo> <command>`. In the nixOS
  repo that also wires up its git hooks.
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

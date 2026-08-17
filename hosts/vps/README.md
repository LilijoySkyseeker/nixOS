# vps

Public-facing tunnel endpoint for CGNAT'd homelab. Terminates the
public IP; homelab dials out to it over WireGuard so nothing needs to
be reachable inbound at home. Caddy (behind an Anubis proof-of-work
challenge) fronts jellyfin; raw TCP/UDP game traffic (minecraft,
factorio) is forwarded straight through the tunnel to homelab.
CrowdSec watches sshd/caddy logs and bans abusive IPs at the firewall.
Admin access (SSH) is over Tailscale only — port 22 is never opened
publicly.

**copyparty is intentionally not exposed here** — it stays
homelab/tailnet-only. Only jellyfin, minecraft, and factorio are meant
to be public.

This is a scaffold — several things still need real values before it
deploys:

## 1. Provision the instance

Pick a provider/region (DigitalOcean SFO or NYC recommended — closest
US regions to homelab + you). Use at least the 1GB RAM / 25GB disk
plan — the vps closure (caddy, crowdsec, tailscale, docker for
minecraft/factorio) is ~8.4GiB, which doesn't fit on the cheapest
512MB/10GB droplet (`disko.nix`'s `/nix` partition is sized for a
25GB disk). Bring the droplet up and install with `nixos-anywhere`:

```
nixos-anywhere --flake .#vps --target-host root@<vps-ip> \
  --generate-hardware-config nixos-generate-config hosts/vps/hardware-configuration.nix \
  --kexec-extra-flags -c
```

`--kexec-extra-flags -c` forces the legacy `KEXEC_LOAD` syscall
instead of the default auto-selected `KEXEC_FILE_LOAD`. On DigitalOcean
(observed on a 512MB SFO droplet) the newer syscall fails with
`kexec_file_load failed: Address not available` — a known issue
(nixos-anywhere#651) tied to secure-boot/signed-kernel verification
support the DO kernel doesn't offer cleanly. `-c` sidesteps it
entirely.

`--generate-hardware-config` has `nixos-anywhere` run
`nixos-generate-config` on the target during install and write the
result to the given path on the local machine — use this for every
new install so `hardware-configuration.nix` reflects the real
instance instead of a stale/scaffolded one. Point the path at
whichever checkout/worktree you're currently working from (not
necessarily `/home/lilijoy/dotfiles`), so the file lands where you'll
actually commit it.

Build on the local machine, not the remote, whenever possible — leave
`--build-on-remote` unset. Small/cheap VPS instances tend to be
memory- and disk-constrained, and building the closure remotely risks
the instance hanging or OOMing mid-install (observed during initial
setup on a prior Vultr instance: the target went unreachable during a
remote closure-copy/GC pass and needed a manual reboot from the
provider console to recover). Building locally and pushing the
finished closure over is more reliable.

Confirm the disk device in `disko.nix` matches the provider's actual
block device (`/dev/vda` is the common default for KVM/virtio, but
check with `lsblk` first) and that `externalInterface` in
`configuration.nix` matches the real public interface name (`ip a` —
often `eth0` on DigitalOcean, but not guaranteed).

## 2. Enroll the host's sops age key + tailscale

After first boot:

```
ssh root@vps 'nix run nixpkgs#ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'
```

Add the resulting `age1...` key to `.sops.yaml`'s `creation_rules` (see
how `homelab3`/`torrent-age` are wired in), then re-encrypt
`secrets/secrets.yaml` so this host can decrypt its secrets. Also add a
`tailscale_authkey_vps` secret (`services.tailscale` itself comes from
`profiles/default.nix`, same as every other host) — SSH access depends
on this box being on the tailnet, since port 22 is never opened
publicly (`networking.firewall.trustedInterfaces = [ "tailscale0" ]`).

## 3. Generate and store the WireGuard keys

```
wg genkey | tee vps-private.key | wg pubkey > vps-public.key
wg genkey | tee homelab-private.key | wg pubkey > homelab-public.key
```

- Put `vps-private.key`'s contents in sops as `vps_wireguard_private_key`
  (manual `sops` edit, not scripted).
- Put `homelab-public.key`'s contents into this file's peer block,
  replacing `REPLACE_WITH_HOMELAB_WIREGUARD_PUBLIC_KEY`.
- homelab needs a matching `networking.wireguard.interfaces.wg0` client
  block (not yet added to `hosts/homelab/configuration.nix`) dialing
  `<vps-ip>:51820`, using `homelab-private.key` as its private key,
  `10.100.0.2/24` as its address, and `vps-public.key` as the peer's
  public key, with `persistentKeepalive` set (CGNAT NAT mappings
  expire without periodic traffic).

## 4. DNS + TLS

The domain is a single Nix value (`vars.domain` in `flake.nix`) shared
between Caddy's `virtualHosts` here and `services/octodns.nix`'s
generated zone data — set it once, both pick it up. See
`services/octodns.nix` for the DNS side (octoDNS + Cloudflare, applied
by a timer on homelab, no checked-in YAML). Caddy will get ACME certs
automatically via HTTP-01 once DNS resolves and ports 80/443 are
reachable — no extra config needed unless you want DNS-01 (e.g. for
wildcard certs), in which case populate `vps_caddy_env` with the DNS
provider's API token and switch Caddy's ACME config to use it.

## 5. Minecraft/Factorio forwarding

`networking.nat.forwardPorts` in `configuration.nix` already forwards
25565/tcp and 34197/udp to homelab's tunnel address
(`10.100.0.2`) — no further config needed once the tunnel is up,
just confirm the ports match `services/minecraft.nix` /
`services/factorio.nix` if those ever change.

## Known gaps in this scaffold

- `hardware-configuration.nix` is a generic virtio stub — replace with
  the real `nixos-generate-config` output if the provider's virtualization
  differs.
- No domains/DNS wired up yet (placeholder in `configuration.nix`).
- CrowdSec is enabled with a few community collections
  (`crowdsecurity/linux`, `crowdsecurity/sshd`, `crowdsecurity/caddy`)
  but nothing beyond that has been tuned — worth reviewing its default
  scenarios/decisions once it's actually seeing traffic.

See `TODO-vps-manual-steps.md` at the repo root for the full,
checkbox-tracked list of what's left before this deploys.

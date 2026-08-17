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

Pick a provider/region (Vultr LA or Silicon Valley recommended — see
prior research). `nixos-anywhere` (build closure locally, push it over
SSH into the provider's rescue-mode kexec environment) proved
unreliable against small/cheap VPS instances — the target went
unreachable mid-install more than once and needed a manual reboot from
the provider console to recover. Instead, install from a custom boot
ISO:

1. Build the repo's installer ISO locally:
   ```
   nix build .#nixosConfigurations.isoimage.config.system.build.isoImage
   ```
   The result symlinks into `./result/iso/*.iso`. It's a generic
   installer for this repo (SSH server with your keys baked in via
   `vars.publicSshKeys`, plus `disko`/`git`/`parted`/`neovim`) — not
   vps-specific, reusable for any bare-metal/cloud host in this flake.
2. Upload that `.iso` as a Custom ISO in the Vultr dashboard, attach it
   to the instance, and boot from it instead of the stock OS image.
3. Once booted, SSH in as root (your key is already authorized) and
   confirm the real disk device and public interface name:
   ```
   lsblk
   ip a
   ```
   Update `disko.nix`'s disk device if it's not `/dev/vda`, and
   `configuration.nix`'s `externalInterface` if it's not `enp1s0`
   (matches the last real instance we saw — not guaranteed to be the
   same on a fresh one).
4. From the booted ISO, clone the repo, regenerate the real hardware
   config, and install:
   ```
   git clone <this-repo-url> /tmp/dotfiles && cd /tmp/dotfiles
   nix run github:nix-community/disko -- --mode disko ./hosts/vps/disko.nix
   nixos-generate-config --no-filesystems --root /mnt \
     --dir /tmp/dotfiles/hosts/vps
   nixos-install --flake .#vps --no-root-passwd
   ```
   `--no-filesystems` matters — disko already declares filesystems in
   `disko.nix`; letting `nixos-generate-config` also write them into
   `hardware-configuration.nix` would conflict. (If any of the
   disk/interface facts above changed, edit them in `/tmp/dotfiles`
   before running `disko`/`nixos-install`.) Copy the resulting
   `hardware-configuration.nix` back into your real checkout afterward
   — it's the only file this whole process produces that needs to be
   committed.
5. Reboot into the installed system, drop the ISO attachment in the
   Vultr dashboard, and confirm it comes up on the real disk (`lsblk`
   should show the `esp`/`nix`/`persist` layout from `disko.nix`, not
   the original stock partitioning).

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

- `hardware-configuration.nix` is a generic virtio stub until step 1.4
  above replaces it with the real `nixos-generate-config` output.
- CrowdSec is enabled with a few community collections
  (`crowdsecurity/linux`, `crowdsecurity/sshd`, `crowdsecurity/caddy`)
  but nothing beyond that has been tuned — worth reviewing its default
  scenarios/decisions once it's actually seeing traffic.

See `TODO-vps-manual-steps.md` at the repo root for the full,
checkbox-tracked list of what's left before this deploys.

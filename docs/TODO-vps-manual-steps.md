# TODO: manual steps to stand up the vps

Temporary tracking doc — delete once the vps is live and this is all
done. See `hosts/vps/README.md` for the fuller background/rationale on
each piece.

## 1. Pre-generate the host SSH key + sops (breaks a chicken-and-egg)

Admin SSH only works over Tailscale, which only comes up once sops
decrypts `tailscale_authkey_vps`, which only works if the vps's age
key is already in `.sops.yaml` — but that key is normally derived
from an SSH host key that doesn't exist until after install. Generate
it locally first, entirely outside this repo checkout (e.g.
`~/vps-extra-files`, never inside the worktree):

- [ ] ```
      mkdir -p ~/vps-extra-files/persist/etc/ssh
      ssh-keygen -t ed25519 -N "" -f ~/vps-extra-files/persist/etc/ssh/ssh_host_ed25519_key
      chmod 600 ~/vps-extra-files/persist/etc/ssh/ssh_host_ed25519_key
      nix run nixpkgs#ssh-to-age < ~/vps-extra-files/persist/etc/ssh/ssh_host_ed25519_key.pub
      ```
- [ ] Add that `age1...` key to `.sops.yaml`'s `creation_rules`
      (alongside `homelab3`/`torrent-age`)
- [ ] `sops updatekeys secrets/secrets.yaml` so the vps is a valid
      recipient before it ever boots
- [ ] Add `tailscale_authkey_vps` secret (same pattern as the other
      hosts — a non-reusable pre-authorized key tagged `tag:vps`)
- [ ] Add `tag:vps` to `tailscale-acl.json`'s `tagOwners` (and decide
      whether it needs `grants`/`ssh` entries — it mainly just needs
      to be reachable by you for admin SSH, not by other tailnet
      devices)

## 2. Provision the instance

- [ ] Pick provider/region — DigitalOcean, SFO or NYC (closest US
      regions to homelab + you), at least the 1GB RAM / 25GB disk plan
      (the 512MB/10GB plan is too small — closure is ~8.4GiB)
- [ ] Create the droplet, confirm from it (SSH in, before running
      nixos-anywhere):
  - [ ] real disk device (`lsblk`) — update `hosts/vps/disko.nix` if
        it's not `/dev/vda`
  - [ ] real public interface name (`ip a`) — update
        `networking.nat.externalInterface` in
        `hosts/vps/configuration.nix` if it's not `eth0`
- [ ] Install, building locally, generating the real hardware config,
      and pre-seeding the SSH host key from step 1 (see
      `hosts/vps/README.md` and `AGENTS.md` for why):
      ```
      nixos-anywhere --flake .#vps --target-host root@<vps-ip> \
        --generate-hardware-config nixos-generate-config hosts/vps/hardware-configuration.nix \
        --kexec-extra-flags -c \
        --extra-files ~/vps-extra-files
      ```

## 3. WireGuard keys — DONE

- [x] Both keypairs generated (`vps_wireguard_private_key`,
      `homelab_wireguard_private_key`) and the PSK
      (`wireguard_vps_homelab_psk`) are all set in sops
- [x] `homelab-public.key` → `hosts/vps/configuration.nix`'s peer entry
- [x] `vps-public.key` → `hosts/homelab/configuration.nix`'s peer entry
- [x] vps's real public IP (IPv6:
      `[2604:a880:4:1d0:0:3:5045:8000]:51820`) → homelab's peer
      `endpoint`
- [x] `nixos-rebuild build --flake .#vps` and `--flake .#homelab` both
      succeed with the tunnel enabled (homelab's `lib.mkIf false`
      wrappers on `wg0`/its secrets removed)

## 4. DNS + domain (octoDNS + Cloudflare, synced from homelab)

DNS is entirely Nix-declared — no checked-in YAML. `services/octodns.nix`
generates octoDNS's config and zone data at build time from `vars.domain`
(in `flake.nix`) and a `vpsPublicIp` value in that same file, and a
systemd timer on homelab applies it to Cloudflare hourly. `vars.domain`
is also what `hosts/vps/configuration.nix`'s Caddy `virtualHosts` reads
for the jellyfin hostname — one edit updates both. Editing a record is
a repo change + `nixos-rebuild switch --flake .#homelab` (or wait for
the timer) — no manual Cloudflare dashboard edits.

- [x] Register/point the real domain's nameservers at Cloudflare
- [x] Create a Cloudflare API token scoped to `Zone:DNS:Edit` for that
      zone, add it to sops as `cloudflare_octodns_token` — note:
      octodns-cloudflare's default `pagerules=true` makes an extra
      `GET /zones/{id}/pagerules` call the DNS-only token can't access,
      which 403s and gets misreported as a DNS auth failure. Fixed by
      setting `pagerules = false` in `services/octodns.nix`'s provider
      config (we don't use Cloudflare page rules).
- [x] Set `vars.domain` in `flake.nix` to the real domain (trailing dot
      required, e.g. `"example.com."`)
- [x] Set `vpsPublicIp` in `services/octodns.nix` to the vps's real
      public IP (137.184.45.18) — also added `vpsPublicIp6` for AAAA
      records (apex, minecraft, factorio all get both A and AAAA now)
- [x] After homelab rebuilds with the real token/domain/IP, manually ran
      `systemctl start octodns-sync.service` once instead of waiting
      for the hourly timer, confirmed via `journalctl -u octodns-sync`
      — 7 changes applied cleanly (2 updates to the apex, 5 creates for
      jellyfin/minecraft/factorio)

## 5. Re-enable the homelab-side services, then deploy

Both are currently disabled on homelab (`lib.mkIf false` / a local
`enable = false;`) so `nixos-rebuild` doesn't fail on the placeholder
values/missing secrets above before the manual work is done:

- [x] `hosts/homelab/configuration.nix`: flip
      `networking.wireguard.interfaces.wg0`'s and
      `sops.secrets.homelab_wireguard_private_key`'s `lib.mkIf false`
      to `lib.mkIf true` (or just drop the `lib.mkIf false` wrapper)
      once the WireGuard keys/IP above are real
- [x] `services/octodns.nix`: flip the `enable = false;` local binding
      to `true` once the Cloudflare token/domain/IP above are real
- [x] `nixos-rebuild build --flake .#vps` (test) then
      `nixos-rebuild switch --flake .#vps` on the vps once everything
      above is filled in
- [x] `nixos-rebuild switch --flake .#homelab` on homelab to bring up
      its side of the wireguard tunnel and the octodns-sync timer
- [x] Verify: `ping 10.100.0.1` from homelab, `ping 10.100.0.2` from vps
- [x] Verify DNS resolves (`dig jellyfin.<domain>`) after the first
      octodns-sync run
- [x] Verify Jellyfin reachable through the real domain — found and
      fixed two real bugs in the process (both live-confirmed, not just
      reasoned through statically):
      1. Anubis's unix socket (`/run/anubis/anubis-jellyfin/anubis.sock`)
         is group-owned `anubis` at mode 0770; caddy runs as a separate
         `caddy` user and had no access, so every request 502'd with
         `dial unix ...: connect: permission denied`. Fixed by adding
         `users.users.caddy.extraGroups = [ "anubis" ]`.
      2. Anubis refuses to reverse-proxy without an `X-Real-Ip` header
         (`[misconfiguration] X-Real-Ip header is not set`) — Caddy's
         `reverse_proxy` doesn't send one by default (only
         `X-Forwarded-For`). Fixed by adding
         `header_up X-Real-Ip {remote_host}` to the jellyfin
         `reverse_proxy` block in `hosts/vps/configuration.nix`.
      After both fixes: confirmed a real Let's Encrypt **production**
      cert (issuer `Let's Encrypt CN=YE1`) is being served, and the
      full chain (Caddy → Anubis → Jellyfin over the wireguard tunnel)
      returns a real `200`/`<title>Jellyfin</title>` page.
- [ ] Verify Minecraft/Factorio reachable on the vps's public IP —
      DNS is live (A/AAAA records exist) but the actual game
      connections haven't been tested yet
- [ ] Verify `noexec` on `/` and `/persist` (`disko.nix`/`configuration.nix`)
      didn't break anything at first boot — this was only statically
      verified (`nix eval`/`nix build`, traced the impermanence bind-mount
      scripts to confirm they don't override the inherited noexec flag),
      never actually booted. Watch `journalctl -b` for `Permission denied`
      / exec-related failures, especially from caddy (ACME), crowdsec,
      tailscale, and the activation/switch process itself. If something
      broke, the likely fix is dropping `noexec` from whichever specific
      mount is affected rather than reverting the whole change.
- [ ] In Jellyfin's admin dashboard (Networking settings), add
      `10.100.0.1` (and `10.100.0.2` itself) to "Known Proxies" —
      without this, Jellyfin sees every external request as coming
      from the vps's tunnel IP instead of the real client IP, which
      breaks its own per-IP failed-login lockout (one bad actor could
      lock out everyone, since they'd all look like the same source).
      This is a runtime dashboard setting, not something Nix declares.
- [ ] Watch Minecraft/Factorio container startup after the
      `--read-only`/`--cap-drop=ALL` change in `services/minecraft.nix`/
      `services/factorio.nix` — `docker logs minecraft-vanilla-plus` /
      `docker logs factorio-main` for "Read-only file system" or
      "Operation not permitted" errors. Both were only reasoned through
      statically (itzg/factoriotools entrypoints are expected to only
      write under /data or /factorio, already-writable volumes, plus
      /tmp which now has a tmpfs) — never actually run under these
      flags. If something breaks: check which path it tried to write,
      add a matching `--tmpfs=/that/path` to `extraOptions` first;
      only drop `--read-only`/`--cap-drop=ALL` entirely as a last
      resort.

## Future: offload vps rebuilds off-box (downsizing prerequisite)

Measured live (2026-08-18): a from-scratch `nixos-rebuild build` on the
vps itself peaked around 1.7GB used + ~424MB swap (out of the droplet's
~2GB total) — evaluation (unpacking/evaluating nixpkgs, home-manager,
disko, etc.), not compilation, was the dominant cost. `myPullDeploy`
currently runs `nixos-rebuild build`/`switch` locally on vps
(`hosts/vps/configuration.nix`), which is why it needs this much RAM at
all. Before downsizing the droplet below ~2GB:

- [ ] Stop evaluating/building on vps itself — run the actual
      `nixos-rebuild switch --target-host` invocation from a beefier
      tailnet machine (homelab, or wherever `myAutoUpdate` already
      builds), so vps only ever activates an already-finished closure.
      This is the main fix; evaluation cost doesn't move to remote
      build machines on its own (see below).
- [ ] Optionally, once that's in place, layer distributed builders on
      top (`nix.distributedBuilds = true` + `nix.buildMachines`
      pointing at other tailnet hosts) so any actual compilation (not
      just evaluation) fans out across the tailnet instead of landing
      on whichever machine initiates the rebuild. Note this only helps
      the *build* phase — it does NOT reduce the evaluation-time memory
      cost measured above, so it's a complement to the point above, not
      a substitute for it.

## Confirmed NOT exposed (by design)

- copyparty — homelab/tailnet-only, no vhost or forward for it anywhere
  in `hosts/vps/configuration.nix`
- SSH to the vps — only reachable over tailscale
  (`networking.firewall.trustedInterfaces = [ "tailscale0" ]`), port 22
  is never opened on the public interface

# TODO: manual steps to stand up the vps

Temporary tracking doc — delete once the vps is live and this is all
done. See `hosts/vps/README.md` for the fuller background/rationale on
each piece.

## 1. Provision the instance

- [ ] Pick provider/region — Vultr, Los Angeles or Silicon Valley
      (lowest latency to homelab + you, only provider researched with
      an actual US West Coast region)
- [ ] Boot it into rescue mode, confirm from there:
  - [ ] real disk device (`lsblk`) — update `hosts/vps/disko.nix` if
        it's not `/dev/vda`
  - [ ] real public interface name (`ip a`) — update
        `networking.nat.externalInterface` in
        `hosts/vps/configuration.nix` if it's not `eth0`
- [ ] Install: `nixos-anywhere --flake .#vps root@<vps-ip>`

## 2. sops

- [ ] `ssh root@vps 'nix run nixpkgs#ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'`
- [ ] Add that `age1...` key to `.sops.yaml`'s `creation_rules`
      (alongside `homelab3`/`torrent-age`)
- [ ] Re-encrypt `secrets/secrets.yaml` for the new recipient
- [ ] Add `tailscale_authkey_vps` secret (same pattern as the other
      hosts — a non-reusable pre-authorized key tagged `tag:vps`)
- [ ] Add `tag:vps` to `tailscale-acl.json`'s `tagOwners` (and decide
      whether it needs `grants`/`ssh` entries — it mainly just needs
      to be reachable by you for admin SSH, not by other tailnet
      devices)

## 3. WireGuard keys

- [ ] Generate both keypairs:
  ```
  wg genkey | tee vps-private.key | wg pubkey > vps-public.key
  wg genkey | tee homelab-private.key | wg pubkey > homelab-public.key
  ```
- [ ] `vps-private.key` → sops secret `vps_wireguard_private_key`
- [ ] `homelab-private.key` → sops secret `homelab_wireguard_private_key`
- [ ] `homelab-public.key` → `hosts/vps/configuration.nix`, replacing
      `REPLACE_WITH_HOMELAB_WIREGUARD_PUBLIC_KEY`
- [ ] `vps-public.key` → `hosts/homelab/configuration.nix`, replacing
      `REPLACE_WITH_VPS_WIREGUARD_PUBLIC_KEY`
- [ ] the vps's actual public IP → `hosts/homelab/configuration.nix`,
      replacing `REPLACE_WITH_VPS_PUBLIC_IP`
- [ ] Generate a preshared key (`wg genpsk`) and put the *same* value
      into sops as `wireguard_vps_homelab_psk` — used verbatim on both
      hosts' peer config (defense-in-depth on top of the keypair
      handshake), not host-prefixed since it must match exactly

## 4. DNS + domain (octoDNS + Cloudflare, synced from homelab)

DNS is entirely Nix-declared — no checked-in YAML. `services/octodns.nix`
generates octoDNS's config and zone data at build time from `vars.domain`
(in `flake.nix`) and a `vpsPublicIp` value in that same file, and a
systemd timer on homelab applies it to Cloudflare hourly. `vars.domain`
is also what `hosts/vps/configuration.nix`'s Caddy `virtualHosts` reads
for the jellyfin hostname — one edit updates both. Editing a record is
a repo change + `nixos-rebuild switch --flake .#homelab` (or wait for
the timer) — no manual Cloudflare dashboard edits.

- [ ] Register/point the real domain's nameservers at Cloudflare
- [ ] Create a Cloudflare API token scoped to `Zone:DNS:Edit` for that
      zone, add it to sops as `cloudflare_octodns_token`
- [ ] Set `vars.domain` in `flake.nix` to the real domain (trailing dot
      required, e.g. `"example.com."`)
- [ ] Set `vpsPublicIp` in `services/octodns.nix` to the vps's real
      public IP (replaces `REPLACE_WITH_VPS_PUBLIC_IP`, used for the
      apex, minecraft, and factorio records)
- [ ] After homelab rebuilds with the real token/domain/IP, manually run
      `systemctl start octodns-sync.service` once instead of waiting
      for the hourly timer, then check `journalctl -u octodns-sync` for
      the actual Cloudflare diff it applied

## 5. Re-enable the homelab-side services, then deploy

Both are currently disabled on homelab (`lib.mkIf false` / a local
`enable = false;`) so `nixos-rebuild` doesn't fail on the placeholder
values/missing secrets above before the manual work is done:

- [ ] `hosts/homelab/configuration.nix`: flip
      `networking.wireguard.interfaces.wg0`'s and
      `sops.secrets.homelab_wireguard_private_key`'s `lib.mkIf false`
      to `lib.mkIf true` (or just drop the `lib.mkIf false` wrapper)
      once the WireGuard keys/IP above are real
- [ ] `services/octodns.nix`: flip the `enable = false;` local binding
      to `true` once the Cloudflare token/domain/IP above are real
- [ ] `nixos-rebuild build --flake .#vps` (test) then
      `nixos-rebuild switch --flake .#vps` on the vps once everything
      above is filled in
- [ ] `nixos-rebuild switch --flake .#homelab` on homelab to bring up
      its side of the wireguard tunnel and the octodns-sync timer
- [ ] Verify: `ping 10.100.0.1` from homelab, `ping 10.100.0.2` from vps
- [ ] Verify DNS resolves (`dig jellyfin.<domain>`) after the first
      octodns-sync run
- [ ] Verify Jellyfin reachable through the real domain (should hit
      the anubis challenge page first, then proxy through on success)
- [ ] Verify Minecraft/Factorio reachable on the vps's public IP
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

## Confirmed NOT exposed (by design)

- copyparty — homelab/tailnet-only, no vhost or forward for it anywhere
  in `hosts/vps/configuration.nix`
- SSH to the vps — only reachable over tailscale
  (`networking.firewall.trustedInterfaces = [ "tailscale0" ]`), port 22
  is never opened on the public interface

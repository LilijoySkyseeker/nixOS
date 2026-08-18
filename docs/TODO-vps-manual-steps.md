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

- [x] ```
      mkdir -p ~/vps-extra-files/persist/etc/ssh
      ssh-keygen -t ed25519 -N "" -f ~/vps-extra-files/persist/etc/ssh/ssh_host_ed25519_key
      chmod 600 ~/vps-extra-files/persist/etc/ssh/ssh_host_ed25519_key
      nix run nixpkgs#ssh-to-age < ~/vps-extra-files/persist/etc/ssh/ssh_host_ed25519_key.pub
      ```
- [x] Add that `age1...` key to `.sops.yaml`'s `creation_rules`
      (alongside `homelab3`/`torrent-age`) — `&vps` key is enrolled
- [x] `sops updatekeys secrets/secrets.yaml` so the vps is a valid
      recipient before it ever boots
- [x] Add `tailscale_authkey_vps` secret (same pattern as the other
      hosts — a non-reusable pre-authorized key tagged `tag:vps`)
- [x] Add `tag:vps` to `tailscale-acl.json`'s `tagOwners` — present in
      `docs/tailscale-acl.json`, plus a ForceCommand allowlist for the
      `vps-deploy` automation user (see the "fix: dispatcher injection"
      commit)

## 2. Provision the instance

- [x] Pick provider/region — ended up on DigitalOcean (an earlier
      Vultr attempt was reverted — see "refactor: switch vps provider
      from Vultr to DigitalOcean")
- [x] Create the droplet, confirm from it:
  - [x] real disk device — `hosts/vps/disko.nix` (`/dev/vda`, real
        `hardware-configuration.nix` generated and checked in)
  - [x] real public interface name — `externalInterface = "ens3"` in
        `hosts/vps/configuration.nix`, with a comment recording a live
        incident where the ens3/ens4 assignment was initially backwards
        and silently broke DNAT for the game ports
- [x] Install — done via `nixos-anywhere` with the real hardware config
      and pre-seeded SSH host key. Also needed a legacy-GRUB fix
      (DigitalOcean chainloads BIOS, not UEFI) and bumping `/nix` to
      18G (the real closure didn't fit in the originally planned 12G).

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
- [x] Verify Minecraft/Factorio reachable on the vps's public IP —
      **root-caused and fixed**. Initial suspicion (DigitalOcean Cloud
      Firewall) was ruled out: the user removed all Cloud Firewalls
      from the droplet and the problem persisted. Actual cause:
      `externalInterface` in `hosts/vps/configuration.nix` was set to
      `ens4`, but `ip a`/`ip route` on the real droplet showed `ens3`
      is the one carrying the public IP and default route (the
      reverse of what an old comment claimed) — every
      DNAT/FORWARD/rate-limit rule was scoped to the wrong interface,
      so real external traffic to 25565/19132/34197 never matched and
      silently vanished. HTTP/HTTPS were unaffected the whole time
      since Caddy listens unscoped on all interfaces, which is what
      masked this. Fixed by switching `externalInterface` to `ens3`;
      confirmed live — Minecraft connects successfully now. A stale
      `-i ens4` rate-limit jump rule is still sitting in the live
      ruleset (harmless, only matches private VPC traffic now) and
      will clear itself on the vps's next reboot.
- [x] Verify `noexec` on `/` and `/persist` (`disko.nix`/`configuration.nix`)
      didn't break anything at first boot — **confirmed live** via SSH
      (`mount` shows `noexec` active on both `/` and `/persist`,
      `journalctl -b` scanned for permission-denied/exec-related
      failures). No noexec-caused breakage found: 0 failed systemd
      units on the current boot (up 13h40m), and caddy/crowdsec/
      crowdsec-firewall-bouncer/tailscaled all `active (running)` for
      hours. The only permission-denied entries in the boot log are the
      already-known-harmless cloud-init `boothooks` writes to a
      read-only `/etc` (see the comment on that in
      `hosts/vps/configuration.nix`) and stale logs from earlier
      deploy-loop attempts within the same boot (WireGuard peer
      failing on the placeholder public key, crowdsec-firewall-bouncer
      failing on a not-yet-provisioned credential) before the real
      secrets/config landed — not noexec-related, and gone by the time
      the system settled. Verified the homelab side of the tunnel too:
      `wg show` has a live handshake (22s old) with real transfer
      stats, `ping 10.100.0.2` from homelab is clean, and
      `octodns-sync.timer` is running on schedule with "no changes
      were planned" (no drift).
- [x] Add `10.100.0.1`/`10.100.0.2` to Jellyfin's "Known Proxies" —
      without this, Jellyfin sees every external request as coming
      from the vps's tunnel IP instead of the real client IP, which
      breaks its own per-IP failed-login lockout (one bad actor could
      lock out everyone, since they'd all look like the same source).
      Made declarative instead of a manual dashboard click: the NixOS
      `jellyfin` module has no option for `network.xml` (only
      `encoding.xml`, via `services.jellyfin.transcoding`/
      `hardwareAcceleration` — confirmed by reading the module source
      in the pinned nixpkgs), so `services/jellyfin.nix` now patches
      `KnownProxies` in `network.xml` via an `xmlstarlet`-based
      `preStart` script (`lib.mkAfter`'d onto the module's own
      `preStart`), idempotent and self-healing on every start, editing
      only that one element so other dashboard-configured network
      settings survive. Verified live on homelab: confirmed
      `network.xml` had an empty `<KnownProxies />` before, deployed
      via `nixos-rebuild switch --flake .#homelab --target-host
      root@homelab`, Jellyfin restarted clean (watched
      `journalctl -u jellyfin`), `network.xml` now has both addresses,
      and `https://jellyfin.skyseekerlabs.net/` still returns a normal
      302 (not the 502 an Anubis/Caddy chain break would cause).
- [x] Watch Minecraft/Factorio container startup after the
      `--read-only`/`--cap-drop=ALL` change — **found and fixed for
      real**: factorio's container hardening broke startup outright
      (see "fix: factorio container hardening was breaking startup
      entirely"), root-caused and resolved without dropping
      `--cap-drop=ALL`. Minecraft's game-port rate limiting was also
      found to be throttling real gameplay traffic (not just abuse)
      and fixed live (see "fix: game-port rate limits were throttling
      real gameplay, not just abuse"). Both are now running live.

## Offload vps rebuilds off-box (downsizing prerequisite) — DONE

Measured live (2026-08-18): a from-scratch `nixos-rebuild build` on the
vps itself peaked around 1.7GB used + ~424MB swap (out of the droplet's
~2GB total) — evaluation (unpacking/evaluating nixpkgs, home-manager,
disko, etc.), not compilation, was the dominant cost.

- [x] Stop evaluating/building on vps itself — **done**. `myPullDeploy`
      was removed from `hosts/vps/configuration.nix`; the vps no longer
      has its own flake checkout or evaluates/builds anything.
      `hosts/homelab/configuration.nix` now runs `myPushDeploy`
      (`hostAttr = "vps"`, `targetHost = "vps-deploy@vps"`), which
      builds vps's config on homelab and pushes+activates the finished
      closure over SSH as the unprivileged `vps-deploy` user (real
      activation via nixos-rebuild's polkit-based `run0` elevator, not
      root login/sudo — see the `vps-deploy` user/ForceCommand
      allowlist in `hosts/vps/configuration.nix`). Wired to
      `systemd.services.nixos-upgrade.onSuccess` right after homelab's
      own `myAutoUpdate` switch, plus a Thursday 03:15 periodic
      fallback timer — confirmed live via
      `systemctl list-timers push-deploy-vps.timer` on homelab.

(The optional follow-on — layering distributed builders across the
tailnet so actual compilation, not just evaluation, fans out — is
cross-host, not vps-specific, so it's tracked in the repo-root
`TODO.md` instead.)

## Confirmed NOT exposed (by design)

- copyparty — homelab/tailnet-only, no vhost or forward for it anywhere
  in `hosts/vps/configuration.nix`
- SSH to the vps — only reachable over tailscale
  (`networking.firewall.trustedInterfaces = [ "tailscale0" ]`), port 22
  is never opened on the public interface

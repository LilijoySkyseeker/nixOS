# vps

Public-facing tunnel endpoint for CGNAT'd `homelab` on DigitalOcean droplet.

## Hardware

DigitalOcean droplet (KVM, `vda`/virtio disk):

- **CPU**: 1 vCPU (`DO-Regular`)
- **RAM**: 1GB, plus a 482MB zram swap device
- **Disk**: 25GB virtio (`vda`)
- **Network**: `ens3` (public IP + a private DigitalOcean VPC address), `ens4`
  (a second private network), plus `wg0` and `tailscale0`

## Reinstall

No local state worth preserving: Caddy/CrowdSec/tailscale config is all
declarative, and secrets re-provision through sops on first boot once
the new host's key is enrolled. See `docs/procedures/new-host.md` for
the general shape; this is the vps-specific worked example.

If the running droplet is unreachable, don't fight a bad boot — destroy
and recreate it in the DO dashboard (no DigitalOcean API tooling lives
in this repo, so that step is manual): `DO-Regular`, 1 vCPU, 1GB RAM,
25GB disk, same region, any SSH key added at creation just needs to
get `nixos-anywhere` in the door. A reserved IP pair survives a
recreate if you reassign it — check the new droplet's actual public
IPv4/IPv6 before assuming either changed. If it's the same IP, clear
the old droplet's now-stale entry first (`ssh-keygen -R <ip>`) — the
new box has a different SSH host key, and `ssh` will otherwise refuse
to connect with a "REMOTE HOST IDENTIFICATION HAS CHANGED" warning.

The 482MB zram swap noted above only exists once NixOS is actually
running — the stock pre-install image has none at all, which matters
for the next step.

**Temporarily resize the droplet up before installing.** Confirmed
live, twice: `kexec` gets OOM-killed on the stock 1GB droplet even
with a swapfile added (it needs genuinely free, kernel-pinned physical
RAM for the new kernel+initrd — not something swap can supply). Bump
it to a bigger RAM tier in the DO dashboard (this needs a power-off/
resize/power-on cycle on the still-stock image — no NixOS state to
lose yet), run the install, then resize back down to `DO-Regular`/1GB
once it succeeds. This is a real, recurring cost tradeoff for this
host, not a one-off — expect to repeat it on every future reinstall
until/unless a lower-memory install path is found.
`scripts/bootstrap-host.sh` checks the target's total RAM (>= 1900MB
— comfortably clears DO's 2GB tier at ~1962MB while rejecting the 1GB
tier at ~956MB) before touching anything and refuses to proceed if
it's short, rather than run headlong into the same OOM again.

Before running the install — the fresh box needs a *working* key the
moment it boots, not after: generate a new tailscale auth key in the
admin console (the old device is stale after a droplet recreate), then
set `tailscale_authkey_vps`'s value via `sops secrets/secrets.yaml`
yourself — value rotation is user-only, see
`docs/procedures/secrets.md`. Doing this after the install just means
the first boot fails to connect on a key that was already dead.

Then, from a machine with the flake checked out (never build on vps
itself — 1 vCPU/1GB is too constrained):

```
scripts/bootstrap-host.sh vps <new-ip> --persist-root /persist -- --kexec-extra-flags -c
```

`--persist-root /persist` matters here specifically: vps's `/` is
tmpfs (impermanence), so a host key written to plain `/etc/ssh` would
vanish on the very first real boot — it has to land at
`/persist/etc/ssh/...`, which is where vps's
`environment.persistence."/persist"` config reads it from. Add `-y` to
skip the "this will WIPE..." confirmation for a scripted/backgrounded
run — piping `y` into stdin instead isn't reliable if the invocation
gets backgrounded (confirmed live: `read` can see EOF regardless of
what was piped in).

`--kexec-extra-flags -c` is DigitalOcean-specific — its kexec target
otherwise fails to pick up an IP. The script handles the rest: fresh
SSH host key generated outside the repo, `.sops.yaml` rotation, `sops
updatekeys`, then the `nixos-anywhere` invocation itself — it does
*not* work around the memory issue above; that's the resize's job.

After install:

- **Resize the droplet back down to `DO-Regular`/1GB** — easy to
  forget once the install itself is working, but the RAM bump above is
  meant to be temporary; leaving it upsized just pays for capacity
  vps doesn't otherwise need. The script prints a reminder on success,
  but do this once you're actually done poking at the new box, not the
  moment it boots (a resize is another power-off/on cycle).
- If the public IP did change, update `modules/services/octodns.nix`'s
  `vpsPublicIp`(`6`) and `hosts/homelab/configuration.nix`'s wireguard
  peer `endpoint`.
- Confirm `crowdsec`, `crowdsec-firewall-bouncer`,
  `tailscaled-autoconnect`, `caddy`, and the fail2ban jail are all
  active before trusting the box, then exercise a real reboot — the
  boot-race fixes (retry-on-failure for crowdsec/the bouncer, a longer
  `tailscaled-autoconnect` timeout) can only be confirmed against
  DigitalOcean's real network-arming delay, not a local VM.

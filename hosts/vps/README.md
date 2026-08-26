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
get `nixos-anywhere` in the door.

Then, from a machine with the flake checked out (never build on vps
itself — 1 vCPU/1GB is too constrained):

```
scripts/bootstrap-host.sh vps <new-ip> --persist-root /persist -- --kexec-extra-flags -c
```

`--persist-root /persist` matters here specifically: vps's `/` is
tmpfs (impermanence), so a host key written to plain `/etc/ssh` would
vanish on the very first real boot — it has to land at
`/persist/etc/ssh/...`, which is where vps's
`environment.persistence."/persist"` config reads it from.

`--kexec-extra-flags -c` is DigitalOcean-specific — its kexec target
otherwise fails to pick up an IP. The script handles the rest: fresh
SSH host key generated outside the repo, `.sops.yaml` rotation, `sops
updatekeys`, then the `nixos-anywhere` invocation itself.

After install:

- Update anything hardcoding the old public IP:
  `modules/services/octodns.nix`'s `vpsPublicIp` and
  `hosts/homelab/configuration.nix`'s wireguard peer `endpoint`.
- Rotate the tailscale auth key: generate a new one in the tailscale
  admin console (the old device is stale after a droplet recreate),
  then set `tailscale_authkey_vps`'s value via `sops
  secrets/secrets.yaml` yourself — value rotation is user-only, see
  `docs/procedures/secrets.md`.
- Confirm `crowdsec`, `crowdsec-firewall-bouncer`,
  `tailscaled-autoconnect`, `caddy`, and the fail2ban jail are all
  active before trusting the box, then exercise a real reboot — the
  boot-race fixes (retry-on-failure for crowdsec/the bouncer, a longer
  `tailscaled-autoconnect` timeout) can only be confirmed against
  DigitalOcean's real network-arming delay, not a local VM.

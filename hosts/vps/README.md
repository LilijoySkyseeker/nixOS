# vps

Public-facing tunnel endpoint for CGNAT'd `homelab` on DigitalOcean droplet.

## Hardware

DigitalOcean droplet (KVM, `vda`/virtio disk):

- **CPU**: 1 vCPU (`DO-Regular`)
- **RAM**: 1GB, plus a 482MB zram swap device
- **Disk**: 25GB virtio (`vda`)
- **Network**: `ens3` (public IP + a private DigitalOcean VPC address), `ens4`
  (a second private network), plus `wg0` and `tailscale0`

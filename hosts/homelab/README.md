# homelab

Old laptop with usb HDD enclose used as main server.

## Hardware

MSI GL62M 7RD laptop:

- **CPU**: Intel Core i5-7300HQ (4 cores/4 threads, 2.50GHz)
- **RAM**: 16GB
- **GPU**: Intel HD Graphics 630 (iGPU) + NVIDIA GeForce GTX 1050 Mobile
- **Boot disk**: 256GB Samsung SATA SSD (`zroot`, single-disk ZFS pool)
- **Storage**: 4x 12TB HGST enterprise drives (HUH721212ALE601) in a
  TerraMaster TDAS enclosure, USB attached behind an ASMedia ASM107x hub,
  in two 2-disk ZFS mirrors (`zdata`, `zbackup`)

## Backups

This host is the backup target and the active side of all replication —
see [`docs/backups.md`](../../docs/backups.md) for the full picture and
[`docs/procedures/backup-restore.md`](../../docs/procedures/backup-restore.md)
for getting data back out.

It **pulls** from `torrent` and `thinkpad` rather than being pushed to, so
it holds an SSH key for them (`homelab_zrepl_key`) and they hold none for
it. It also replicates its own datasets into `zbackup` over zrepl's
in-process `local` transport.

`zbackup` lives on USB-attached drives sharing one hub. This used to be a
severe throughput and I/O-contention constraint: all four drives ran at USB
2.0 High-Speed (480 Mbps) on a single upstream link, a hard ~40-60MB/s
ceiling *across all four combined*, with recurring `uas_eh_abort_handler` /
`stat urb: status -71` faults on the same link.

**Resolved in hardware on 2026-08-23 by replacing the enclosure's USB
cable.** All four drives now enumerate at 5000 Mbps (USB 3.0 SuperSpeed) on
bus 2, and the fault class is gone — zero `uas_eh_*`/urb errors across the
23h following the change, all pools healthy. Verify with:

```
for d in /sys/bus/usb/devices/*/; do [ -f "$d/speed" ] &&   echo "$(basename $d) $(cat $d/speed) $(cat $d/product 2>/dev/null)"; done
```

The four `TerraMaster TDAS` entries should read `5000`; `480` means the link
has renegotiated down (a marginal cable/port) and the old ceiling is back.

The conservative replication settings chosen under the old ceiling are still
in place — replication runs on a 15m interval separate from the 5m snapshot
cadence, and the archive retention grid is tiered rather than a flat year of
dailies. Those are no longer forced by the hardware and could be revisited,
but they have not been re-tuned; see
`2026-08-23-replace-sanoid-syncoid-with-zrepl-repo-wide.md`.


<!-- inventory:start -->
## Host Inventory

_Auto-generated from `nixosConfigurations.homelab`. Regenerate with
`scripts/doc-host.sh homelab` -- do not hand-edit between the markers._

### Services (enabled)

acpid, dbus, fstrim, fwupd, immich, jellyfin, logind, logrotate, lvm, networkd-dispatcher, nixosManual, nscd, openssh, postgresql, resolved, rpcbind, samba, smartd, sshd, systembus-notify, tailscale, timesyncd, udev, udisks2, zrepl

### Packages

acl, attr, audit, backblaze-b2, bash-interactive, bat, bcache-tools, bind, bitwarden-cli, btop, bzip2, comma-with-db-2.4.1, coreutils-full, cpio, cpupower, curl, dbus, dbus-broker, diffutils, direnv, docker, dosfstools, eza, ffmpeg, findutils, flac, fontconfig, fuse, fwupd, gawk, git, glibc, glibc-locales, glow, gnugrep, gnused, gnutar, gzip, helix, hicolor-icon-theme, hostname-debian, iproute2, ipset, iptables, iputils, jq, kbd, kexec-tools, keyutils, kmod, lazygit, less, libcap, libressl, linux-pam, lvm2, man-db, mkpasswd, modemmanager, mtools, nano, ncurses, neovim, networkmanager, nfs-utils, nh, nix, nix-bash-completions, nix-index-with-full-db-0.1.10, nix-info, nixfmt, nixos-build-vms, nixos-configuration-reference-manpage, nixos-enter, nixos-firewall-tool, nixos-generate-config, nixos-help, nixos-install, nixos-manual-html, nixos-option, nixos-rebuild-ng, nixos-version, nvidia-x11, openssh, patch, polkit, postgresql-and-plugins, procps, psmisc, redis, restic, restic-backblazeWeekly, rpcbind, rsync, samba, shadow, shared-mime-info, smartmontools, sops, sound-theme-freedesktop, sudo, systemd, tailscale, texinfo-interactive, time, tldr, tmux, topgrade, trippy, udisks, util-linux, wget, which, wireguard-tools, wpa_supplicant, xz, zfs, zfs-prune-snapshots, zoxide, zrepl, zstd

### Containers

- `factorio-main`
- `minecraft-vanilla-plus`

### Storage (ZFS / network filesystems)

- `/` <- `zroot/local/root` (zfs)
- `/nix` <- `zroot/local/nix` (zfs)
- `/nix/state` <- `zroot/local/state` (zfs)
- `/storage` <- `zdata/storage/storage` (zfs)
- `/storage-bulk` <- `zdata/storage/storage-bulk` (zfs)

### Firewall

- `tailscale0`: TCP 22,445,2049,2283,8096,25565 / UDP 19132,25565,34197
- `wg0`: TCP 8096,25565 / UDP 19132,25565,34197
- plus custom `networking.firewall.extraCommands` iptables rules -- see the host's configuration.nix, not captured here

### Scheduled jobs (systemd timers)

- `beets-import`: -
- `fstrim`: weekly
- `fwupd-refresh`: -
- `health-check`: *:0/15
- `logrotate`: hourly
- `nh-clean`: daily
- `octodns-sync`: -
- `restic-backups-backblazeWeekly`: Fri 03:00:00
- `zfs-scrub`: monthly
- `zpool-trim`: weekly

### Users

Human:
_none_

System (excludes nixbld*/nobody; may include accounts a service
module auto-creates, not just ones this repo hand-declares):
`android-smb`, `beets`, `fwupd-refresh`, `health-check`, `immich`, `jellyfin`, `nm-iodine`, `nscd`, `octodns`, `redis-immich`, `sshd`, `systemd-oom`, `wpa_supplicant`

### Secrets in use

`cloudflare_octodns_token`, `discord_webhook`, `factorio_game_password`, `factorio_token`, `factorio_username`, `git_email`, `git_username`, `homelab_backblaze_rclone_config`, `homelab_backblaze_restic_password`, `homelab_beets_acoustid_apikey`, `homelab_samba_android_smb_password`, `homelab_vps_deploy_key`, `homelab_wireguard_private_key`, `homelab_zrepl_key`, `minecraft_username`, `tailscale_authkey_homelab`, `wireguard_vps_homelab_psk`
<!-- inventory:end -->

# torrent

Primary desktop.

## Hardware

- CPU: Ryzen 7 9800x3D 8x, AMD
- GPU: RX 7900XTX 24 GB, XFX SPEEDSTER MERC 310
- RAM: 96 GB (2x48GB) DDR5 6000MHz CL30, CORSAIR VENGEANCE
- SSD: 4 TB M.2, SAMSUNG 990 PRO
- Motherboard: X870 ATX LGA 1718, GIGABYTE AORUS ELITE ICE
- CPU Cooler: NH-D15 G2, Noctua
- Thermal Paste: PTM 7950
- Power Supply: 1000W ATX 80 PLUS PLATINUM, Super Flower Leadex VI
- Case: Torrent Black Solid, Fractal Design
- Monitors: 1x 27" 4K 60Hz, Dell S2721QS
- Keyboard (Gaming): WOOTING TWO HE
- Mouse: MM710 PMW3389, Cooler Master
- Headphones: WH-1000XM4 (Wired), Sony
- Speakers: A5+, Audioengine
- Microphone: AT2020, Audio-Technica
- Interface: RC-505MKII, BOSS

## Backups

Snapshots and replication are handled by zrepl — see
[`docs/backups.md`](../../docs/backups.md).

**This host now runs `sshd`, which it did not before.** It exists solely to
carry zrepl's `ssh+stdinserver` transport, because homelab *pulls* from
this host rather than being pushed to. It is locked down accordingly:
tailnet-only (`openFirewall = false` plus a `tailscale0` firewall rule),
`PermitRootLogin = "forced-commands-only"`, and the only key in root's
`authorized_keys` is a forced command pinned to
`zrepl stdinserver homelab`. Don't add unrestricted root keys here without
reconsidering that posture.

The impermanence migration has not happened on this host yet, and unlike
thinkpad it has no `@blank` snapshots to preserve.

<!-- inventory:start -->
## Host Inventory

_Auto-generated from `nixosConfigurations.torrent`. Regenerate with
`scripts/doc-host.sh torrent` -- do not hand-edit between the markers._

### Services (enabled)

accounts-daemon, dbus, displayManager, flatpak, fstrim, fwupd, geoclue2, getty, graphical-desktop, libinput, logind, logrotate, lvm, mingetty, mullvad-vpn, nixosManual, nscd, openssh, orca, pcscd, pipewire, power-profiles-daemon, printing, resolved, rpcbind, smartd, speechd, sshd, system-config-printer, systembus-notify, tailscale, timesyncd, udev, udisks2, upower, xserver, zrepl

### Packages

Vial, X11-fonts, accountsservice, acl, akonadi, android-tools, appimage-run, ark, at-spi2-core, attr, aurorae, baloo, baloo-widgets, bambu-studio, bash-interactive, bat, bcache-tools, bind, bitwarden-cli, bitwarden-desktop, bluedevil, bluez, bluez-qt, breeze, breeze-gtk, breeze-icons, btop, bzip2, calibre, caligula, claude-code, comma-with-db-2.4.1, coreutils-full, cpio, cpupower, cups, cups-pk-helper, curl, dbus, dbus-broker, dconf, diffutils, direnv, discord, discover, distrobox, dolphin, dolphin-plugins, dosfstools, drkonqi, easyeffects, element-desktop, elisa, eza, fallback-cursor-theme, fd, feishin, ffmpeg, ffmpegthumbs, filelight, findutils, fish, flac, flatpak, flatpak-kcm, fontconfig, frameworkintegration, fuse, fwupd, gamemode, gawk, geoclue, gh, git, git-with-svn, gjs, glibc, glibc-locales, glow, gnome-boxes, gnugrep, gnused, gnutar, grc, gwenview, gzip, helix, hicolor-icon-theme, hostname-debian, iceauth, iproute2, ipset, iptables, iputils, isd, jq, kactivitymanagerd, kate, kauth, kbd, kcmutils, kconfig, kcoreaddons, kde-cli-tools, kde-gtk-config, kde-inotify-survey, kdeconnect-kde, kded, kdegraphics-thumbnailers, kdenlive, kdepim-runtime, kdeplasma-addons, kexec-tools, keyutils, kfilemetadata, kglobalacceld, kguiaddons, khelpcenter, kiconthemes, kile, kimageformats, kinfocenter, kio, kio-admin, kio-extras, kio-extras-kf5, kio-fuse, kio5-plugins-only, kmenuedit, kmod, knighttime, konsole, kpackage, kpmcore, krdc, krdp, krfb, kscreen, kscreenlocker, kservice, ksystemstats, ktexteditor, kunifiedpush, kwallet, kwallet-pam, kwalletmanager, kwayland-integration, kwin, kwin-x11, kwrited, lazygit, ld-library-path, less, libcap, libkscreen, libksysguard, libplasma, libreoffice, libressl, libvirt, linux-pam, lvm2, lxc, man-db, milou, mkpasswd, modemmanager, mtools, mullvad, mullvad-vpn, nano, ncurses, neovim, net.conf, networkmanager, nfs-utils, nh, nicotine-plus, nix, nix-bash-completions, nix-index-with-full-db-0.1.11, nix-info, nixfmt, nixos-anywhere, nixos-build-vms, nixos-configuration-reference-manpage, nixos-enter, nixos-firewall-tool, nixos-generate-config, nixos-help, nixos-icons, nixos-install, nixos-manual-html, nixos-option, nixos-rebuild-ng, nixos-version, nomadnet, nvf-reference-manpage, nvf-with-helpers, obexftp, ocean-sound-theme, okular, openobex, openssh, orca, partitionmanager, patch, pcsclite-with-polkit, phonon-vlc, picard, pipewire, plasma-activities, plasma-browser-integration, plasma-desktop, plasma-integration, plasma-keyboard, plasma-nm, plasma-pa, plasma-systemmonitor, plasma-workspace, plasma-workspace-wallpapers, podman, podman-docker-compat-5.8.6, polkit, polkit-kde-agent-1, power-profiles-daemon, powerdevil, print-manager, prismlauncher, procps, psmisc, qalculate-qt, qbittorrent, qemu, qpwgraph, qqc2-breeze-style, qqc2-desktop-style, qrca, qtbase, qtimageformats, qtsvg, qttools, qtvirtualkeyboard, qtwayland, quickemu, quodlibet, r2modman, rclone, restic, ripgrep, rns, rpcbind, rsync, rtkit, run0-sudo-shim, sane-airscan, sane-backends, scrcpy, sddm, setxkbmap, shadow, shared-mime-info, signal-desktop, skanpage, smartmontools, solid, sops, sound-theme-freedesktop, spectacle, speech-dispatcher, spice-gtk, spotify, ssh-to-age, steam, steam-run, systemd, systemsettings, tailscale, texinfo-interactive, texlive, thunderbird, time, tldr, tmux, topgrade, trippy, udisks, ungoogled-chromium, union, upower, util-linux, vesktop, vipsdisp, virt-manager, vlc, vscode, waydroid, wget, which, wireplumber, wl-clipboard, wootility, wpa_supplicant, xauth, xdg-desktop-portal, xdg-desktop-portal-gtk, xdg-desktop-portal-kde, xdg-user-dirs, xdg-utils, xf86-input-evdev, xf86-input-libinput, xinput, xlsclients, xorg-server, xprop, xrandr, xrdb, xset, xsetroot, xterm, xwayland, xz, yt-dlp, yubikey-manager, yubioath-flutter, zfs, zfs-prune-snapshots, zoxide, zrepl, zstd

### Containers

_none_

### Storage (ZFS / network filesystems)

- `/` <- `zroot/local/root` (zfs)
- `/home` <- `zroot/local/home` (zfs)
- `/home/lilijoy/storage` <- `homelab:/storage` (nfs4)
- `/home/lilijoy/storage-bulk` <- `homelab:/storage-bulk` (nfs4)
- `/nix` <- `zroot/local/nix` (zfs)

### Firewall

- `podman0`: TCP - / UDP -
- `tailscale0`: TCP 22 / UDP -
- plus custom `networking.firewall.extraCommands` iptables rules -- see the host's configuration.nix, not captured here

### Scheduled jobs (systemd timers)

- `fstrim`: weekly
- `fwupd-refresh`: -
- `health-check`: *:0/15
- `logrotate`: hourly
- `nh-clean`: daily
- `podman-prune`: -
- `zfs-scrub`: monthly
- `zpool-trim`: weekly

### Users

Human:
`lilijoy`

System (excludes nixbld*/nobody; may include accounts a service
module auto-creates, not just ones this repo hand-declares):
`flatpak`, `fwupd-refresh`, `geoclue`, `health-check`, `mandb`, `nm-iodine`, `nscd`, `pcscd`, `rtkit`, `sshd`, `systemd-oom`, `wpa_supplicant`

### Secrets in use

`discord_webhook`, `git_email`, `git_username`, `tailscale_authkey_torrent`
<!-- inventory:end -->

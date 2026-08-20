# modules/nixos

Reusable NixOS option modules. A module only takes effect if some host
or profile actually imports it — see `docs/architecture.md` for each
host's import chain. Modules that define a real options surface follow
the `my<Name>` convention documented in `docs/style-guide.md`; the rest
are plain config wired directly to upstream NixOS options.

## Inventory

- `auto-update.nix` — `myAutoUpdate`: scheduled flake.lock bump +
  build-test on a branch, merges to master only if it builds.
- `health-alerts.nix` — `myHealthAlerts`: periodic ZFS/SMART/systemd
  health checks with Discord webhook alerts.
- `iso-autobuild.nix` — `myIsoAutobuild`: auto-builds the isoimage
  flake output, pruning older same-prefix ISOs.
- `kde.nix` — KDE Plasma desktop environment and related packages.
- `nfs-homelab-mounts.nix` — client-side automount of homelab's NFS
  shares over tailnet.
- `pull-deploy.nix` — `myPullDeploy`: scheduled local pull+build+switch
  (self-updating host).
- `push-deploy.nix` — `myPushDeploy`: scheduled build-locally,
  push-and-activate on a remote host.
- `tooling.nix` — shared CLI tooling (git, fish, neovim as default
  editor) at the NixOS level.
- `virtual-machines.nix` — libvirtd/virt-manager/gnome-boxes + USB
  passthrough, system side.
- `wooting.nix` — Wooting keyboard hardware support.

## Gotchas

- `nfs-homelab-mounts.nix`'s `multimedia` gid must stay in sync with
  `modules/services/jellyfin.nix`'s group — an NFS `sec=sys` cross-host
  coupling that isn't enforced by Nix itself. If one side's gid
  changes, the other needs updating too.

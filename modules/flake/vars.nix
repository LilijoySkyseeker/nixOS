{ ... }:
{
  flake.vars = {
    # root access ssh keys
    publicSshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFA+HAQkhmPxKyJFSopziqIVNvFqEaqyRWPVvgu+urfh lilijoy@nixos-thinkpad" # thinkpad
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIPlHQiJlsDCcOWk/EadTOgm8mnkGpsg1y8gzvhUgsg7rAAAABHNzaDo= lilijoy@yubikey" # yubikey
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII6pG0Y9QdCBRJZKpCD62U3uXl5Lz/bE0ifWLbhZ4q9o lilijoy@torrent" # torrent
    ];
    # Public half of homelab's zrepl pull key (private half is the
    # homelab_zrepl_key sops secret). Both source hosts pin this same key
    # to a forced `zrepl stdinserver` command in root's authorized_keys, so
    # it lives here rather than being repeated per host.
    #
    # REPLACE-ME: placeholder. Generate the keypair on homelab, add the
    # private half to secrets.yaml as homelab_zrepl_key, and paste the
    # public half here before deploying torrent or thinkpad.
    zreplPullerKey = "ssh-ed25519 AAAAREPLACEMEREPLACEMEREPLACEMEREPLACEMEREPLACEME homelab-zrepl-pull";
    username = "lilijoy";
    # public domain fronted by hosts/vps (jellyfin, minecraft, factorio
    # subdomains — see services/octodns.nix and hosts/vps/configuration.nix)
    domain = "skyseekerlabs.net.";
    # shared numeric IDs that must stay consistent across files
    # (services/jellyfin.nix, modules/nixos/nfs-homelab-mounts.nix, profiles/PC.nix)
    gids = {
      multimedia = 999;
      flatpak = 998;
    };
    # impermanence persistence root shared by profiles/default.nix and the
    # homelab services that append their own state dirs to it
    persistRoot = "/nix/state";
  };
}

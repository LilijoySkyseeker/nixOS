# Single-disk cloud VM layout. No ZFS — one virtual disk with no
# redundancy to leverage gets nothing from ZFS beyond overhead. Root is
# tmpfs (wiped every boot); /nix and /persist are the only durable
# partitions. Adjust the device path to match the provider's virtual
# disk (DigitalOcean/most KVM providers expose /dev/vda).
#
# No disk-backed swap partition — see zramSwap in configuration.nix.
# sops decrypts several live secrets (WireGuard key, CrowdSec bouncer
# key, Caddy env, Tailscale authkey) into /run under memory pressure;
# a disk swap partition could let that material page out to
# persistent, unencrypted storage. zram compresses into RAM instead
# and never touches disk.
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/vda";
        content = {
          type = "gpt";
          partitions = {
            # DigitalOcean droplets are BIOS-only, no UEFI support at all
            # (confirmed via DO docs/community forum) — GRUB in legacy
            # mode needs this small unformatted partition to embed its
            # core.img into on a GPT disk (blocklist-embedding straight
            # into the disk is unreliable/discouraged). No mountpoint;
            # GRUB writes to it directly.
            grub = {
              size = "1M";
              type = "EF02";
            };
            boot = {
              size = "512M";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
              };
            };
            nix = {
              size = "18G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/nix";
              };
            };
            persist = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/persist";
                # nothing under /persist (caddy certs, crowdsec state,
                # tailscale state, logs, /etc/nixos checkout) needs to be
                # executed directly — everything actually run comes from
                # /nix/store, which is a separate partition and stays
                # exec-enabled below.
                mountOptions = [
                  "defaults"
                  "noexec"
                  "nosuid"
                  "nodev"
                ];
              };
            };
          };
        };
      };
    };
  };
}

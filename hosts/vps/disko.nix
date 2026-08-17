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
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            nix = {
              size = "12G";
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

# Single-disk cloud VM layout. No ZFS — one virtual disk with no
# redundancy to leverage gets nothing from ZFS beyond overhead. Root is
# tmpfs (wiped every boot); /nix and /persist are the only durable
# partitions. Adjust the device path to match the provider's virtual
# disk (Vultr/most KVM providers expose /dev/vda).
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
            swap = {
              size = "2G";
              content = {
                type = "swap";
              };
            };
            nix = {
              size = "50%";
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
              };
            };
          };
        };
      };
    };
  };
}

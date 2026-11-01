{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/vda";
        content = {
          type = "gpt";
          partitions = {
            # DigitalOcean droplets are BIOS-only, no UEFI support
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

# VM test: modules/nixos/hibernate.nix on thinkpad's encrypted layout
# GPT (ESP + LUKS2) -> LVM (swap, zfs) -> zpool, root on ZFS, systemd initrd,
# systemd-boot. hibernate, resume, then hibernate again with the bootloader
# pointing at a generation on a newer kernel and resume through that
# the target system is installed onto the disk with nixos-install, like
# nixpkgs' installer tests: the store lives on the pool, not a 9p/virtiofs
# share, which hibernation doesn't survive
#
# Writing or debugging one of these: .claude/skills/verify-a-change/vm-testing.md.
{
  pkgs,
  hibernateModule,
}:
let
  inherit (pkgs) lib;

  passphrase = "supersecret";
  hostId = "8425e349";

  # what gets installed onto the disk
  targetModule =
    { modulesPath, ... }:
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        # the driver's backdoor shell, in an installed system
        (modulesPath + "/testing/test-instrumentation.nix")
        hibernateModule
      ];

      system.stateVersion = "26.11";
      documentation.enable = false;
      networking.hostId = hostId;

      boot.loader.systemd-boot.enable = true;
      boot.loader.timeout = 1;

      boot.initrd.systemd.enable = true;
      boot.initrd.services.lvm.enable = true;
      boot.initrd.luks.devices.cryptroot.device = "/dev/disk/by-partlabel/cryptroot";

      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.forceImportRoot = false;

      fileSystems."/" = {
        device = "zroot/root";
        fsType = "zfs";
      };
      fileSystems."/boot" = {
        device = "/dev/disk/by-partlabel/ESP";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };
      swapDevices = [ { device = "/dev/mapper/vg-swap"; } ];

      myHibernate = {
        enable = true;
        resumeDevice = "/dev/mapper/vg-swap";
      };

      # the driver's shell is on hvc0; hand it back over on resume (nixpkgs' hibernate.nix)
      powerManagement.powerDownCommands = "systemctl --no-block stop backdoor.service";
      powerManagement.resumeCommands = "systemctl --no-block restart backdoor.service";
    };

  # generation 2: the same system on a newer kernel, as after an update
  newKernelSystem = pkgs.nixos [
    targetModule
    { boot.kernelPackages = pkgs.linuxPackages_latest; }
  ];

  # generation 1, carrying generation 2 so the target's own nix can --set it
  targetSystem = pkgs.nixos [
    targetModule
    { system.extraDependencies = [ newKernelSystem.toplevel ]; }
  ];

  # outside the node: `pkgs.path` in a node's imports recurses
  autoFormatRootDevice = pkgs.path + "/nixos/tests/common/auto-format-root-device.nix";

  oldKernel = targetSystem.config.boot.kernelPackages.kernel.version;
  newKernel = newKernelSystem.config.boot.kernelPackages.kernel.version;

  # qemu side shared by both nodes: they are one machine booted two ways
  commonConfig = {
    virtualisation.diskImage = "./target.qcow2";
    virtualisation.diskSize = 10 * 1024;
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
  };
in
assert lib.versionOlder oldKernel newKernel;
pkgs.testers.runNixOSTest {
  name = "hibernate-zfs-luks";

  nodes.installer =
    { pkgs, ... }:
    {
      imports = [
        commonConfig
        autoFormatRootDevice
      ];
      # own root on the small vdb so the target disk is vda in both boots
      virtualisation.emptyDiskImages = [ 2048 ];
      virtualisation.rootDevice = "/dev/vdb";
      virtualisation.fileSystems."/".autoFormat = true;

      nix.enable = true;
      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.forceImportRoot = false;
      networking.hostId = hostId;
      environment.systemPackages = with pkgs; [
        cryptsetup
        dosfstools
        gptfdisk
        lvm2
      ];
      virtualisation.additionalPaths = [ targetSystem.toplevel ];
    };

  nodes.target = {
    imports = [ commonConfig ];
    virtualisation.useBootLoader = true;
    virtualisation.useEFIBoot = true;
    virtualisation.useDefaultFilesystems = false;
    virtualisation.efi.keepVariables = false;
    # no 9p/virtiofs devices: the installed system doesn't use them
    virtualisation.sharedDirectories = lib.mkForce { };
    # never mounted: the installed system's own fileSystems boot
    virtualisation.fileSystems."/" = {
      device = "/dev/disk/by-label/this-is-not-real-and-will-never-be-used";
      fsType = "ext4";
    };
  };

  testScript = ''
    import re
    import time

    def unlock(delay=0):
        target.wait_for_console_text("Please enter passphrase for disk cryptroot")
        if delay:
            # host-side: machine.sleep() runs in the guest, which has no shell yet
            time.sleep(delay)
        target.send_console("${passphrase}\n")

    def boot_id():
        return target.succeed("cat /proc/sys/kernel/random/boot_id").strip()

    def check_pool(sha):
        out = target.succeed("zpool status -x").strip()
        assert out == "all pools are healthy", out
        target.succeed("zpool scrub -w zroot")
        status = target.succeed("zpool status -v zroot")
        print(status)
        assert "errors: No known data errors" in status, status
        assert re.search(r"scrub repaired 0B .* with 0 errors", status), status
        assert target.succeed("sha256sum /data.bin").split()[0] == sha

    def hibernate():
        target.execute("systemctl hibernate >&2 &", check_return=False)
        target.wait_for_shutdown()

    def resume_and_check(bid, marker, sha):
        target.succeed("true")  # reconnects to the resumed backdoor
        assert boot_id() == bid, "booted fresh instead of resuming"
        assert target.succeed("cat /run/test/marker").strip() == marker
        print(target.succeed("dmesg | grep -iE 'PM: (hibernation|image|restor|resume)' || true"))
        check_pool(sha)

    with subtest("install: GPT (ESP + LUKS2) -> LVM (swap, zfs) -> zpool"):
        installer.wait_for_unit("multi-user.target")
        installer.succeed(
            "sgdisk -Z /dev/vda",
            "sgdisk -n1:1M:+512M -t1:EF00 -c1:ESP -n2:0:0 -t2:8309 -c2:cryptroot /dev/vda",
            "udevadm settle",
            "mkfs.vfat -F32 /dev/disk/by-partlabel/ESP",
            "echo -n ${passphrase} | cryptsetup luksFormat --type luks2 -q --iter-time=1 /dev/disk/by-partlabel/cryptroot -",
            "echo -n ${passphrase} | cryptsetup open /dev/disk/by-partlabel/cryptroot cryptroot -",
            "pvcreate /dev/mapper/cryptroot",
            "vgcreate vg /dev/mapper/cryptroot",
            "lvcreate -L 3G -n swap vg",
            "lvcreate -l 100%FREE -n zfs vg",
            "mkswap /dev/mapper/vg-swap",
            "zpool create -o ashift=12 -O mountpoint=none -O acltype=posixacl -O xattr=sa zroot /dev/mapper/vg-zfs",
            "zfs create -o mountpoint=legacy zroot/root",
            "mkdir -p /mnt",
            "mount -t zfs zroot/root /mnt",
            "mkdir /mnt/boot",
            "mount -o umask=0077 /dev/disk/by-partlabel/ESP /mnt/boot",
        )
        installer.succeed(
            "nixos-install --system ${targetSystem.toplevel} --root /mnt --no-root-passwd --no-channel-copy >&2"
        )
        installer.succeed(
            "umount -R /mnt",
            "zpool export zroot",
            "vgchange -an vg",
            "cryptsetup close cryptroot",
            "sync",
        )
        installer.shutdown()

    # same disk image, booted through OVMF + systemd-boot this time
    target.state_dir = installer.state_dir

    with subtest("cold boot: unlock late, root on ZFS"):
        target.start()
        # longer than zfs-import's 60s device-wait loop
        unlock(delay=75)
        target.wait_for_unit("multi-user.target")
        assert target.succeed("findmnt -no SOURCE,FSTYPE /").split() == ["zroot/root", "zfs"]
        print(target.succeed("lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS"))
        cmdline = target.succeed("cat /proc/cmdline")
        assert "resume=/dev/mapper/vg-swap" in cmdline, cmdline
        assert "nohibernate" not in cmdline, cmdline
        target.succeed("swapon --show=NAME --noheadings | grep -q dm-")
        assert target.succeed("uname -r").strip() == "${oldKernel}"

    with subtest("initrd ran zfs-import-zroot only after systemd-hibernate-resume"):
        # systemd logs unit descriptions, not names
        journal = target.succeed(
            "journalctl -b -o short-monotonic --no-pager "
            "| grep -E 'Finished Resume from hibernation|Starting Import ZFS pool|Finished Cryptography Setup for cryptroot'"
        )
        print(journal)

        def first(text):
            line = next(l for l in journal.splitlines() if text in l)
            return float(line.split("]")[0].strip("[ "))

        unlocked = first("Finished Cryptography Setup for cryptroot")
        resumed = first("Finished Resume from hibernation")
        importing = first("Starting Import ZFS pool")
        assert unlocked <= resumed <= importing, (unlocked, resumed, importing)

    with subtest("hibernate and resume on the same kernel"):
        target.succeed("dd if=/dev/urandom of=/data.bin bs=1M count=64 status=none", "sync")
        sha = target.succeed("sha256sum /data.bin").split()[0]
        target.succeed(
            "mkdir /run/test",
            "mount -t ramfs ramfs /run/test",
            "head -c16 /dev/urandom | od -An -tx1 | tr -d ' \\n' > /run/test/marker",
        )
        marker = target.succeed("cat /run/test/marker").strip()
        bid = boot_id()
        hibernate()
        target.start()
        unlock()
        resume_and_check(bid, marker, sha)
        assert target.succeed("uname -r").strip() == "${oldKernel}"

    with subtest("hibernate with generation 2 (newer kernel) as the boot default"):
        target.succeed(
            "nix-env -p /nix/var/nix/profiles/system --set ${newKernelSystem.toplevel}",
            "/nix/var/nix/profiles/system/bin/switch-to-configuration boot",
        )
        entry = target.succeed("sed -n 's/^default //p' /boot/loader/loader.conf").strip()
        entry_text = target.succeed(f"cat /boot/loader/entries/{entry}")
        print(entry_text)
        assert "Generation 2" in entry_text and "${newKernel}" in entry_text, entry_text
        target.succeed("echo changed > /run/test/marker2")
        bid = boot_id()
        hibernate()
        target.start()
        # generation 2's kernel is the one systemd-boot started
        target.wait_for_console_text("Linux version ${newKernel}")
        unlock()
        resume_and_check(bid, marker, sha)
        # and it handed over to the hibernated older kernel
        assert target.succeed("uname -r").strip() == "${oldKernel}"
        assert target.succeed("cat /run/test/marker2").strip() == "changed"

    with subtest("a cold boot afterwards runs generation 2 and imports the pool cleanly"):
        target.shutdown()
        target.start()
        unlock()
        target.wait_for_unit("multi-user.target")
        assert target.succeed("uname -r").strip() == "${newKernel}"
        target.fail("test -e /run/test/marker")
        check_pool(sha)
  '';
}

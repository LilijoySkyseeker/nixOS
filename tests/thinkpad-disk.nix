# VM test: thinkpad's encrypted root disk, end to end, with the real modules
# disko formats vars.mkEncryptedRootSsd (ESP + LUKS2 `crypt` -> LVM swap +
# zroot) plus a zpool like hosts/thinkpad/disko.nix; the installed system runs
# myEncryptedRoot, myHibernate and myHibernateOnly on systemd-boot with a TPM.
# First boot unlocks with the passphrase, then TPM2 + PIN is enrolled with the
# README's command and every later boot and resume types only the PIN; PCR 15
# then blocks a second unseal. Hibernate and resume, then hibernate with a
# newer kernel as the boot default (it resumes, or boots fresh with the pool
# intact), then wrong PINs fall back to the passphrase
# the store lives on the pool, not a 9p/virtiofs share, which hibernation
# doesn't survive
#
# Writing or debugging one of these: .claude/skills/verify-a-change/vm-testing.md.
{
  pkgs,
  vars,
  diskoModule,
  encryptedRootModule,
  hibernateModule,
  hibernateOnlyModule,
}:
let
  inherit (pkgs) lib;

  # what disko's askPassword prompt sets when IN_DISKO_TEST is set
  passphrase = "disko";
  pin = "246810";
  hostId = "8425e349";
  # hosts/thinkpad/README.md's enrollment
  luksDevice = "/dev/disk/by-partlabel/disk-root-luks";
  pcrs = "7+15:sha256=${lib.strings.replicate 64 "0"}";

  # qemu gives the target disk serial `root`
  diskoDevices = vars.mkEncryptedRootSsd "virtio-root" "3G" // {
    zpool.zroot = {
      type = "zpool";
      mode = "";
      rootFsOptions = vars.zfsRootFsOptions;
      options.ashift = "13";
      datasets = {
        "local" = {
          type = "zfs_fs";
          options.mountpoint = "none";
        };
        "local/nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
        };
        "local/root" = {
          type = "zfs_fs";
          mountpoint = "/";
        };
        "local/home" = {
          type = "zfs_fs";
          mountpoint = "/home";
        };
      };
    };
  };

  # what gets installed onto the disk
  targetModule =
    { lib, modulesPath, ... }:
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        # the driver's backdoor shell, in an installed system
        (modulesPath + "/testing/test-instrumentation.nix")
        diskoModule
        encryptedRootModule
        hibernateModule
        hibernateOnlyModule
      ];

      # myHibernateOnly's KDE half (home-manager + plasma-manager) isn't built here
      options.home-manager.users = lib.mkOption {
        type = lib.types.attrsOf lib.types.raw;
        default = { };
      };

      config = {
        _module.args.vars = vars;

        system.stateVersion = "26.11";
        documentation.enable = false;
        networking.hostId = hostId;

        disko.devices = diskoDevices;

        boot.loader.systemd-boot.enable = true;
        boot.loader.timeout = 1;
        # stands in for lanzaboote's stub, whose StubPcrKernelImage EFI variable
        # is what lets systemd-cryptsetup measure into PCR 15 at all
        boot.kernelParams = [ "systemd.tpm2_measured_os=1" ];
        boot.supportedFilesystems = [ "zfs" ];
        fileSystems."/nix".neededForBoot = true;

        myEncryptedRoot.enable = true;
        myHibernate = {
          enable = true;
          resumeDevice = "/dev/mapper/vg-swap";
        };
        myHibernateOnly.enable = true;

        # the driver's shell is on hvc0; hand it back over on resume (nixpkgs' hibernate.nix)
        powerManagement.powerDownCommands = "systemctl --no-block stop backdoor.service";
        powerManagement.resumeCommands = "systemctl --no-block restart backdoor.service";
      };
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
    virtualisation.diskSize = 12 * 1024;
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
  };
in
assert lib.versionOlder oldKernel newKernel;
pkgs.testers.runNixOSTest {
  name = "thinkpad-disk";

  nodes.installer =
    { config, pkgs, ... }:
    {
      imports = [
        commonConfig
        autoFormatRootDevice
        diskoModule
      ];
      # own root on the small vdb so the target disk is vda in both boots
      virtualisation.emptyDiskImages = [ 2048 ];
      virtualisation.rootDevice = "/dev/vdb";
      virtualisation.fileSystems."/".autoFormat = true;

      disko.enableConfig = false;
      disko.devices = diskoDevices;

      nix.enable = true;
      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.forceImportRoot = false;
      networking.hostId = hostId;
      environment.systemPackages = [
        pkgs.cryptsetup
        config.system.build.destroyFormatMount
        config.system.build.unmount
      ];
      virtualisation.additionalPaths = [ targetSystem.toplevel ];
    };

  nodes.target = {
    imports = [ commonConfig ];
    virtualisation.useBootLoader = true;
    virtualisation.useEFIBoot = true;
    virtualisation.useDefaultFilesystems = false;
    virtualisation.efi.keepVariables = false;
    virtualisation.tpm.enable = true;
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

    # kernel and initrd log lines land in the middle of a prompt on the serial
    # console, so a prompt's characters may have whole log lines between them
    def spread(text):
        return r"(?:\[\s*\d+\.\d+\][^\n]*\n)*".join(re.escape(c) for c in text)

    prompt_re = re.compile(f"(?P<pin>{spread('Please enter TPM2 PIN')})|{spread('Please enter passphrase for disk')}")

    def prompt():
        """wait for this boot's first unlock prompt, return which one it is"""
        deadline = time.monotonic() + 600
        while True:
            seen = prompt_re.search(target.get_console_log() + "\n")
            if seen:
                return "pin" if seen["pin"] else "passphrase"
            assert time.monotonic() < deadline, "no unlock prompt"
            time.sleep(0.5)

    def unlock(expect, secret, delay=0):
        got = prompt()
        assert got == expect, f"initrd asked for the {got}, expected the {expect}"
        if delay:
            # host-side: machine.sleep() runs in the guest, which has no shell yet
            time.sleep(delay)
        target.send_console(secret + "\n")

    def boot_id():
        return target.succeed("cat /proc/sys/kernel/random/boot_id").strip()

    def pcr15():
        out = target.succeed("systemd-analyze pcrs 15 --no-pager")
        print(out)
        return out.split()[-1].lower()

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

    with subtest("install: disko formats vars.mkEncryptedRootSsd + zroot"):
        installer.wait_for_unit("multi-user.target")
        installer.succeed("IN_DISKO_TEST=1 disko-destroy-format-mount --yes-wipe-all-disks >&2")
        print(installer.succeed("lsblk -o NAME,TYPE,FSTYPE,PARTLABEL,SIZE,MOUNTPOINTS"))
        dump = installer.succeed("cryptsetup luksDump ${luksDevice}")
        print(dump)
        assert re.search(r"^Version:\s+2$", dump, re.M), dump
        assert re.search(r"^Flags:\s+allow-discards", dump, re.M), dump
        assert installer.succeed("findmnt -no SOURCE /mnt").strip() == "zroot/local/root"
        assert installer.succeed("findmnt -no SOURCE /mnt/nix").strip() == "zroot/local/nix"
        assert installer.succeed("findmnt -no FSTYPE /mnt/boot").strip() == "vfat"
        installer.succeed(
            "nixos-install --system ${targetSystem.toplevel} --root /mnt --no-root-passwd --no-channel-copy >&2"
        )
        installer.succeed("disko-unmount >&2", "sync")
        installer.fail("zpool list zroot", "cryptsetup status crypt")
        installer.shutdown()

    # same disk image, booted through OVMF + systemd-boot this time
    target.state_dir = installer.state_dir

    with subtest("first boot: nothing enrolled, the passphrase unlocks"):
        target.start()
        unlock("passphrase", "${passphrase}")
        target.wait_for_unit("multi-user.target")
        assert target.succeed("findmnt -no SOURCE,FSTYPE /").split() == ["zroot/local/root", "zfs"]
        assert target.succeed("findmnt -no SOURCE /nix").strip() == "zroot/local/nix"
        print(target.succeed("lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS"))
        cmdline = target.succeed("cat /proc/cmdline")
        assert "resume=/dev/mapper/vg-swap" in cmdline, cmdline
        assert "nohibernate" not in cmdline, cmdline
        target.succeed("swapon --show=NAME --noheadings | grep -q dm-")
        assert target.succeed("uname -r").strip() == "${oldKernel}"

    with subtest("myHibernateOnly: logind offers hibernate, not sleep; the lid hibernates"):
        manager = "org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager"

        def login1(call, expect):
            got = target.succeed(f"busctl {call}").split()[-1].strip('"')
            assert got == expect, f"{call}: {got}, expected {expect}"

        # "no": disabled in sleep.conf, rather than "na", unsupported
        login1(f"call {manager} CanSuspend", "no")
        login1(f"call {manager} CanHybridSleep", "no")
        login1(f"call {manager} CanSuspendThenHibernate", "no")
        login1(f"call {manager} CanHibernate", "yes")
        for prop in ["HandleLidSwitch", "HandleLidSwitchExternalPower", "HandleLidSwitchDocked", "HandleSuspendKey"]:
            login1(f"get-property {manager} {prop}", "hibernate")

    with subtest("enroll TPM2 + PIN with the README's command"):
        target.succeed(
            "PASSWORD=${passphrase} NEWPIN=${pin} systemd-cryptenroll"
            " --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=${pcrs} ${luksDevice} >&2"
        )
        slots = target.succeed("systemd-cryptenroll ${luksDevice}")
        print(slots)
        assert re.search(r"\bpassword\b", slots) and re.search(r"\btpm2\b", slots), slots

    with subtest("cold boot: only the PIN, typed late; the TPM unseals"):
        target.shutdown()
        target.start()
        # longer than zfs-import's 60s device-wait loop
        unlock("pin", "${pin}", delay=75)
        target.wait_for_unit("multi-user.target")
        prompts = ["pin" if m["pin"] else "passphrase" for m in prompt_re.finditer(target.get_console_log())]
        assert prompts == ["pin"], prompts
        journal = target.succeed("journalctl -b -o short-monotonic --no-pager")
        cryptsetup_lines = [l for l in journal.splitlines() if "systemd-cryptsetup" in l]
        print("\n".join(cryptsetup_lines))
        assert any("Successfully extended PCR index 15" in l for l in cryptsetup_lines), cryptsetup_lines
        assert target.succeed("findmnt -no SOURCE /").strip() == "zroot/local/root"

    with subtest("initrd ran zfs-import-zroot only after systemd-hibernate-resume"):
        # systemd logs unit descriptions, not names
        order = [
            l
            for l in journal.splitlines()
            if re.search(r"Finished Resume from hibernation|Starting Import ZFS pool|Finished Cryptography Setup for crypt\b", l)
        ]
        print("\n".join(order))

        def first(text):
            line = next(l for l in order if text in l)
            return float(line.split("]")[0].strip("[ "))

        unlocked = first("Finished Cryptography Setup for crypt")
        resumed = first("Finished Resume from hibernation")
        importing = first("Starting Import ZFS pool")
        assert unlocked <= resumed <= importing, (unlocked, resumed, importing)

    with subtest("PCR 15 guard: once crypt is open the TPM won't unseal again"):
        value = pcr15()
        assert re.fullmatch(r"[0-9a-f]{64}", value) and value != "0" * 64, value
        # what the initrd ran, with the right PIN, against the same token
        rc, out = target.execute(
            "SYSTEMD_LOG_LEVEL=debug PIN=${pin} systemd-cryptsetup attach probe ${luksDevice} -"
            " tpm2-device=auto,tpm2-measure-pcr=yes,headless=yes 2>&1"
        )
        print(out)
        assert rc != 0, out
        assert "Current policy digest does not match stored policy digest" in out, out
        target.fail("test -e /dev/mapper/probe")

    with subtest("hibernate and resume on the same kernel, PIN only"):
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
        unlock("pin", "${pin}")
        resume_and_check(bid, marker, sha)
        assert target.succeed("uname -r").strip() == "${oldKernel}"

    with subtest("hibernate with generation 2 (newer kernel) as the boot default: resumes, or boots fresh with the pool intact"):
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
        unlock("pin", "${pin}")
        target.succeed("true")  # reconnects to the resumed or freshly booted backdoor
        if boot_id() == bid:
            print("resumed through the newer kernel")
            resume_and_check(bid, marker, sha)
            # and it handed over to the hibernated older kernel
            assert target.succeed("uname -r").strip() == "${oldKernel}"
            assert target.succeed("cat /run/test/marker2").strip() == "changed"
        else:
            # with a TPM, OVMF's e820 map differs between the two kernels and
            # the newer one refuses the image ("inconsistent memory map")
            kmsg = target.succeed("journalctl -k -b --no-pager | grep -E 'hibernation|memory map' || true")
            print("booted fresh instead of resuming:\n" + kmsg)
            assert "Failed to load image" in kmsg, kmsg
            target.wait_for_unit("multi-user.target")
            assert target.succeed("uname -r").strip() == "${newKernel}"
            target.fail("test -e /run/test/marker")
            check_pool(sha)

    with subtest("wrong PINs fall back to the passphrase; generation 2 cold boots"):
        target.shutdown()
        target.start()
        # systemd-cryptsetup re-asks a bad PIN up to 5 times, fewer once the TPM's
        # dictionary-attack lockout starts, then falls back to the passphrase
        # their log lines come before the next prompt, whose own line may stay
        # unterminated on the console
        bad_pin_re = re.compile(spread("Bad PIN."))
        fallback_re = re.compile(spread("falling back to traditional unlocking"))

        def after_wrong_pin(wrong):
            deadline = time.monotonic() + 600
            while True:
                console = target.get_console_log() + "\n"
                if fallback_re.search(console):
                    return "passphrase"
                if wrong < 5 and len(bad_pin_re.findall(console)) >= wrong:
                    return "pin"
                assert time.monotonic() < deadline, "neither a PIN prompt nor the fallback"
                time.sleep(0.5)

        assert prompt() == "pin"
        wrong = 0
        while True:
            target.send_console("000000\n")
            wrong += 1
            if after_wrong_pin(wrong) == "passphrase":
                break
            time.sleep(2)
        lockout = "dictionary attack lock-out" in target.get_console_log()
        print(f"passphrase asked for after {wrong} wrong PINs (TPM lockout: {lockout})")
        time.sleep(2)
        target.send_console("${passphrase}\n")
        target.wait_for_unit("multi-user.target")
        assert target.succeed("uname -r").strip() == "${newKernel}"
        target.fail("test -e /run/test/marker")
        check_pool(sha)
  '';
}

# VM test: thinkpad's encrypted root disk, end to end, with the real modules
# disko formats vars.mkEncryptedRootSsd (ESP + LUKS2 `crypt` -> LVM swap +
# zroot) plus a zpool like hosts/thinkpad/disko.nix; the installed system runs
# myEncryptedRoot, myHibernate and myHibernateOnly on systemd-boot with a TPM.
# First boot unlocks with the passphrase, then TPM2 + PIN is enrolled with the
# README's command and every later boot and resume types only the PIN, which
# systemd-cryptsetup's token discovery asks for. Hibernate and resume, then hibernate with a
# newer kernel as the boot default (myHibernate's one-shot entry resumes it
# through the kernel that hibernated), then wrong PINs fall back to the
# passphrase and the newer kernel cold boots
# the store lives on the pool, not a 9p/virtiofs share, which hibernation
# doesn't survive
#
# Writing or debugging one of these: .agents/skills/verify-a-change/vm-testing.md.
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
  pcrs = "7";

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
        boot.supportedFilesystems = [ "zfs" ];
        fileSystems."/nix".neededForBoot = true;

        myEncryptedRoot.enable = true;
        myHibernate = {
          enable = true;
          resumeDevice = "/dev/mapper/vg-swap";
        };
        myHibernateOnly.enable = true;

        # power off after writing the image instead of ACPI S4, which OVMF with
        # a TPM sometimes never completes (test VM only)
        systemd.sleep.settings.Sleep.HibernateMode = "shutdown";

        # the driver's shell is on hvc0; hand it back over on resume (nixpkgs' hibernate.nix)
        powerManagement.powerDownCommands = "systemctl --no-block stop backdoor.service";
        powerManagement.resumeCommands = "systemctl --no-block restart backdoor.service";
      };
    };

  # generation 2: the same system on a newer kernel, as after an update
  newKernelSystem = pkgs.nixos [
    targetModule
    # newest kernel zfs supports; TODO: drop when zfs supports linuxPackages_latest (7.3) again
    { boot.kernelPackages = pkgs.linuxPackages_7_2; }
  ];

  # generation 1, carrying generation 2 so the target's own nix can --set it
  targetSystem = pkgs.nixos [
    targetModule
    { system.extraDependencies = [ newKernelSystem.toplevel ]; }
  ];

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
    from datetime import timedelta

    # kernel and initrd log lines land in the middle of a prompt on the serial
    # console, so a prompt's characters may have whole log lines between them
    def spread(text):
        return r"(?:\[\s*\d+\.\d+\][^\n]*\n)*".join(re.escape(c) for c in text)

    prompt_re = re.compile(f"(?P<pin>{spread('Please enter LUKS2 token PIN')})|{spread('Please enter passphrase for disk')}")

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

    def hibernate_until_resumed(kernel, sha, tries=6):
        """hibernate until a resume works; return the attempt it took

        with a TPM, the kernel's EFI stub keeps its copy of the TPM event log
        in an e820 "ACPI data" region, and OVMF places it differently from
        boot to boot, so the resuming kernel can refuse the image ("Hibernate
        inconsistent memory map detected!") and boot fresh. That is this VM's
        firmware, not the system under test; any other reason fails the test.
        """
        for attempt in range(1, tries + 1):
            target.succeed(
                "mkdir -p /run/test",
                "mountpoint -q /run/test || mount -t ramfs ramfs /run/test",
                "head -c16 /dev/urandom | od -An -tx1 | tr -d ' \\n' > /run/test/marker",
            )
            marker = target.succeed("cat /run/test/marker").strip()
            bid = boot_id()
            hibernate()
            target.start()
            target.wait_for_console_text(f"Linux version {kernel}", timeout=timedelta(minutes=10))
            unlock("pin", "${pin}")
            target.succeed("true")  # reconnects to the resumed or freshly booted backdoor
            if boot_id() == bid:
                resume_and_check(bid, marker, sha)
                print(f"resumed on attempt {attempt}")
                return attempt
            kmsg = target.succeed("journalctl -k -b --no-pager | grep -E 'memory map|Image mismatch|Failed to load image' || true")
            assert "inconsistent memory map" in kmsg, "booted fresh, not for the VM's moving e820 region:\n" + kmsg
            print(f"attempt {attempt}: the e820 map moved under OVMF, hibernating again")
            target.wait_for_unit("multi-user.target")
        raise AssertionError(f"no resume in {tries} attempts")

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

    with subtest("hibernate and resume on the same kernel, PIN only"):
        target.succeed("dd if=/dev/urandom of=/data.bin bs=1M count=64 status=none", "sync")
        sha = target.succeed("sha256sum /data.bin").split()[0]
        hibernate_until_resumed("${oldKernel}", sha)
        assert target.succeed("uname -r").strip() == "${oldKernel}"

    with subtest("hibernate with generation 2 (newer kernel) as the boot default: resumes through the entry that hibernated"):
        target.succeed(
            "nix-env -p /nix/var/nix/profiles/system --set ${newKernelSystem.toplevel}",
            "/nix/var/nix/profiles/system/bin/switch-to-configuration boot",
        )
        entry = target.succeed("sed -n 's/^default //p' /boot/loader/loader.conf").strip()
        entry_text = target.succeed(f"cat /boot/loader/entries/{entry}")
        print(entry_text)
        assert "Generation 2" in entry_text and "${newKernel}" in entry_text, entry_text

        loader_guid = "4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"

        def efi_string(name):
            # EFI variable file: 4 attribute bytes, then UTF-16LE (ASCII ids: drop the NULs)
            return target.succeed(
                f"tail -c +5 /sys/firmware/efi/efivars/{name}-{loader_guid} | tr -d '\\0'"
            ).strip()

        # hibernate-prepare's one-shot is the entry that boots the running
        # system, under its current file name: installing generation 2 renamed
        # generation 1's entry, so the ID this boot came from (LoaderEntrySelected)
        # is gone. The one-shot outlives a restart and systemd-boot boots it
        target.succeed("systemctl start hibernate-prepare.service")
        selected = efi_string("LoaderEntrySelected")
        oneshot = efi_string("LoaderEntryOneShot")
        print(f"selected={selected} oneshot={oneshot}")
        assert oneshot != entry, (oneshot, entry)
        target.succeed(
            f"test -f /boot/loader/entries/{oneshot}",
            f"grep -q \"init=$(readlink -f /run/booted-system)/init\" /boot/loader/entries/{oneshot}",
        )
        target.shutdown()
        target.start()
        unlock("pin", "${pin}")
        target.wait_for_unit("multi-user.target")
        booted = target.succeed("uname -r").strip()
        print(target.succeed("bootctl status --no-pager 2>&1 | sed -n '/Current Boot Loader/,/^$/p;/Boot Loader Entries/,/^$/p' || true"))
        print("LoaderEntrySelected now: " + efi_string("LoaderEntrySelected"))
        rc, _ = target.execute(f"test -e /sys/firmware/efi/efivars/LoaderEntryOneShot-{loader_guid}")
        print(f"after restart: booted {booted}, one-shot variable {'still set' if rc == 0 else 'gone'}")
        assert booted == "${oldKernel}", f"the one-shot entry wasn't booted (kernel {booted})"
        assert rc != 0, "the one-shot variable is still set"

        # hibernate-prepare makes the running entry (generation 1) the
        # one-shot, so every attempt boots the kernel that hibernated
        hibernate_until_resumed("${oldKernel}", sha)
        assert target.succeed("uname -r").strip() == "${oldKernel}"
        # consumed: the next restart takes generation 2 (the next subtest boots it)
        target.fail(f"test -e /sys/firmware/efi/efivars/LoaderEntryOneShot-{loader_guid}")

    with subtest("wrong PINs fall back to the passphrase; generation 2 cold boots"):
        target.shutdown()
        target.start()
        # token discovery re-asks a wrong PIN; once the TPM's dictionary-attack
        # lockout starts, the token fails outright and the passphrase is asked
        # for. The newest prompt's own line may stay unterminated on the console
        pin_re = re.compile(spread("Please enter LUKS2 token PIN"))
        # the passphrase prompt's line may stay unterminated, so its query's log
        # line after the lockout counts too
        passphrase_re = re.compile(
            f"{spread('Please enter passphrase for disk')}|{spread('dictionary attack lock-out mode.')}"
        )

        def after_wrong_pin(asked):
            deadline = time.monotonic() + 600
            while True:
                console = target.get_console_log() + "\n"
                if passphrase_re.search(console):
                    return "passphrase"
                if len(pin_re.findall(console)) > asked:
                    return "pin"
                assert time.monotonic() < deadline, "neither another PIN prompt nor the passphrase"
                time.sleep(0.5)

        assert prompt() == "pin"
        wrong = 0
        while True:
            target.send_console("000000\n")
            wrong += 1
            if after_wrong_pin(wrong) == "passphrase":
                break
            assert wrong < 12, "still asking for the PIN after 12 wrong ones"
            time.sleep(2)
        print(f"passphrase asked for after {wrong} wrong PINs")
        time.sleep(2)
        target.send_console("${passphrase}\n")
        target.wait_for_unit("multi-user.target")
        assert target.succeed("uname -r").strip() == "${newKernel}"
        target.fail("test -e /run/test/marker")
        check_pool(sha)
  '';
}

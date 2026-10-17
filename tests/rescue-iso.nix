# VM test: the rescue ISO's safety properties hold on a booted system
# internal disks really reject writes until `disk-rw`, a mount of one falls
# back to read-only, sshd is unreachable off the tailnet, and phone-paste
# takes exactly one submission behind its token, scopes its firewall rule
# to one interface and removes it after
{ pkgs, rescueIsoModule }:
pkgs.testers.runNixOSTest {
  name = "rescue-iso";

  nodes.client = _: {
    environment.systemPackages = [
      pkgs.curl
      pkgs.netcat
    ];
  };

  nodes.machine = _: {
    imports = [ rescueIsoModule ];
    _module.args.pkgs-unstable = pkgs;

    # the live ISO runs from RAM; a disk-backed root would itself go read-only
    virtualisation.diskImage = null;
    # with no root disk these are vda (a plain internal disk) and vdb (stands
    # in for the stick's TOOLBOX partition)
    virtualisation.emptyDiskImages = [
      64
      64
    ];

    # what the installer profile provides on the real ISO
    users.users.nixos.isNormalUser = true;
    services.openssh.enable = true;
    # phone-paste binds the default route's source address
    networking.defaultGateway = "192.168.1.254";
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sshd.service")
    client.wait_for_unit("multi-user.target")

    with subtest("internal disks start read-only and reject writes"):
        machine.succeed("udevadm settle")
        machine.succeed("test -b /dev/vda && test -b /dev/vdb")
        machine.succeed("test $(blockdev --getro /dev/vda) = 1")
        machine.fail("dd if=/dev/zero of=/dev/vda bs=4096 count=1 oflag=direct")

    with subtest("disk-rw lifts it for one disk"):
        machine.succeed("disk-rw /dev/vda")
        machine.succeed("test $(blockdev --getro /dev/vda) = 0")
        machine.succeed("test $(blockdev --getro /dev/vdb) = 1")
        machine.succeed("mkfs.ext4 -q /dev/vda")

    with subtest("a mount of a read-only disk falls back to read-only"):
        machine.succeed("blockdev --setro /dev/vda")
        machine.succeed("mkdir -p /mnt/t && mount /dev/vda /mnt/t")
        machine.succeed("findmnt -no OPTIONS /mnt/t | grep -qw ro")
        machine.fail("touch /mnt/t/x")
        machine.succeed("umount /mnt/t")

    with subtest("device-mapper volumes on internal disks start read-only"):
        machine.succeed("dmsetup create testlv --table '0 2048 linear /dev/vda 0' && udevadm settle")
        machine.succeed("test $(blockdev --getro /dev/mapper/testlv) = 1")
        machine.succeed("dmsetup remove testlv")

    with subtest("toolbox-mount uses Ventoy's VentoyPart mapping, read-only, --rw on request"):
        # the real stick is USB, hence writable; here vdb plays it
        machine.succeed("disk-rw /dev/vdb && mkfs.exfat -L TOOLBOX /dev/vdb")
        machine.succeed("dmsetup create VentoyPart --table \"0 $(blockdev --getsz /dev/vdb) linear /dev/vdb 0\" && udevadm settle")
        machine.succeed("test $(blockdev --getro /dev/mapper/VentoyPart) = 0")
        machine.succeed("toolbox-mount")
        machine.succeed("findmnt -no SOURCE,OPTIONS /run/toolbox | grep -w ro | grep -q VentoyPart")
        machine.succeed("toolbox-mount --rw && touch /run/toolbox/written")

    with subtest("agent instructions are in place for both CLIs"):
        machine.succeed("grep -q 'Rescue session' /home/nixos/.claude/CLAUDE.md")
        machine.succeed("grep -q 'Rescue session' /home/nixos/.codex/AGENTS.md")
        machine.succeed("test $(stat -c %U /home/nixos/.claude) = nixos")

    with subtest("sshd runs but is closed off the tailnet"):
        machine.succeed("nc -z 127.0.0.1 22")
        client.fail("nc -z -w 3 machine 22")

    with subtest("phone-paste: token-gated, one submission, port closed after"):
        client.fail("nc -z -w 3 machine 8765")
        machine.succeed("phone-paste >/tmp/paste.out 2>/tmp/paste.err &")
        machine.wait_until_succeeds("grep -q 'open: http' /tmp/paste.err")
        url = machine.succeed("grep -o 'http://[^ ]*' /tmp/paste.err").strip()
        base = url.rsplit("/", 1)[0]
        machine.succeed("iptables -S nixos-fw | grep -- '-i eth1 ' | grep -q 'rescue-fw:8765'")
        # an idle connection that never sends a request mustn't block others
        client.succeed("(sleep 60 | nc machine 8765 >/dev/null &)")
        client.succeed(f"test $(curl -s --max-time 10 -o /dev/null -w '%{{http_code}}' {base}/wrong) = 404")
        client.succeed(f"curl -sf {url} | grep -q '<form'")
        client.succeed(f"curl -sf --data-urlencode 'text=hello from the phone' {url}")
        machine.wait_until_succeeds("grep -qx 'hello from the phone' /tmp/paste.out")
        client.fail(f"curl -sf --max-time 3 --data-urlencode 'text=second' {url}")
        client.fail("nc -z -w 3 machine 8765")
        machine.wait_until_fails("iptables -S nixos-fw | grep -q rescue-fw")

    with subtest("phone-paste cleans up its firewall rule when killed"):
        machine.succeed("phone-paste >/dev/null 2>/tmp/paste2.err & echo $! >/tmp/paste2.pid")
        machine.wait_until_succeeds("iptables -S nixos-fw | grep -q rescue-fw:8765")
        machine.succeed("kill -TERM $(cat /tmp/paste2.pid)")
        machine.wait_until_fails("iptables -S nixos-fw | grep -q rescue-fw")
  '';
}

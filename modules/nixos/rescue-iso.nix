# rescue-iso: a Plasma live ISO that is both the user's own rescue/work
# environment and a toolbox for AI agents (Claude Code, Codex) working on a
# broken machine. Built by modules/flake/rescue-iso.nix; booted from the
# USB toolbox stick (Ventoy).
{ config, ... }:
let
  inherit (config.flake) vars;
in
{
  flake.modules.nixos."rescue-iso" =
    { pkgs-unstable, ... }:
    let
      pkgs = pkgs-unstable;

      # agent instructions for the live session; one file for both CLIs
      rescueAgentsMd = pkgs.writeText "rescue-AGENTS.md" (builtins.readFile ./rescue-iso-AGENTS.md);

      # nothing listens by default, so no port is open by default: the
      # servers below open theirs (unscoped, interface names aren't known
      # ahead on a live ISO) only while they run, and bind one address
      phone-paste = pkgs.writers.writePython3Bin "phone-paste" {
        flakeIgnore = [ "E501" ];
      } (builtins.readFile ./rescue-iso-phone-paste.py);

      # share a folder to a phone or another PC with copyparty, read-only
      # unless --rw, behind a password chosen per session
      share = pkgs.writeShellApplication {
        name = "share";
        runtimeInputs = with pkgs; [
          copyparty
          iproute2
          gawk
          coreutils
        ];
        text = ''
          mode=r
          if [[ ''${1:-} == --rw ]]; then mode=rw; shift; fi
          dir=$(realpath "''${1:-.}")
          port=3923
          ip=$(ip -4 route get 1.1.1.1 | awk '{ for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1) }')
          [[ -n $ip ]] || { echo "no network: plug in a phone with USB tethering, or connect with nmtui" >&2; exit 1; }
          read -rsp "Choose a password for this session: " pw
          echo
          sudo nixos-firewall-tool open tcp "$port"
          trap 'sudo nixos-firewall-tool reset' EXIT
          echo "sharing $dir ($mode) on $ip:$port; log in as \"me\". Ctrl+C to stop."
          echo "Not encrypted (plain HTTP): on shared Wi-Fi others could see the password and files. Prefer USB tethering."
          copyparty -i "$ip" -p "$port" --qr -v "$dir:/:$mode,me" -a "me:$pw"
        '';
      };

      ai-login = pkgs.writeShellApplication {
        name = "ai-login";
        runtimeInputs = [
          phone-paste
          pkgs.claude-code
          pkgs.codex
          pkgs.tmux
          pkgs.qrencode
          pkgs.curl
          pkgs.iproute2
          pkgs.gnugrep
          pkgs.coreutils
        ];
        text = builtins.readFile ./rescue-iso-ai-login.sh;
      };

      # internal disks start read-only (udev rule below); this lifts it
      disk-rw = pkgs.writeShellApplication {
        name = "disk-rw";
        runtimeInputs = with pkgs; [
          util-linux
          coreutils
        ];
        text = ''
          if [[ $# -eq 0 ]]; then
            echo "usage: disk-rw /dev/DISK...   (or --all for every internal disk)" >&2
            echo "Internal disks start read-only on this system. Current state:" >&2
            lsblk -d -o NAME,SIZE,RO,TRAN,MODEL >&2
            exit 2
          fi
          if [[ $1 == --all ]]; then
            mapfile -t disks < <(lsblk -dnpo NAME,RO | awk '$2 == 1 { print $1 }' | grep -Ev '^/dev/(loop|sr|zram)')
          else
            disks=("$@")
          fi
          for d in "''${disks[@]}"; do
            sudo blockdev --setrw "$d"
            echo "$d is now writable"
          done
        '';
      };

      # the stick's own exFAT partition, which Ventoy exposes as a dm device
      toolbox-mount = pkgs.writeShellApplication {
        name = "toolbox-mount";
        runtimeInputs = with pkgs; [
          util-linux
          coreutils
        ];
        text = ''
          mode=ro
          [[ ''${1:-} == --rw ]] && mode=rw
          dev=/dev/mapper/VentoyPart
          [[ -e $dev ]] || dev=/dev/disk/by-label/TOOLBOX
          [[ -e $dev ]] || { echo "toolbox stick partition not found (no /dev/mapper/VentoyPart or label TOOLBOX)" >&2; exit 1; }
          sudo mkdir -p /run/toolbox
          if mountpoint -q /run/toolbox; then
            sudo mount -o "remount,$mode" /run/toolbox
          else
            sudo mount -o "$mode,uid=$(id -u),gid=$(id -g)" "$dev" /run/toolbox
          fi
          echo "stick mounted $mode at /run/toolbox (Transfer: /run/toolbox/Transfer)"
        '';
      };

      # offline docs from the stick, in a browser
      toolbox-docs = pkgs.writeShellApplication {
        name = "toolbox-docs";
        runtimeInputs = [
          toolbox-mount
          pkgs.kiwix-tools
          pkgs.util-linux
        ];
        text = ''
          mountpoint -q /run/toolbox || toolbox-mount
          echo "offline docs at http://localhost:8080 (Ctrl+C to stop)"
          exec kiwix-serve --address 127.0.0.1 --port 8080 /run/toolbox/_toolbox/docs/*.zim
        '';
      };
    in
    {
      # boot on whatever machine it's plugged into: every firmware blob
      hardware.enableAllFirmware = true;

      # internal disks start read-only, so nothing (agent or human) writes to
      # a disk being rescued by accident; `disk-rw` lifts it per disk. USB
      # disks stay writable: they're the stick and the backup targets.
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="sd*|nvme*|mmcblk*|vd*|hd*|xvd*", ENV{ID_BUS}!="usb", RUN+="${pkgs.util-linux}/bin/blockdev --setro /dev/%k"
      '';

      # the user's own keys, so the rescue box can be reached over SSH;
      # sshd itself comes from the installer profile
      users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
      users.users.nixos.openssh.authorizedKeys.keys = vars.publicSshKeys;
      # ssh over the tailnet only, never the LAN the box happens to sit on
      services.openssh.openFirewall = false;
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

      # iPhone USB tethering (Android's works without extra services)
      services.usbmuxd.enable = true;

      # inert until `sudo tailscale up --qr`; a live session forgets it on reboot
      services.tailscale.enable = true;

      services.fwupd.enable = true;
      programs.wireshark = {
        enable = true;
        package = pkgs.wireshark;
      };
      users.users.nixos.extraGroups = [ "wireshark" ];
      # KDE Partition Manager, as on the PCs (modules/nixos/kde.nix)
      programs.partition-manager.enable = true;

      # both CLIs keep their login and state in these; nixos must own them
      systemd.tmpfiles.rules = [
        "d /home/nixos/.claude 0700 nixos users - -"
        "d /home/nixos/.codex 0700 nixos users - -"
        "L+ /home/nixos/.claude/CLAUDE.md - - - - ${rescueAgentsMd}"
        "L+ /home/nixos/.codex/AGENTS.md - - - - ${rescueAgentsMd}"
        "d /home/nixos/rescue 0755 nixos users - -"
      ];

      environment.systemPackages = [
        ai-login
        phone-paste
        share
        disk-rw
        toolbox-mount
        toolbox-docs
      ]
      ++ (with pkgs; [
        # AI agents and what they lean on
        claude-code
        codex
        nodejs # codex plugin scripts
        python3
        perl
        bc
        binutils # strings, objdump
        tmux
        qrencode
        gh
        ripgrep
        fd

        # disks: health, imaging, recovery
        ddrescue
        testdisk # also photorec
        smartmontools
        nvme-cli
        hdparm
        sdparm
        gsmartcontrol
        partclone
        fsarchiver
        f3 # fake-capacity flash detection
        fio
        sleuthkit
        foremost
        gnome-disk-utility
        kdePackages.filelight
        ncdu

        # filesystems and encryption beyond profiles/base.nix
        ntfs3g
        exfatprogs
        dosfstools
        e2fsprogs
        btrfs-progs
        xfsprogs
        f2fs-tools
        lvm2
        mdadm
        dislocker # BitLocker
        cryptsetup

        # Windows repair
        chntpw
        wimlib
        hivex

        # boot and firmware
        efibootmgr
        efivar
        mokutil
        sbctl
        dmidecode
        lshw
        inxi
        hwinfo
        usbutils
        pciutils

        # stress and sensors
        stress-ng
        memtester
        lm_sensors
        s-tui
        btop
        htop
        iotop

        # network
        nmap
        iperf3
        mtr
        tcpdump
        dnsutils
        whois
        wget
        aria2
        socat
        ethtool
        iw
        wavemon
        traceroute
        arp-scan
        wireguard-tools
        openssl

        # moving files
        copyparty
        rsync
        rclone
        sshfs
        cifs-utils
        nfs-utils
        samba # smbclient

        # phones
        android-tools
        scrcpy
        libimobiledevice

        # offline docs and odds and ends
        kiwix-tools
        p7zip
        zip
        unzip
        file
        xxd
        binwalk
        qalculate-qt
        kdePackages.kate
      ]);
    };
}

{
  pkgs-unstable,
  pkgs-stable,
  lib,
  config,
  vars,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./nvidia.nix
    ./disko.nix
  ];

  myPullDeploy = {
    enable = true;
    flakeDir = "/home/lilijoy/dotfiles";
    hostAttr = "thinkpad";
    dates = "Thu 03:00";
    autoReboot = false;
    operation = "boot";
    requireACPower = true;
  };

  # System installed pkgs
  environment.systemPackages =
    (with pkgs-unstable; [
    ])
    ++ (with pkgs-stable; [
    ]);

  # fingerprint reader
  services.fprintd.enable = true;

  # state change settings/buttons
  services.logind.settings.Login = {
    HandleLidSwitch = "hybrid-sleep";
    HandlePowerKey = "poweroff";
  };

  # update microcode
  hardware.cpu.intel.updateMicrocode = true;

  # keyboard
  services.keyd = {
    enable = true;
    keyboards.default.ids = [ "0001:0001" ];
    keyboards.default.settings = {
      main = {
        # mods
        capslock = "overload(control, esc)";
        esc = "overload(capslock, esc)";
        leftalt = "layer(navigation)";
        leftcontrol = "leftalt";
      };
      navigation = {
        j = "left";
        k = "down";
        i = "up";
        l = "right";
        u = "pageup";
        o = "pagedown";
      };
    };
  };

  # Define your hostname.
  networking.hostName = "thinkpad";

  # Fix Clickpad Bug and Intel CPU freq stuck fix
  boot.kernelParams = [
    "psmouse.synaptics_intertouch=0"
    "intel_pstate=active"
  ];

  # zfs support
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "5f763495";
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/nix/state".neededForBoot = true;

  # zfs snapshots, and serving them to homelab's puller (zrepl; replaced
  # sanoid + the syncoid-based myBackupPush). Passive side -- see the
  # equivalent block in hosts/torrent/configuration.nix for the reasoning.
  #
  # Being a laptop, this host spends the most time unreachable, so the
  # module's snap job matters most here: snapshotting and a local prune
  # ceiling run on-box and do not wait for homelab. A month away costs
  # nothing -- the replication cursor bookmark survives, so the next pull
  # resumes incrementally rather than resending.
  #
  # That removes what would otherwise be the strongest argument for
  # flipping this host to push (myZrepl.push.targets): under pull the
  # puller owns retention, so without a snap job an unreachable homelab
  # would mean no pruning at all here. Pull is kept because this is also
  # the host most likely to be compromised, and pull is what denies a
  # compromised source the ability to destroy its own backup history.
  myZrepl = {
    enable = true;
    serve = {
      enable = true;
      datasets = [
        "zroot/local/home"
        "zroot/local/root"
      ];
      clients.homelab.publicKey = vars.zreplPullerKey;
    };
  };

  # sshd exists on this host solely to carry zrepl's stdinserver
  # transport: tailnet-only, root login forced-commands-only, and no other
  # root keys present. See hosts/torrent/configuration.nix for detail.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "forced-commands-only";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # auto snapshot pruning at low disk space
  # manual `systemctl start zfs-emergency-prune.service`
  myZfsSpaceGuard = {
    enable = true;
    pool = "zroot";
    datasets = [
      "zroot/local/home"
      "zroot/local/root"
    ];
    freeThresholdPercent = 15;
  };
}

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
  # This is the host with the strongest case for flipping to push
  # (myZrepl.push.targets): it is a laptop whose online windows are short
  # and unpredictable, and a 15m puller can miss them. Left on pull for
  # now because it is also the host most likely to be compromised, and
  # pull is what denies a compromised source the ability to destroy its
  # own backup history. Revisit if coverage proves insufficient in
  # practice rather than pre-emptively.
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

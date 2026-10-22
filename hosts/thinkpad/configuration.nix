{
  pkgs-unstable,
  pkgs-stable,
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

  # state change settings/buttons (lid, idle, sleep key: myHibernateOnly below)
  services.logind.settings.Login.HandlePowerKey = "poweroff";

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

  # encrypted root (disko.nix): unlocked by TPM2 + PIN, either YubiKey
  # (FIDO2) or the recovery passphrase; enrollment is in README.md
  myEncryptedRoot.enable = true;

  # Secure Boot, keys on zroot/local/secureboot; boot menu also lists Windows
  # (its boot files copied onto this ESP, see README.md)
  mySecureBoot.enable = true;
  boot.loader.timeout = 2;

  # hibernate in place of sleep (lid, 60 min idle, critical battery), to the
  # swap LV in disko.nix
  myHibernate = {
    enable = true;
    resumeDevice = "/dev/mapper/vg-swap";
  };
  myHibernateOnly = {
    enable = true;
    # resuming asks for the disk's TPM2 PIN, which is the unlock
    lockOnResume = false;
  };

  # tells the desktop when a pull-deploy is waiting for a restart
  myRebootNotice.enable = true;

  # zroot root dataset's own properties, applied live as well as at disko install
  myZfsDatasetProperties."zroot" = vars.zfsRootFsOptions;

  # zfs snapshots served to homelab's zrepl puller (passive side, as torrent).
  # pull, not push: the most exposed host can't destroy its own backup
  # history; the local snap job keeps pruning while homelab is unreachable
  myZrepl = {
    enable = true;
    preserveLegacySnapshots = false;
    serve = {
      enable = true;
      datasets = [
        "zroot/local/home"
        "zroot/local/root"
      ];
      clients.homelab.publicKey = vars.zreplPullerKey;
    };
  };

  # sshd only carries zrepl's stdinserver transport: tailnet-only, root is
  # forced-commands-only, and there must be no other root keys
  services.openssh = {
    enable = true;
    openFirewall = false;
    # docs/hardening.md's SSH baseline; see hosts/torrent/configuration.nix
    # for why these are `settings`, not `extraConfig`
    allowSFTP = false;
    settings = {
      PermitRootLogin = "forced-commands-only";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AuthenticationMethods = "publickey";
      AllowAgentForwarding = false;
      AllowStreamLocalForwarding = false;
      AllowTcpForwarding = false;
      PermitTunnel = "no";
      ClientAliveInterval = 60;
      ClientAliveCountMax = 5;
    };
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # emergency space reclaim: `systemctl start zfs-emergency-prune.service`
  myZfsSpaceGuard = {
    enable = true;
    datasets = [
      "zroot/local/home"
      "zroot/local/root"
    ];
  };

  # backup restore-test canaries: content must match homelab's
  # myBackupRestoreTest.zbackup.targets byte for byte
  myBackupCanary.paths = {
    "/home/.backup-canary/canary.txt" = "backup-canary thinkpad zroot/local/home v1";
    "/.backup-canary/canary.txt" = "backup-canary thinkpad zroot/local/root v1";
  };

  # failed-unit / stuck-switch alerts to Discord; see
  # hosts/torrent/configuration.nix for the shared webhook and checkSmart
  sops.secrets.discord_webhook = {
    owner = "health-check";
    group = "health-check";
  };

  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.discord_webhook.path;
    checkSmart = false;
    # after weeks off, the Persistent timer fires one catch-up batch;
    # cooldownHours keeps it to one
    #
    # a pull-deploy that stops running. 720h, not torrent's 504: a laptop
    # goes dark for weeks and requireACPower legitimately skips battery
    # Thursdays
    staleMarkerFiles = {
      "/var/lib/pull-deploy/deployed" = 720;
    };
  };
}

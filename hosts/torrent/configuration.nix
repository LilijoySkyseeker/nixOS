{
  pkgs-unstable,
  config,
  vars,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  myPullDeploy = {
    enable = true;
    hostAttr = "torrent";
    dates = "Thu 03:00";
    operation = "boot";
  };

  environment.systemPackages = [ pkgs-unstable.bambu-studio ];

  powerManagement.cpuFreqGovernor = "performance";

  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  time.timeZone = "America/Los_Angeles";

  networking.hostName = "torrent";

  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  networking.hostId = "0376f9ae";
  fileSystems."/nix".neededForBoot = true;

  myZfsDatasetProperties."zroot" = vars.zfsRootFsOptions;
  # gguf files: large sequential reads that don't compress. primarycache stays
  # "all": llama.cpp's mmap faults 4 KiB pages, and without the arc each fault
  # rereads the whole 1M record
  myZfsDatasetProperties."zroot/local/models" = {
    recordsize = "1M";
    primarycache = "all";
  };

  # zfs snapshots served to homelab's zrepl puller; passive side: holds no
  # homelab credential and homelab owns retention, so a compromise here can't
  # delete backup history. the local snap job prunes even if homelab is away
  myZrepl = {
    enable = true;
    serve = {
      enable = true;
      datasets = [
        "zroot/local/home"
        "zroot/local/root"
        "zroot/local/models"
      ];
      clients.homelab.publicKey = vars.zreplPullerKey;
    };
  };

  # sshd only carries zrepl's stdinserver transport: tailnet-only, root is
  # forced-commands-only, and there must be no other root keys
  services.openssh = {
    enable = true;
    openFirewall = false;
    allowSFTP = false;
    settings = {
      PermitRootLogin = "forced-commands-only";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;

      # in `settings`, not
      # `extraConfig`: sshd_config is first-directive-wins and `settings`
      # renders first
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

  # backup restore-test canaries: content must match homelab's
  # myBackupRestoreTest.zbackup.targets byte for byte
  myBackupCanary.paths = {
    "/home/.backup-canary/canary.txt" = "backup-canary torrent zroot/local/home v1";
    "/.backup-canary/canary.txt" = "backup-canary torrent zroot/local/root v1";
    "/srv/models/.backup-canary/canary.txt" = "backup-canary torrent zroot/local/models v1";
  };

  # paseo daemon password: only its bcrypt hash, in a torrent-only sops file;
  # the plaintext lives in the owner's password manager
  sops.secrets.paseo_password_hash = {
    sopsFile = ../../secrets/torrent.yaml;
    restartUnits = [
      "paseo-agent-config.service"
      "paseo.service"
      "paseo-tailscale-serve.service"
    ];
  };
  systemd.services.paseo-agent-config.serviceConfig.LoadCredential =
    "paseo-password-hash:${config.sops.secrets.paseo_password_hash.path}";

  # failed-unit / stuck-switch alerts to Discord; one fleet-wide webhook,
  # shared on purpose (write-only sink, worst case is forged alerts)
  sops.secrets.discord_webhook = {
    owner = "health-check";
    group = "health-check";
  };

  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.discord_webhook.path;
    # off: smartctl needs the disk group + CAP_SYS_RAWIO (root-equivalent), and
    # the fleet-wide smartd already reaches a human via the graphical session
    checkSmart = false;
    # a pull-deploy that stops running; a failed one pages as a failed
    # unit. 504h = 21 days, weekly deploys plus two weeks of slack
    staleMarkerFiles = {
      "/var/lib/pull-deploy/deployed" = 504;
    };
  };
}

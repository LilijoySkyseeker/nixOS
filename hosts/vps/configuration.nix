{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  # DigitalOcean's only world facing interface
  externalInterface = "ens3";

  # reciever for homelab's vps deployer/updater
  vpsDeployDispatcher = pkgs.writeShellScript "vps-deploy-dispatcher" ''
    set -eu
    cmd=$SSH_ORIGINAL_COMMAND

    # restrict the name half of the Nix store path to this system's own closures
    store_path=$(
      printf '%s\n' "$cmd" \
        | ${pkgs.gnugrep}/bin/grep -oE '/nix/store/[0-9a-z]{32}-nixos-system-vps-[0-9A-Za-z._-]+' \
        | ${pkgs.coreutils}/bin/head -n1
    ) || store_path=""

    reject() {
      # the stderr line only reaches the ssh *client*; the logger line
      # lands in this host's own journal
      ${pkgs.util-linux}/bin/logger -t vps-deploy -p auth.warning "rejected command: $cmd" || true
      echo "vps-deploy: rejected command: $cmd" >&2
      exit 1
    }

    require_store_path() {
      [ -n "$store_path" ] || reject
    }

    case "$cmd" in
      *"nix-store --serve --write"*)
        exec ${pkgs.nix}/bin/nix-store --serve --write
        ;;
    esac

    # nixos-rebuild's pre-activation sanity check
    case "$cmd" in
      *"test -f "*"/nixos-version"*)
        require_store_path
        exec ${pkgs.coreutils}/bin/test -f "$store_path/nixos-version"
        ;;
    esac

    # nixos-rebuild's own "is systemd actually running" check
    case "$cmd" in
      *"test -d /run/systemd/system"*)
        exec ${pkgs.coreutils}/bin/test -d /run/systemd/system
        ;;
    esac

    # nixos-rebuild's `nix-env --set` step, points profile at new generation
    case "$cmd" in
      *"nix-env -p /nix/var/nix/profiles/system --set"*)
        require_store_path
        exec /run/current-system/sw/bin/sudo ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set "$store_path"
        ;;
    esac

    # nixos-rebuild's switch-to-configuration invocation
    case "$cmd" in
      *"switch-to-configuration switch"*)
        require_store_path
        exec /run/current-system/sw/bin/sudo "$store_path/bin/switch-to-configuration" switch
        ;;
    esac

    # reboot-if-kernel-changed trigger
    case "$cmd" in
      *"systemctl reboot"*)
        exec /run/current-system/sw/bin/sudo ${pkgs.systemd}/bin/systemctl reboot
        ;;
    esac

    # myPushDeploy's pre-reboot kernel-change check
    case "$cmd" in
      *"readlink /run/booted-system/kernel"*)
        exec ${pkgs.coreutils}/bin/readlink /run/booted-system/kernel
        ;;
      *"readlink /run/current-system/kernel"*)
        exec ${pkgs.coreutils}/bin/readlink /run/current-system/kernel
        ;;
    esac

    # myPushDeploy's minSwitchInterval pre-check -- exact match, no
    # wildcard, since this one has no interpolated store path to bound
    case "$cmd" in
      "stat -c %Y /nix/var/nix/profiles/system")
        exec ${pkgs.coreutils}/bin/stat -c %Y /nix/var/nix/profiles/system
        ;;
    esac

    reject
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Define your hostname.
  networking.hostName = "vps";

  # DigitalOcean's hypervisor virtual switch needs cloud-init to run and "register"/arm the droplet's network before it'll pass any traffic for that NIC
  networking.networkmanager.enable = lib.mkForce false;
  # DigitalOcean's public NIC has no DHCP; cloud-init renders its static
  # config as networkd units, so networkd must manage interfaces and useDHCP
  # stays off or dhcpcd races networkd for the NIC
  networking.useNetworkd = true;
  networking.useDHCP = false;
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [ "ConfigDrive" ];
      datasource.ConfigDrive = { };
      cloud_init_modules = [ "seed_random" ];
      cloud_config_modules = [ ];
      cloud_final_modules = [ ];
      preserve_hostname = true;
    };
  };
  # upstream cloud-init's 05_logging.cfg verbatim (the NixOS module omits it):
  # console at WARNING, full DEBUG to /var/log/cloud-init.log
  environment.etc."cloud/cloud.cfg.d/05_logging.cfg".text = ''
    _log:
     - &log_base |
       [loggers]
       keys=root,cloudinit

       [handlers]
       keys=consoleHandler,cloudLogHandler

       [formatters]
       keys=simpleFormatter,arg0Formatter

       [logger_root]
       level=DEBUG
       handlers=consoleHandler,cloudLogHandler

       [logger_cloudinit]
       level=DEBUG
       qualname=cloudinit
       handlers=
       propagate=1

       [handler_consoleHandler]
       class=StreamHandler
       level=WARNING
       formatter=arg0Formatter
       args=(sys.stderr,)

       [formatter_arg0Formatter]
       format=%(asctime)s - %(filename)s[%(levelname)s]: %(message)s

       [formatter_simpleFormatter]
       format=[CLOUDINIT] %(filename)s[%(levelname)s]: %(message)s
     - &log_file |
       [handler_cloudLogHandler]
       class=FileHandler
       level=DEBUG
       formatter=arg0Formatter
       args=('/var/log/cloud-init.log', 'a', 'UTF-8')

    log_cfgs:
     - [ *log_base, *log_file ]

    output: {all: '| tee -a /var/log/cloud-init-output.log'}
  '';

  # DigitalOcean only supports GRUB, not systemdboot
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
  };

  # zram instead to prevent secrets leakage
  zramSwap.enable = true;

  # impermanence: root is tmpfs and wiped every boot
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "size=2G"
      "mode=0755"
      "noexec"
      "nosuid"
      "nodev"
    ];
    neededForBoot = true;
  };
  # exec-capable: cloud-init execs DigitalOcean's vendor-data boothook from
  # here (root is noexec), and without it the droplet's network never arms
  fileSystems."/var/lib/cloud" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "size=64M"
      "mode=0755"
      "nosuid"
      "nodev"
    ];
    neededForBoot = true;
  };
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;

  # persisteted file and dirs between imepmatence wipes
  environment.persistence."/persist" = {
    enable = true;
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos" # avoids uid/gid complaints on reboot
      "/var/lib/tailscale" # node identity/state; authKeyFile is single-use
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key" # for sops age key gen
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  # ssh key root access
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;

  # updater user
  users.users.vps-deploy = {
    isSystemUser = true;
    group = "vps-deploy";
    # needed for sshd
    shell = "${pkgs.bash}/bin/bash";
    openssh.authorizedKeys.keys = [
      # homelab -> vps push-deploy key
      "command=\"${vpsDeployDispatcher}\",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlJbrWrcdGkWtpXnBZgAJ0gHHR1G36SSmdeoLHzqPGn homelab-vps-deploy"
    ];
  };
  users.groups.vps-deploy = { };

  # lets vps-deploy elevate privladge
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "vps-deploy") {
        // silent auto-grants leave no journal line otherwise
        polkit.log("vps-deploy manage-units grant: " + action.id);
        return polkit.Result.YES;
      }
    });
  '';

  # needed for the nix daemon to accept closures vps-deploy copies in
  nix.settings.trusted-users = [ "vps-deploy" ];
  services.openssh = {
    enable = true;
    # force port 22 closed
    openFirewall = false;
    allowSFTP = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PasswordAuthentication = false;
    extraConfig = ''
      PermitRootLogin = prohibit-password
      AllowTcpForwarding no
      X11Forwarding no
      AllowAgentForwarding no
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
      PermitTunnel no
      ClientAliveInterval 60
      ClientAliveCountMax 5
    '';
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # tailscale allow
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # the module's LOG rule has no rate limit and can outrun journald under a scan
  networking.firewall.logRefusedConnections = false;

  # wireguard tunnel
  # networkd reads PrivateKeyFile only at link setup and a key-only rotation
  # changes no unit file, so restart it explicitly
  sops.secrets.vps_wireguard_private_key.restartUnits = [ "systemd-networkd.service" ];
  sops.secrets.wireguard_vps_homelab_psk.restartUnits = [ "systemd-networkd.service" ];
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets.vps_wireguard_private_key.path;
    peers = [
      {
        # homelab
        publicKey = "d4dZJWJpbExfmmZivueaSAuRItMHUWOAsoZBYt9rHTc=";
        presharedKeyFile = config.sops.secrets.wireguard_vps_homelab_psk.path;
        allowedIPs = [ "10.100.0.2/32" ];
      }
    ];
  };

  # game server forwarding
  networking.nat = {
    enable = true;
    inherit externalInterface;
    forwardPorts = [
      {
        destination = "10.100.0.2:25565";
        proto = "tcp";
        sourcePort = 25565;
      }
      {
        destination = "10.100.0.2:19132";
        proto = "udp";
        sourcePort = 19132; # minecraft: geyser (bedrock edition)
      }
      {
        destination = "10.100.0.2:34197";
        proto = "udp";
        sourcePort = 34197; # factorio
      }
    ];
  };

  # SNAT forwarded traffic to our wg0 IP so source IP's are preserved
  networking.firewall.extraCommands = ''
    iptables -t nat -C POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1 2>/dev/null \
      || iptables -t nat -A POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1

    # per-source-IP rate limiting on forwarded game ports
    iptables -t raw -N vps-ratelimit 2>/dev/null || iptables -t raw -F vps-ratelimit
    iptables -t raw -C PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null \
      || iptables -t raw -I PREROUTING -i ${externalInterface} -j vps-ratelimit

    # minecraft: cap new-connection attempts per source IP
    iptables -t raw -A vps-ratelimit -p tcp --dport 25565 --syn \
      -m hashlimit --hashlimit-above 15/minute --hashlimit-burst 10 \
      --hashlimit-mode srcip --hashlimit-name mc-new -j DROP

    # minecraft (geyser/bedrock): cap packet rate per source IP
    iptables -t raw -A vps-ratelimit -p udp --dport 19132 \
      -m hashlimit --hashlimit-above 1000/second --hashlimit-burst 500 \
      --hashlimit-mode srcip --hashlimit-name mc-bedrock-flood -j DROP

    # factorio: cap packet rate per source IP
    iptables -t raw -A vps-ratelimit -p udp --dport 34197 \
      -m hashlimit --hashlimit-above 2000/second --hashlimit-burst 1000 \
      --hashlimit-mode srcip --hashlimit-name factorio-flood -j DROP
  '';

  # tear down the raw-table chain; the firewall's stop path only flushes
  # nat/filter. every line guarded: runs under `set -e`, and a half-aborted
  # stop is worse than a skipped rule
  networking.firewall.extraStopCommands = ''
    iptables -t raw -D PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null || true
    iptables -t raw -F vps-ratelimit 2>/dev/null || true
    iptables -t raw -X vps-ratelimit 2>/dev/null || true
  '';

  # this box never needs to forward IPv6
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = false;

  # default 90s start timeout kills tailscaled-autoconnect before tailscale is Running on a slow boot
  systemd.services.tailscaled-autoconnect.serviceConfig.TimeoutStartSec = "300s";

  # failed-unit / stuck-switch alerts to Discord, no ZFS/SMART on this box
  sops.secrets.discord_webhook = {
    owner = "health-check";
    group = "health-check";
  };

  # small disk: half the fleet's journal cap
  # stable spelling; replaces the profile's 2G line rather than adding to it
  services.journald.extraConfig = lib.mkForce "SystemMaxUse=1G";

  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.discord_webhook.path;
    checkZfs = false;
    checkSmart = false;
    # homelab push-deploys this host and exits 0 when a guard defers, so the
    # profile's mtime is the only signal activations stopped; 504h = 21 days,
    # weekly deploys plus two weeks of slack
    staleMarkerFiles = {
      "/nix/var/nix/profiles/system" = 504;
    };
  };

  # this box has no real block devices for smartd to monitor
  services.smartd.enable = lib.mkForce false;

  # firewall
  networking.firewall.allowedUDPPorts = [
    51820 # wireguard
  ];

}

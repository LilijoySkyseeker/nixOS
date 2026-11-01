{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  externalInterface = "ens3";

  vpsDeployDispatcher = pkgs.writeShellScript "vps-deploy-dispatcher" ''
    set -eu
    cmd=$SSH_ORIGINAL_COMMAND

    store_path=$(
      printf '%s\n' "$cmd" \
        | ${pkgs.gnugrep}/bin/grep -oE '/nix/store/[0-9a-z]{32}-nixos-system-vps-[0-9A-Za-z._-]+' \
        | ${pkgs.coreutils}/bin/head -n1
    ) || store_path=""

    reject() {
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

    case "$cmd" in
      *"nix-env -p /nix/var/nix/profiles/system --set"*)
        require_store_path
        exec /run/current-system/sw/bin/sudo ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set "$store_path"
        ;;
    esac

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

    # homelab's heartbeat: vps alerts when it stops (myHealthAlerts below)
    case "$cmd" in
      "heartbeat")
        exec ${pkgs.coreutils}/bin/touch /var/lib/heartbeat/homelab
        ;;
    esac

    # myPushDeploy's "what does vps run, and what is installed" checks --
    # exact match, no wildcard, since these have no store path to bound
    case "$cmd" in
      "/run/current-system/sw/bin/nixos-version --configuration-revision")
        exec /run/current-system/sw/bin/nixos-version --configuration-revision
        ;;
      "/nix/var/nix/profiles/system/sw/bin/nixos-version --configuration-revision")
        exec /nix/var/nix/profiles/system/sw/bin/nixos-version --configuration-revision
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
      cloud_init_modules = [ ];
      cloud_config_modules = [ ];
      cloud_final_modules = [ ];
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
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
  };

  # zram instead to prevent secrets leakage
  zramSwap.enable = true;

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "size=2G"
      "mode=0755"
    ];
  };
  fileSystems."/persist".neededForBoot = true;

  environment.persistence."/persist" = {
    directories = [
      "/var/log"
      "/var/lib/nixos" # avoids uid/gid complaints on reboot
      "/var/lib/tailscale" # node identity/state; authKeyFile is single-use
      {
        # homelab's heartbeat marker, written by vps-deploy's dispatcher
        directory = "/var/lib/heartbeat";
        user = "vps-deploy";
        group = "vps-deploy";
        mode = "0755";
      }
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key" # for sops age key gen
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;

  users.users.vps-deploy = {
    isSystemUser = true;
    group = "vps-deploy";
    # needed for sshd
    shell = "${pkgs.bash}/bin/bash";
    openssh.authorizedKeys.keys = [
      "command=\"${vpsDeployDispatcher}\",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlJbrWrcdGkWtpXnBZgAJ0gHHR1G36SSmdeoLHzqPGn homelab-vps-deploy"
    ];
  };
  users.groups.vps-deploy = { };

  # lets vps-deploy elevate privladge
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "vps-deploy") {
        return polkit.Result.YES;
      }
    });
  '';

  # needed for the nix daemon to accept closures vps-deploy copies in
  nix.settings.trusted-users = [ "vps-deploy" ];

  # /nix is a fixed 18G partition and each nixpkgs bump adds ~5G: room for two generations plus an incoming push
  programs.nh.clean.extraArgs = lib.mkForce "--keep-since 7d --keep 2";
  nix.settings.auto-optimise-store = true;
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PasswordAuthentication = false;
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # the module's LOG rule has no rate limit and can outrun journald under a scan
  networking.firewall.logRefusedConnections = false;

  # networkd reads PrivateKeyFile only at link setup and a key-only rotation
  # changes no unit file, so restart it explicitly
  sops.secrets.vps_wireguard_private_key.restartUnits = [ "systemd-networkd.service" ];
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets.vps_wireguard_private_key.path;
    peers = [
      {
        publicKey = "d4dZJWJpbExfmmZivueaSAuRItMHUWOAsoZBYt9rHTc=";
        allowedIPs = [ "10.100.0.2/32" ];
      }
    ];
  };

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
        sourcePort = 19132;
      }
      {
        destination = "10.100.0.2:80";
        proto = "tcp";
        sourcePort = 80; # website: ACME challenges and the https redirect
      }
      {
        destination = "10.100.0.2:443";
        proto = "tcp";
        sourcePort = 443;
      }
    ];
  };

  # SNAT forwarded traffic to our wg0 IP so replies return through the tunnel;
  # homelab sees every forwarded client as 10.100.0.1, so per-IP limits live here
  networking.firewall.extraCommands = ''
    iptables -t nat -C POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1 2>/dev/null \
      || iptables -t nat -A POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1

    iptables -t raw -N vps-ratelimit 2>/dev/null || iptables -t raw -F vps-ratelimit
    iptables -t raw -C PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null \
      || iptables -t raw -I PREROUTING -i ${externalInterface} -j vps-ratelimit

    iptables -t raw -A vps-ratelimit -p tcp --dport 25565 --syn \
      -m hashlimit --hashlimit-above 15/minute --hashlimit-burst 10 \
      --hashlimit-mode srcip --hashlimit-name mc-new -j DROP

    iptables -t raw -A vps-ratelimit -p udp --dport 19132 \
      -m hashlimit --hashlimit-above 1000/second --hashlimit-burst 500 \
      --hashlimit-mode srcip --hashlimit-name mc-bedrock-flood -j DROP

    iptables -t raw -A vps-ratelimit -p tcp -m multiport --dports 80,443 --syn \
      -m hashlimit --hashlimit-above 120/minute --hashlimit-burst 60 \
      --hashlimit-mode srcip --hashlimit-name http-new -j DROP
  '';

  # default 90s start timeout kills tailscaled-autoconnect before tailscale is Running on a slow boot
  systemd.services.tailscaled-autoconnect.serviceConfig.TimeoutStartSec = "300s";

  sops.secrets.discord_webhook = {
    owner = "health-check";
    group = "health-check";
  };

  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.discord_webhook.path;
    checkZfs = false;
    checkSmart = false;
    # deploy staleness is homelab's: it pushes this host and watches
    # /var/lib/push-deploy/deployed-vps
    # homelab checks in every 5m (heartbeat-vps there); silence means
    # homelab, its network or the house is down
    staleMarkerFiles."/var/lib/heartbeat/homelab" = 1;
  };

  # this box has no real block devices for smartd to monitor
  services.smartd.enable = lib.mkForce false;

  networking.firewall.allowedUDPPorts = [
    51820
  ];

}

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
  networking.useDHCP = lib.mkDefault true;
  services.cloud-init = {
    enable = true;
    settings = {
      datasource_list = [ "ConfigDrive" ];
      datasource.ConfigDrive = { };
      cloud_init_modules = [ "seed_random" ];
      cloud_config_modules = [ ];
      cloud_final_modules = [ ];
      preserve_hostname = true;
    };
  };

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
      "/var/lib/caddy" # ACME certs — avoids re-requesting from Let's Encrypt every reboot
      {
        directory = "/var/lib/crowdsec";
        user = "crowdsec";
        group = "crowdsec";
        mode = "0750";
      }
      "/etc/crowdsec" # hub state (installed collections/parsers)
      {
        # crowdsec-firewall-bouncer-register's api-key.cred lives here. Without
        # persisting it, every reboot wipes this dir while /var/lib/crowdsec's
        # bouncer-registration DB above survives, so the register service finds
        # the bouncer already registered but has no key file for it and fails
        # ("Bouncer registered but API key is not present").
        directory = "/var/lib/crowdsec-firewall-bouncer-register";
        user = "crowdsec";
        group = "crowdsec";
        mode = "0750";
      }
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
      "command=\"${vpsDeployDispatcher}\",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINDGczUoWFSHuf+96aLLrGd+Eqkz5KTFY1gYbSaqJJFp homelab-vps-deploy"
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

  # log refused TCP connection attempts (closed-port scans) to the kernel log —
  # off by default, so these were previously invisible everywhere, including to CrowdSec
  networking.firewall.logRefusedConnections = true;

  # wireguard tunnel
  sops.secrets.vps_wireguard_private_key = { };
  sops.secrets.wireguard_vps_homelab_psk = { };
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets.vps_wireguard_private_key.path;
    peers = [
      {
        # homelab
        publicKey = "GH5vw+bR1d28xPPTlB4cn9VLp529QAyyNAJhnhmzVXE=";
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
        sourcePort = 34197; # old.factorio
      }
      {
        destination = "10.100.0.2:34198";
        proto = "udp";
        sourcePort = 34198; # new.factorio
      }
    ];
  };

  # SNAT forwarded traffic to our wg0 IP so source IP's are preserved
  networking.firewall.extraCommands = ''
    iptables -t nat -C POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1 2>/dev/null \
      || iptables -t nat -A POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1

    # crowdsec-firewall-bouncer.service is After=/PartOf=firewall.service, so it always
    # creates this ipset *after* we get here — pre-create it (idempotent, matches the
    # bouncer's own params exactly) so referencing it below doesn't fail on every boot
    ${pkgs.ipset}/bin/ipset create -exist crowdsec-blacklists-0 hash:net family inet \
      hashsize 1024 maxelem 131072 timeout 300

    # per-source-IP rate limiting on forwarded game ports (DNAT bypasses anubis/crowdsec)
    iptables -t raw -N vps-ratelimit 2>/dev/null || iptables -t raw -F vps-ratelimit
    iptables -t raw -C PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null \
      || iptables -t raw -I PREROUTING -i ${externalInterface} -j vps-ratelimit

    # apply CrowdSec's existing ban list (built from sshd/caddy scenarios) to DNAT'd game
    # traffic too — it never reaches INPUT/CROWDSEC_CHAIN, so this reuses the bouncer's own
    # ipset instead of duplicating ban logic. Must come first in the chain: banned IPs get
    # dropped before spending any hashlimit budget below.
    iptables -t raw -A vps-ratelimit -m set --match-set crowdsec-blacklists-0 src -j DROP

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

    # new.factorio: same as old.factorio
    iptables -t raw -A vps-ratelimit -p udp --dport 34198 \
      -m hashlimit --hashlimit-above 2000/second --hashlimit-burst 1000 \
      --hashlimit-mode srcip --hashlimit-name factorio-new-flood -j DROP

    # base rate limit for caddy's public HTTP(S) entry (80/443)
    iptables -t raw -A vps-ratelimit -p tcp -m multiport --dports 80,443 --syn \
      -m hashlimit --hashlimit-above 120/minute --hashlimit-burst 60 \
      --hashlimit-mode srcip --hashlimit-name http-new -j DROP
  '';

  # narrow tailscale routing to "client", this box isn't an exit node/subnet router
  services.tailscale.useRoutingFeatures = lib.mkForce "client";

  # this box never needs to forward IPv6
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = false;

  # anubis: proof-of-work challenge in front of jellyfin
  services.anubis.instances.jellyfin = {
    enable = true;
    settings = {
      TARGET = "http://10.100.0.2:8096";
    };
  };

  # caddy: public HTTPS entry point, jellyfin routes through anubis
  sops.secrets.vps_caddy_env = { }; # TODO: populate with DNS provider API token if using DNS-01 challenges
  # caddy needs group membership to reverse_proxy into anubis's unix socket
  users.users.caddy.extraGroups = [ "anubis" ];
  services.caddy = {
    enable = true;
    virtualHosts = {
      # catch-all for plain-HTTP requests with no matching Host (bots hitting the raw
      # IP, fake hostnames, etc.) — otherwise these produce zero log output anywhere.
      # HTTPS/SNI-based probes aren't covered here: Caddy can't present a cert for an
      # unlisted hostname without on-demand TLS, which is its own design/abuse-surface
      # decision, not a quick add — left for a follow-up.
      ":80" = {
        logFormat = ''
          output stdout
          format json
        '';
        extraConfig = ''
          respond 421
        '';
      };
      "jellyfin.${lib.removeSuffix "." vars.domain}" = {
        # without this, caddy emits no access logs for crowdsec's parser
        logFormat = ''
          output stdout
          format json
        '';
        extraConfig = ''
          header {
            Strict-Transport-Security "max-age=31536000"
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            Referrer-Policy "strict-origin-when-cross-origin"
            Permissions-Policy "camera=(), microphone=(), geolocation=()"
          }
          reverse_proxy unix//run/anubis/anubis-jellyfin/anubis.sock {
            # anubis refuses to proxy without an explicit X-Real-Ip
            header_up X-Real-Ip {remote_host}
          }
        '';
      };
    };
  };

  # crowdsec: watches sshd/caddy logs, bans abusive IPs via the firewall bouncer
  services.crowdsec = {
    enable = true;
    # needed for the local API crowdsec and the bouncer both talk to
    settings.general.api.server.enable = true;
    settings.lapi.credentialsFile = "/var/lib/crowdsec/local_api_credentials.yaml";
    hub.collections = [
      "crowdsecurity/linux"
      "crowdsecurity/sshd"
      "crowdsecurity/caddy"
    ];
    localConfig.acquisitions = [
      {
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
        labels.type = "syslog";
      }
      {
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=caddy.service" ];
        # must be "syslog", not "caddy" — strips the journalctl envelope
        labels.type = "syslog";
      }
    ];
  };
  services.crowdsec-firewall-bouncer.enable = true;
  # drop both "crowdsec" and "crowdsec-firewall-bouncer-register" from StateDirectory —
  # both are real impermanence bind-mounts, and DynamicUser's StateDirectory= migration
  # (moving the "pre-existing public" dir into /var/lib/private/<name> behind a symlink)
  # deterministically fails with EBUSY against an active mountpoint. Confirmed live
  # 2026-08-25: this unit's own directory hit exactly the failure the "crowdsec" drop
  # below was already written to avoid, just never extended to itself.
  systemd.services.crowdsec-firewall-bouncer-register.serviceConfig = {
    StateDirectory = lib.mkForce [ ];
    # DynamicUser makes these read-only otherwise; cscli needs to write /var/lib/crowdsec,
    # and this unit needs to write its own state (api-key.cred) under the other path
    ReadWritePaths = [
      "/var/lib/crowdsec"
      "/var/lib/crowdsec-firewall-bouncer-register"
    ];
  };
  # symlink cscli's expected default config path into place
  systemd.tmpfiles.rules = [
    "L+ /etc/crowdsec/config.yaml - - - - ${
      (pkgs.formats.yaml { }).generate "crowdsec.yaml" config.services.crowdsec.settings.general
    }"
  ];

  # failed-unit / stuck-switch alerts to Discord, no ZFS/SMART on this box
  sops.secrets.vps_discord_webhook = {
    owner = "health-check";
    group = "health-check";
  };
  myHealthAlerts = {
    enable = true;
    webhookUrlFile = config.sops.secrets.vps_discord_webhook.path;
    checkZfs = false;
    checkSmart = false;
  };

  # this box has no real block devices for smartd to monitor
  services.smartd.enable = lib.mkForce false;

  # firewall
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    51820 # wireguard
  ];

}

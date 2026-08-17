{
  config,
  lib,
  vars,
  ...
}:
let
  # TODO: confirm against `ip a` once the DigitalOcean droplet exists —
  # was "enp1s0" on the prior Vultr instance; DigitalOcean's predictable
  # interface naming may differ (often "eth0" on their images).
  externalInterface = "eth0";
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    ../../profiles/default.nix
    ../../profiles/server.nix

    ../../modules/nixos/pull-deploy.nix
    ../../modules/nixos/health-alerts.nix
  ];

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Define your hostname.
  networking.hostName = "vps";

  # pull whatever homelab's myAutoUpdate has already build-tested and
  # merged to master, then build/switch/reboot-if-needed here too — no
  # separate bump/test/merge cycle (that's homelab's job), just apply
  # what's already vetted on master.
  myPullDeploy = {
    enable = true;
    flakeDir = "/etc/nixos";
    hostAttr = "vps";
    dates = "Thu 03:00"; # matches homelab's myAutoUpdate.switchDates
    autoReboot = true;
    operation = "switch";
  };

  # DigitalOcean droplets don't support UEFI boot at all (confirmed via
  # DO's own docs/community forum) — systemd-boot never gets invoked and
  # the droplet hangs unbootable with no console output. GRUB in legacy
  # BIOS mode (GPT + a BIOS boot partition, see disko.nix) is required.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  # devices intentionally omitted — disko auto-populates
  # boot.loader.grub.devices from the EF02 partition it finds in
  # disko.nix; setting it here too duplicates the entry.
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
  };

  # zram instead of a disk-backed swap partition — see disko.nix for why
  # (decrypted secrets in /run shouldn't be able to page out to disk).
  zramSwap.enable = true;

  # impermanence: root is tmpfs and wiped every boot. No ZFS here — a
  # single cloud disk gets nothing from it without redundancy to
  # leverage, so this is plain tmpfs-root + bind-mounted /persist
  # instead of the ZFS-rollback approach homelab uses.
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "size=2G"
      "mode=0755"
      # everything actually executed comes from /nix/store (a separate,
      # exec-enabled partition) via symlinks — nothing physically
      # written to the root tmpfs itself needs to be run directly.
      "noexec"
      "nosuid"
      "nodev"
    ];
    neededForBoot = true;
  };
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist" = {
    enable = true;
    hideMounts = true;
    directories = [
      "/etc/nixos"
      "/var/log"
      "/var/lib/nixos" # avoids uid/gid complaints on reboot
      "/var/lib/tailscale" # node identity/state; without this, a non-reusable
      # authKeyFile is consumed on first boot then fails every boot after
      "/var/lib/caddy" # ACME certs — avoids re-requesting from Let's Encrypt every reboot
      "/var/lib/crowdsec" # local ban decisions/state
      "/etc/crowdsec" # hub state (installed collections/parsers)
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key" # must persist — sops.age identity is
      # derived from this; losing it locks the host out of its own secrets
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  # ssh server — reachable over tailscale/wireguard only (see
  # networking.firewall.trustedInterfaces below); port 22 is never
  # opened on the public interface, so it isn't part of this box's
  # internet-facing attack surface at all.
  users.users.root.openssh.authorizedKeys.keys = vars.publicSshKeys;
  services.openssh = {
    enable = true;
    allowSFTP = false;
    settings.KbdInteractiveAuthentication = false;
    extraConfig = ''
      passwordAuthentication = no
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

  # tailscale (services.tailscale itself comes from profiles/default.nix)
  # is how we manage/ssh into this box; trusting its interface lets
  # sshd stay reachable over the tailnet without ever exposing 22
  # publicly. wireguard's own tunnel doesn't need the same treatment —
  # only homelab rides it, and only for the ports explicitly forwarded
  # below.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # sops.age.sshKeyPaths comes from profiles/server.nix. This host's age
  # public key (`nix run nixpkgs#ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`)
  # needs to be added to .sops.yaml's creation_rules before any
  # sops.secrets below will decrypt — see README.md.

  # wireguard: this box is the public-facing tunnel endpoint; homelab
  # (behind CGNAT) dials out to it. allowedIPs restricts the tunnel to
  # a single homelab peer since nothing else should ride this link.
  sops.secrets.vps_wireguard_private_key = { };
  # PSK is an extra symmetric secret required on top of the keypair
  # handshake — defense-in-depth against a future break of the
  # asymmetric crypto, standard WireGuard hardening advice. Same file
  # content needed verbatim on both ends (see TODO-vps-manual-steps.md).
  sops.secrets.wireguard_vps_homelab_psk = { };
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets.vps_wireguard_private_key.path;
    peers = [
      {
        # homelab
        publicKey = "REPLACE_WITH_HOMELAB_WIREGUARD_PUBLIC_KEY";
        presharedKeyFile = config.sops.secrets.wireguard_vps_homelab_psk.path;
        allowedIPs = [ "10.100.0.2/32" ];
      }
    ];
  };

  # forward the game server ports straight through to homelab over the
  # tunnel — these are raw TCP/UDP, not HTTP, so caddy can't front them,
  # and unlike the caddy path they never pass through anubis or
  # crowdsec (those only see sshd/caddy traffic) — DNAT happens at the
  # netfilter level below caddy/anubis/crowdsec entirely. The
  # per-source rate limits below are this path's only abuse defense.
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
        sourcePort = 34197;
      }
    ];
  };

  # per-source-IP rate limiting on the forwarded game ports, since
  # DNAT'd traffic bypasses anubis/crowdsec entirely (see above). Raw
  # table so it's evaluated before conntrack/NAT and independent of
  # whatever chain names the nat/firewall modules generate internally.
  # Thresholds are deliberately loose (a real player's client won't hit
  # them) — this is a floor against basic scanning/flooding, not a full
  # DDoS mitigation; a large enough volumetric flood saturates the
  # uplink before any firewall rule gets a say regardless.
  networking.firewall.extraCommands = ''
    iptables -t raw -N vps-ratelimit 2>/dev/null || iptables -t raw -F vps-ratelimit
    iptables -t raw -C PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null \
      || iptables -t raw -I PREROUTING -i ${externalInterface} -j vps-ratelimit

    # minecraft: cap new-connection attempts per source IP
    iptables -t raw -A vps-ratelimit -p tcp --dport 25565 --syn \
      -m hashlimit --hashlimit-above 15/minute --hashlimit-burst 10 \
      --hashlimit-mode srcip --hashlimit-name mc-new -j DROP

    # minecraft (geyser/bedrock): cap packet rate per source IP (also
    # blunts UDP amplification/reflection abuse of this port, same as
    # the factorio rule below)
    iptables -t raw -A vps-ratelimit -p udp --dport 19132 \
      -m hashlimit --hashlimit-above 60/second --hashlimit-burst 30 \
      --hashlimit-mode srcip --hashlimit-name mc-bedrock-flood -j DROP

    # factorio: cap packet rate per source IP (also blunts UDP
    # amplification/reflection abuse of this port)
    iptables -t raw -A vps-ratelimit -p udp --dport 34197 \
      -m hashlimit --hashlimit-above 60/second --hashlimit-burst 30 \
      --hashlimit-mode srcip --hashlimit-name factorio-flood -j DROP
  '';

  # profiles/default.nix sets useRoutingFeatures = "both" for every
  # host, which forces net.ipv{4,6}.conf.all.forwarding = true at a
  # priority that beats a plain sysctl override — needed on homelab
  # (subnet router + exit node) but not here: this box only uses
  # tailscale for admin SSH, never as an exit node/subnet router.
  # Narrowing to "client" here stops that forced-on IPv6 forwarding
  # (IPv4 forwarding stays on regardless, via the nat module — that
  # one's intentional, it's what makes the homelab DNAT work).
  services.tailscale.useRoutingFeatures = lib.mkForce "client";

  # this box never needs to forward IPv6 (nat/forwardPorts above is
  # IPv4-only, and minecraft/factorio are only reachable via the IPv4
  # DNAT rules) — explicit off rather than relying on the kernel
  # default, so there's no ambient IPv6 forwarding path to homelab.
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = false;

  # anubis: proof-of-work challenge in front of jellyfin, absorbing bot/
  # scraper noise before it reaches caddy's backend at all.
  services.anubis.instances.jellyfin = {
    enable = true;
    settings = {
      TARGET = "http://10.100.0.2:8096";
    };
  };

  # caddy: public HTTPS entry point. jellyfin routes through anubis
  # first; minecraft/factorio are raw TCP/UDP and can't go through
  # caddy at all, so they're forwarded directly below instead.
  # `vars.domain` is the single source of truth for the public domain
  # (also consumed by services/octodns.nix) — see flake.nix's `vars`.
  sops.secrets.vps_caddy_env = { }; # TODO: populate with DNS provider API token if using DNS-01 challenges
  services.caddy = {
    enable = true;
    virtualHosts = {
      "jellyfin.${lib.removeSuffix "." vars.domain}".extraConfig = ''
        header {
          Strict-Transport-Security "max-age=31536000"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "SAMEORIGIN"
          Referrer-Policy "strict-origin-when-cross-origin"
          Permissions-Policy "camera=(), microphone=(), geolocation=()"
        }
        reverse_proxy unix//run/anubis/anubis-jellyfin/anubis.sock
      '';
    };
  };

  # crowdsec: watches sshd/caddy logs, bans abusive IPs locally and
  # pulls in community threat-intel blocklists via the firewall bouncer.
  # Complements anubis rather than duplicating it — anubis filters by
  # request behavior regardless of source IP, crowdsec bans by source
  # IP regardless of request shape.
  services.crowdsec = {
    enable = true;
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
        labels.type = "caddy";
      }
    ];
  };
  services.crowdsec-firewall-bouncer.enable = true;

  # failed-unit / stuck-switch alerts to the same Discord channel as
  # homelab. ZFS/SMART checks are off — this box has no ZFS pools and
  # no real block devices to check (single virtio disk).
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

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    51820 # wireguard
  ];
}

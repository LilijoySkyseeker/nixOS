{
  config,
  lib,
  vars,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    ../../profiles/default.nix
  ];

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Define your hostname.
  networking.hostName = "vps";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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
    settings.KbdInteractiveAuthentication = false;
    extraConfig = ''
      passwordAuthentication = no
      PermitRootLogin = prohibit-password
      X11Forwarding no
      AllowAgentForwarding no
      AuthenticationMethods publickey
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

  # sops age key derived from this host's own ssh host key, same pattern
  # as the other hosts (see profiles/server.nix). This host's age public
  # key (`nix run nixpkgs#ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`)
  # needs to be added to .sops.yaml's creation_rules before any
  # sops.secrets below will decrypt — see README.md.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # wireguard: this box is the public-facing tunnel endpoint; homelab
  # (behind CGNAT) dials out to it. allowedIPs restricts the tunnel to
  # a single homelab peer since nothing else should ride this link.
  sops.secrets.vps_wireguard_private_key = { };
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets.vps_wireguard_private_key.path;
    peers = [
      {
        # homelab
        publicKey = "REPLACE_WITH_HOMELAB_WIREGUARD_PUBLIC_KEY";
        allowedIPs = [ "10.100.0.2/32" ];
      }
    ];
  };

  # forward the game server ports straight through to homelab over the
  # tunnel — these are raw TCP/UDP, not HTTP, so caddy can't front them.
  networking.nat = {
    enable = true;
    externalInterface = "eth0"; # TODO: confirm against the provider's actual public interface name
    forwardPorts = [
      {
        destination = "10.100.0.2:25565";
        proto = "tcp";
        sourcePort = 25565;
      }
      {
        destination = "10.100.0.2:34197";
        proto = "udp";
        sourcePort = 34197;
      }
    ];
  };

  # anubis: proof-of-work challenge in front of jellyfin, absorbing bot/
  # scraper noise before it reaches caddy's backend at all. copyparty is
  # deliberately not fronted here or in caddy below — it stays homelab/
  # tailnet-only and is never exposed publicly.
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

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    51820 # wireguard
  ];
}

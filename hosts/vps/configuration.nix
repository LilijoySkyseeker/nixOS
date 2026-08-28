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
  # DigitalOcean's public NIC is NOT DHCP -- it requires the static address
  # cloud-init reads from the ConfigDrive datasource. cloud-init's NixOS
  # module always renders that as systemd-networkd units (system_info.network.renderers
  # defaults to [ "networkd" ], hardcoded upstream), so networkd has to be the
  # one actually managing interfaces or nothing ever consumes that config.
  # Confirmed via a rescue-ISO journal read: with useNetworkd unset (scripted
  # dhcpcd networking), dhcpcd did its own blind DHCP on the public NIC, got
  # no lease (DO doesn't run DHCP on that network), and fell back to a
  # self-assigned 169.254.x.x link-local address -- box never actually bound
  # its real IP despite cloud-init having read the correct static config.
  # Per nixpkgs's own networking module docs: running
  # systemd.network.enable = true (which services.cloud-init.network.enable
  # below turns on) together with useDHCP = true and useNetworkd = false
  # "can cause both networkd and dhcpcd to manage the same interfaces...
  # loss of networking" -- exactly this bug. useDHCP is disabled here since
  # cloud-init's rendered units already carry the static addresses/routes;
  # letting NixOS also generate a DHCP-enabled unit for the same interface
  # would just recreate the same race.
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
  # cloud-init's own package ships a 05_logging.cfg default (console at
  # WARNING, full DEBUG to /var/log/cloud-init.log) but NixOS's cloud-init
  # module doesn't install it, and all four cloud-init systemd units are
  # StandardOutput=journal+console -- so with no logging config at all,
  # cloud-init falls back to a much noisier default and every DEBUG line
  # (hundreds per boot) gets echoed straight to the console, which is what
  # DigitalOcean's web console showed during a live reinstall. Installing
  # the upstream package's own default here (verbatim, from
  # <cloud-init pkg>/lib/python3.14/site-packages/etc/cloud/cloud.cfg.d/05_logging.cfg)
  # keeps full detail in the log file without spamming the console.
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
  # cloud-init writes DigitalOcean's vendor-data boothook script under
  # /var/lib/cloud and execs it directly -- root's tmpfs noexec above
  # broke this with a bare PermissionError on the real droplet (confirmed
  # via a rescue-ISO journal read: cloud-init's datasource activation
  # succeeded fine, only the boothook exec failed), which in turn seems
  # to be what actually arms DigitalOcean's network for this NIC (see the
  # services.cloud-init comment below) -- so the box never came up at
  # all on its first real boot. Give this one path its own exec-capable
  # tmpfs rather than loosening root itself.
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
      # fail2ban's ban-history db (fail2ban.sqlite3) — without this, progressive
      # ban tracking (bantime-increment) resets to first-offense duration every
      # reboot. Runs as root (no DynamicUser), so no user/group/mode needed.
      "/var/lib/fail2ban"
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
        sourcePort = 34197; # factorio
      }
    ];
  };

  # SNAT forwarded traffic to our wg0 IP so source IP's are preserved
  networking.firewall.extraCommands = ''
    iptables -t nat -C POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1 2>/dev/null \
      || iptables -t nat -A POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1

    # NOTE: the two `ipset create` calls that used to live here have moved
    # to systemd.services.crowdsec-ipset-precreate below (F-P2-02). They
    # must not run in this script — see that unit's comment for why an
    # `ipset` failure here took the whole packet filter down, fail-open.

    # per-source-IP rate limiting on forwarded game ports (DNAT bypasses anubis/crowdsec)
    iptables -t raw -N vps-ratelimit 2>/dev/null || iptables -t raw -F vps-ratelimit
    iptables -t raw -C PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null \
      || iptables -t raw -I PREROUTING -i ${externalInterface} -j vps-ratelimit

    # apply CrowdSec's existing ban list (built from sshd/caddy scenarios) to DNAT'd game
    # traffic too — it never reaches INPUT/CROWDSEC_CHAIN, so this reuses the bouncer's own
    # ipset instead of duplicating ban logic. Must come first in the chain: banned IPs get
    # dropped before spending any hashlimit budget below.
    # `|| true` is load-bearing: this rule fails with "Set ... doesn't exist"
    # if the pre-create unit did not run or failed, and an unguarded failure
    # here aborts the firewall script before it arms the filter (F-P2-02).
    # Degrading the ban layer is survivable; losing the firewall is not.
    iptables -t raw -A vps-ratelimit -m set --match-set crowdsec-blacklists-0 src -j DROP || true

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

    # base rate limit for caddy's public HTTP(S) entry (80/443)
    iptables -t raw -A vps-ratelimit -p tcp -m multiport --dports 80,443 --syn \
      -m hashlimit --hashlimit-above 120/minute --hashlimit-burst 60 \
      --hashlimit-mode srcip --hashlimit-name http-new -j DROP

    # IPv6 counterpart of the above: caddy already accepts real IPv6 traffic
    # today (apex + jellyfin CNAME both carry AAAA records, native on this
    # box — no forwarding involved), but until now that traffic skipped this
    # whole raw-table rate-limit layer entirely since it was iptables-only.
    # CrowdSec's own INPUT-chain bans are already dual-stack (confirmed live:
    # ip6tables' CROWDSEC_CHAIN matches against a separate crowdsec6-blacklists
    # ipset the bouncer maintains automatically), this just closes the gap for
    # the pre-CrowdSec burst/flood layer. Game ports are deliberately not
    # mirrored here — they're still IPv4-only (see
    # 2026-08-18-add-ipv6-support-for-the-vps-s-forwarded-game-port.md).
    # (crowdsec6-blacklists-0 is pre-created by the same unit as its v4 twin)
    ip6tables -t raw -N vps-ratelimit 2>/dev/null || ip6tables -t raw -F vps-ratelimit
    ip6tables -t raw -C PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null \
      || ip6tables -t raw -I PREROUTING -i ${externalInterface} -j vps-ratelimit

    # same reasoning as the v4 rule above: fail soft, never take the filter down
    ip6tables -t raw -A vps-ratelimit -m set --match-set crowdsec6-blacklists-0 src -j DROP || true

    ip6tables -t raw -A vps-ratelimit -p tcp -m multiport --dports 80,443 --syn \
      -m hashlimit --hashlimit-above 120/minute --hashlimit-burst 60 \
      --hashlimit-mode srcip --hashlimit-name http-new6 -j DROP
  '';

  # Tear down the raw-table chain this host adds in extraCommands above.
  #
  # The NixOS firewall's own stop path only reaches the nat and filter tables
  # (extraStopCommands is non-empty already, but it is the nat module's
  # flushNat), so without this the vps-ratelimit chain and its PREROUTING
  # jump survive `systemctl stop firewall` (F-P2-02). Two consequences, both
  # bad in a debugging session: raw-table DROP rules keep applying on a box
  # you believe you have just unfirewalled, and the chain persists across a
  # parameter change rather than being rebuilt from scratch.
  #
  # Every line is guarded. extraStopCommands is spliced into a `-e` script
  # exactly like extraCommands is, and a stop path that aborts halfway
  # through leaves a *partially* torn-down firewall, which is worse than one
  # that skips a rule it could not find.
  networking.firewall.extraStopCommands = ''
    iptables -t raw -D PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null || true
    iptables -t raw -F vps-ratelimit 2>/dev/null || true
    iptables -t raw -X vps-ratelimit 2>/dev/null || true
    ip6tables -t raw -D PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null || true
    ip6tables -t raw -F vps-ratelimit 2>/dev/null || true
    ip6tables -t raw -X vps-ratelimit 2>/dev/null || true
  '';

  # Pre-create CrowdSec's ipsets, out of the firewall's own start script.
  #
  # These two `ipset create` calls used to sit in
  # networking.firewall.extraCommands, which was fail-OPEN on the one
  # internet-facing host in the fleet (F-P2-02). NixOS renders the firewall
  # start script with `#! ${runtimeShell} -e` and splices extraCommands in
  # *immediately before* the `ip46tables -A INPUT -j nixos-fw` that actually
  # arms the filter. Any non-zero exit in between and that jump is never
  # installed: no INPUT filtering at all. On a reload it is worse, because
  # reloadScript falls back to stopScript, which removes the jump and the
  # rpfilter hook outright. sshd binds 0.0.0.0:22 here and the packet filter
  # is the *only* thing keeping port 22 off the public internet
  # (services.openssh.openFirewall = false is not an sshd setting), so the
  # blast radius of one failed `ipset create` was OpenSSH pre-auth exposed
  # to the internet, plus the loss of the rate limiter and the DNAT rules.
  #
  # `-exist` does not save it. ipset(8) only suppresses the error when the
  # setname *and the create parameters* are identical, and those parameters
  # are pinned by nothing: nixpkgs' crowdsec-firewall-bouncer module sets
  # only the set names, and ipset_type/ipset_size/timeouts/the -N suffix all
  # come from cs-firewall-bouncer's own defaults. A nixpkgs bump that moves
  # that package -- or one ipset made by hand while troubleshooting -- turned
  # the next firewall reload into a total loss of the firewall. (Checked live
  # 2026-08-27: the running sets do still match these parameters exactly.)
  #
  # As its own unit, that failure is contained *and* visible: the firewall
  # comes up regardless, and this lands in `systemctl --failed`, which
  # myHealthAlerts already pages on. That visibility is the reason this is a
  # unit rather than just `|| true` on the original lines -- `|| true` alone
  # would have made the firewall succeed silently and told nobody the ban
  # layer had gone missing.
  #
  # Deliberately ordered Before= firewall.service but NOT RequiredBy/PartOf
  # it: the firewall must never be able to fail because of this. Before= only
  # orders the two when both are already in the same transaction, which they
  # are at boot via multi-user.target.
  systemd.services.crowdsec-ipset-precreate = {
    description = "Pre-create CrowdSec's ipsets before the firewall references them";
    before = [ "firewall.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "crowdsec-ipset-precreate" ''
        set -eu
        ipset=${pkgs.ipset}/bin/ipset
        "$ipset" create -exist crowdsec-blacklists-0 hash:net family inet \
          hashsize 1024 maxelem 131072 timeout 300
        "$ipset" create -exist crowdsec6-blacklists-0 hash:net family inet6 \
          hashsize 1024 maxelem 131072 timeout 300
      '';
      # ipset speaks netlink to netfilter; CAP_NET_ADMIN is the whole need.
      AmbientCapabilities = [ "CAP_NET_ADMIN" ];
      CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      # ProtectKernelModules is safe here only because the modules are
      # declared in boot.kernelModules below. Creating a hash:net set
      # otherwise relies on the kernel autoloading ip_set_hash_net at
      # create time, which is exactly the kind of implicit dependency that
      # should not sit between this host and a working packet filter.
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      PrivateTmp = true;
    };
  };
  # Load ipset's modules at boot rather than relying on autoload from inside
  # the sandboxed unit above. Names confirmed against the live host
  # (`lsmod`): ip_set is the core, ip_set_hash_net backs the hash:net type
  # both CrowdSec sets use.
  boot.kernelModules = [
    "ip_set"
    "ip_set_hash_net"
  ];

  # tailscale routing: nothing needed here any more. This box isn't an exit
  # node or a subnet router, and "client" is now the fleet-wide default in
  # modules/profiles/default.nix rather than something each host has to
  # remember to opt out of -- so the mkForce override that used to sit here
  # is redundant. homelab is the only host that overrides it, in the other
  # direction.

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
  # caddy needs group membership to reverse_proxy into anubis's unix socket
  users.users.caddy.extraGroups = [ "anubis" ];
  # anubis's "anubis" group is transient (DynamicUser = true): it only exists
  # while anubis-jellyfin.service is active. Without this ordering, a boot
  # where caddy starts first spawns caddy before that group exists, so
  # caddy's supplementary-group resolution misses it entirely and every
  # request 502s with "permission denied" on the anubis socket until the
  # next caddy restart. Seen live 2026-08-18/2026-08-21 right after reboots.
  systemd.services.caddy.after = [ "anubis-jellyfin.service" ];
  systemd.services.caddy.wants = [ "anubis-jellyfin.service" ];
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
    # progressive bans for CrowdSec's own scenario-detected decisions (sshd/caddy):
    # each repeat offense (by decision-history count for that IP/range, all-time,
    # not just currently-active bans) roughly quadruples the ban duration off the
    # module's stock 4h default — 4h, 16h, ~2.7d, ~10.7d, ~42.7d, then capped —
    # rather than literal-forever, since a shared/dynamic IP (residential ISP
    # reassignment, CGNAT, VPN exit) can hand off to an unrelated user later.
    # This is CrowdSec's own module default profile pair, reproduced verbatim
    # (services.crowdsec.localConfig.profiles has no merge semantics — setting it
    # replaces the default, so both scopes must be repeated here) plus duration_expr.
    # NOTE: only applies to CrowdSec's own alert->profile pipeline; `cscli decisions
    # add` (fail2ban's cscli.conf action, below) bypasses profile evaluation
    # entirely — verified against crowdsec's own apiserver source, see
    # 2026-08-25-add-fail2ban-to-vps-defaulting-to-an-immediate-ban.md.
    localConfig.profiles = [
      {
        name = "default_ip_remediation";
        filters = [ "Alert.Remediation == true && Alert.GetScope() == 'Ip'" ];
        decisions = [
          {
            type = "ban";
            duration = "4h"; # fallback if duration_expr fails to evaluate/parse
          }
        ];
        duration_expr = "Sprintf('%dh', int(min(4 ** (GetDecisionsCount(Alert.GetValue()) + 1), 2160)))"; # cap 2160h = 90d
        on_success = "break";
      }
      {
        name = "default_range_remediation";
        filters = [ "Alert.Remediation == true && Alert.GetScope() == 'Range'" ];
        decisions = [
          {
            type = "ban";
            duration = "4h";
          }
        ];
        duration_expr = "Sprintf('%dh', int(min(4 ** (GetDecisionsCount(Alert.GetValue()) + 1), 2160)))";
        on_success = "break";
      }
    ];
  };
  services.crowdsec-firewall-bouncer.enable = true;
  # boot-race fix: this droplet's network intermittently takes longer to actually
  # pass traffic than network-online.target reports ready — DigitalOcean's
  # hypervisor vNIC arming lags behind the guest's own DHCP lease acquisition (see
  # the externalInterface comment above), so anything doing a network call at
  # startup can lose this race. Confirmed live across two separate reboots: both
  # crowdsec.service (its ExecStartPre's `cscli hub update`) and
  # crowdsec-firewall-bouncer.service failed with a DNS resolution error at
  # ~90s into userspace boot — identically, down to the second, both times — and
  # neither ever retried for the rest of that boot session. crowdsec.service
  # already sets RestartSec=60 upstream but never sets Restart=, an incomplete
  # no-op left in nixpkgs' own crowdsec.nix; crowdsec-firewall-bouncer.service has
  # no restart policy at all.
  systemd.services.crowdsec.serviceConfig.Restart = "on-failure";
  systemd.services.crowdsec-firewall-bouncer.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "15s";
  };
  # tailscaled-autoconnect polls internally until tailscale reports Running, but
  # systemd's default 90s unit-start timeout was killing it before that could
  # happen on a slow boot — also confirmed live, twice, at the same ~90s mark.
  systemd.services.tailscaled-autoconnect.serviceConfig.TimeoutStartSec = "300s";
  # self-ban prevention: exempt the tailnet (100.64.0.0/10) from every CrowdSec
  # decision. SSH here is tailscale-only (no public port 22), so anything that
  # reconnects quickly enough — scripted health checks, this repo's own deploy
  # tooling, a burst of manual troubleshooting — can trip crowdsecurity/sshd's
  # ssh-slow-bf scenario against itself and get banned by the same mechanism
  # meant for internet attackers. Confirmed live 2026-08-26: rapid diagnostic
  # SSH during this PR's own testing did exactly that to the admin's own IP.
  # Not a new trust boundary — networking.firewall.trustedInterfaces above
  # already treats tailscale0 as trusted at the packet-filter level; this
  # extends the same boundary to CrowdSec's decision engine. The actual access
  # gate stays tailscale's own device authorization (ACLs/key approval) — only
  # devices explicitly added to the tailnet can ever present a 100.64.0.0/10
  # source — and sshd is publickey-only regardless, so there's no password to
  # brute-force from inside the mesh even if this exemption were ever abused.
  # `cscli allowlists create` errors (not just warns) if the name already
  # exists, unlike `add` (which just warns and skips already-present values —
  # confirmed in crowdsec's own cliallowlists/allowlists.go), hence `|| true`
  # only on the create step.
  systemd.services.crowdsec-allowlist-tailnet = {
    description = "Exempt the tailnet from CrowdSec decisions";
    after = [ "crowdsec.service" ];
    requires = [ "crowdsec.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "15s";

      # This was the one custom unit in the repo running as unsandboxed
      # root, on the internet-facing host (F-P2-08). Root is not required:
      # the script reads /etc/crowdsec/config.yaml (a symlink into the
      # world-readable store, per the tmpfiles rule below) and talks to
      # the LAPI using /var/lib/crowdsec/local_api_credentials.yaml, which
      # is crowdsec-owned. services.crowdsec.user is a real static system
      # user, not a DynamicUser-only name, so User= can simply be set.
      User = config.services.crowdsec.user;
      Group = config.services.crowdsec.group;

      # ReadWritePaths is a deliberate departure from F-P2-08's proposed
      # fix, which claimed strict needs none because "the allowlist lives
      # in CrowdSec's own database via the LAPI". Two pieces of evidence
      # say otherwise, and the cost of being wrong here is that the
      # tailnet exemption silently stops applying and CrowdSec starts
      # banning the admin's own IP -- which is exactly what prompted this
      # unit in the first place:
      #   - crowdsec-firewall-bouncer-register just below carries the
      #     comment "cscli needs to write /var/lib/crowdsec", and grants
      #     precisely that.
      #   - the live state dir on vps holds a SQLite crowdsec.db
      #     (/var/lib/crowdsec/state/crowdsec.db, 0640 crowdsec:crowdsec),
      #     and cscli reaches the database directly for several
      #     subcommands rather than going through the LAPI.
      # Granting it is strictly safer than omitting it: if cscli turns out
      # not to need the write, nothing is lost.
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/crowdsec" ];

      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      PrivateTmp = true;
      CapabilityBoundingSet = [ "" ];

      ExecStart = pkgs.writeShellScript "crowdsec-allowlist-tailnet" ''
        set -eu
        cscli=${config.services.crowdsec.package}/bin/cscli
        "$cscli" allowlists create trusted-tailnet -d "tailscale mesh, exempt from ban decisions" || true
        "$cscli" allowlists add trusted-tailnet 100.64.0.0/10 -d "tailnet CGNAT range"
      '';
    };
  };
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

  # fail2ban: complements CrowdSec's scenario-based detection with a zero-threshold
  # layer for probes against ports/services vps doesn't actually offer — "nothing
  # legitimate lives here", so ban on first sight instead of after a failure count.
  # Bans go through CrowdSec's own decision list (cscli), not fail2ban's default
  # iptables action, so this stays a second detector feeding one unified ban list/
  # ipset — the same one the DNAT'd game ports already consult (see vps-ratelimit
  # above) — rather than a second independent ban mechanism on the box.
  services.fail2ban = {
    enable = true;
    # progressive bans: fail2ban's own repeat-offender tracking (per source IP,
    # keyed off ban history in its sqlite db — persisted above, see /var/lib/fail2ban).
    # multipliers is a fixed lookup table applied against each jail's *static*
    # configured bantime (bantime * factor * multipliers[priorBanCount], not
    # compounding on the previous ban's duration — verified in fail2ban's own
    # jail.py) — deliberately powers-of-4 to reproduce, ban-for-ban, the exact
    # same curve as CrowdSec's duration_expr below (both start from a 4h base):
    # 4h, 16h, 64h, 256h, 1024h, then capped — same cap too, for the same
    # shared/dynamic-IP reason (residential ISP reassignment, CGNAT, VPN exit).
    bantime-increment = {
      enable = true;
      multipliers = "1 4 16 64 256 1024";
      maxtime = "90d";
    };
    # SSH brute-force is already CrowdSec's job (crowdsecurity/sshd scenario against
    # sshd.service's journal) — leave the module's auto-added default jail off so
    # the same threat isn't judged by two uncoordinated detectors.
    jails.sshd.enabled = false;

    jails.vps-closed-port-scan = {
      # networking.firewall.logRefusedConnections logs refused TCP SYNs to the
      # kernel log with this prefix — CrowdSec never sees these, its acquisitions
      # only read the sshd/caddy journal units, never kernel logs.
      filter.Definition = {
        failregex = ''^refused connection: .*\sSRC=<HOST>\s'';
        ignoreregex = "";
      };
      settings = {
        journalmatch = "_TRANSPORT=kernel";
        # any hit here is a probe of a port vps doesn't listen on — no legitimate
        # traffic can trigger this filter, so ban on the very first match
        findtime = "1d";
        maxretry = 1;
        # base for bantime-increment's multiplier table above — matches
        # CrowdSec's duration_expr base so both curves line up exactly
        bantime = "4h";
        action = "cscli";
      };
    };
  };
  # custom action: bans via `cscli decisions add` instead of fail2ban's own
  # iptables rules, so this jail's bans land in CrowdSec's decision list/ipset
  environment.etc."fail2ban/action.d/cscli.conf".text = ''
    [Definition]
    actionban = ${config.services.crowdsec.package}/bin/cscli decisions add --ip <ip> --duration <bantime>s --reason "fail2ban-<name>" --type ban
    actionunban = ${config.services.crowdsec.package}/bin/cscli decisions delete --ip <ip>
  '';

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
    # This host does not deploy itself — homelab builds its closure and
    # pushes it (myPushDeploy). So "homelab silently stopped updating me" is
    # invisible from here *and* from homelab, whose push-deploy-vps exits 0
    # when a guard defers it. The profile symlink's mtime is the one signal
    # that lives on the right side of that link: it only advances when this
    # host actually got activated.
    #
    # This is not hypothetical. push-deploy-vps failed on 2026-08-25 (the
    # vps-deploy forced-command allowlist rejected its `stat`) and again on
    # 2026-08-27 (read-only git config); the second entered systemctl
    # --failed on homelab, but a run the *guards* skip never would.
    #
    # 504h = 21 days, matching homelab's own entry — dates is weekly and
    # minSwitchInterval is 7 days, giving a 14-day normal ceiling plus one
    # deferral of slack.
    staleMarkerFiles = {
      "/nix/var/nix/profiles/system" = 504;
    };
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

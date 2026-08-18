{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  # Confirmed via the real droplet's `ip a` + DO metadata service
  # (/metadata/v1.json, matched by MAC): ens4 is the public interface
  # (137.184.45.18/20, gw 137.184.32.1), ens3 is the private/internal
  # one (10.124.0.2/20, gw 10.124.0.1). DigitalOcean droplet NICs do
  # NOT serve real DHCP (confirmed: NetworkManager sat in
  # "connecting (getting IP configuration)" forever, 45s DHCP timeouts,
  # never a DHCPOFFER) — nixos-infect works around this the same way,
  # by hardcoding the static address/gateway pair instead of relying
  # on DHCP. See networking config below.
  externalInterface = "ens4";

  # Forced SSH command for the vps-deploy automation user (see below) —
  # only three exact command shapes are let through; everything else is
  # rejected. This allowlist, not the polkit grant it relies on, is the
  # real security boundary: it's what stops a compromised deploy key
  # from doing anything beyond "copy in and activate this exact
  # system's closure, or reboot".
  #
  # The activate case matches nixos-rebuild's own `--elevate=run0`
  # remote invocation, derived from nixos-rebuild-ng's source
  # (elevate.py's Run0Elevator + nix.py's SWITCH_TO_CONFIGURATION_CMD_
  # PREFIX — the switch-to-configuration call is itself wrapped in an
  # inner systemd-run for unit isolation, then that whole thing is
  # wrapped again in the outer uid=0 systemd-run for elevation). Worth
  # a live smoke test the first time push-deploy actually runs, since
  # this was derived from source rather than captured empirically.
  vpsDeployDispatcher = pkgs.writeShellScript "vps-deploy-dispatcher" ''
    set -eu
    cmd=$SSH_ORIGINAL_COMMAND

    case "$cmd" in
      "nix-store --serve --write")
        exec nix-store --serve --write
        ;;
    esac

    # nixos-rebuild's pre-activation sanity check ("does this closure
    # look like a real NixOS system") — confirmed live, this is a
    # separate remote command nixos-rebuild issues before the actual
    # activation command below. Read-only stat, no side effects;
    # restricted to this system's own store paths same as activation.
    case "$cmd" in
      *"test -f /nix/store/"*"-nixos-system-vps-"*"/nixos-version")
        exec /bin/sh -c "$cmd"
        ;;
    esac

    # nixos-rebuild's own "is systemd actually running" check —
    # confirmed live, it precedes the activation command and (since our
    # dispatcher was rejecting it) caused nixos-rebuild to infer
    # systemd wasn't running and send a simpler activation form without
    # the inner isolation wrapper the "real" (systemd-running) path
    # uses. Read-only stat, no side effects.
    case "$cmd" in
      *"test -d /run/systemd/system")
        exec /bin/sh -c "$cmd"
        ;;
    esac

    # nixos-rebuild's run0-elevated `nix-env --set` step, updating the
    # system profile to point at the new generation — confirmed live,
    # another separate remote command issued before the actual
    # activation command below. Restricted to this system's own store
    # paths and the standard system profile path, same as elsewhere.
    case "$cmd" in
      *"systemd-run --uid=0 --pipe --quiet --wait --collect --service-type=exec --send-sighup"*)
        case "$cmd" in
          *"nix-env -p /nix/var/nix/profiles/system --set /nix/store/"*"-nixos-system-vps-"*)
            exec /bin/sh -c "$cmd"
            ;;
        esac
        ;;
    esac

    # nixos-rebuild's run0-elevated switch-to-configuration invocation
    # — validate both the elevation wrapper shape and that the actual
    # target path is this system's own store path before allowing it.
    # nixos-rebuild sends this with or without an inner isolation
    # wrapper (--unit=nixos-rebuild-switch-to-configuration) depending
    # on whether its own "is systemd running" check succeeds — match
    # both forms rather than assuming one.
    case "$cmd" in
      *"systemd-run --uid=0 --pipe --quiet --wait --collect --service-type=exec --send-sighup"*)
        case "$cmd" in
          *"/nix/store/"*"-nixos-system-vps-"*"/bin/switch-to-configuration switch")
            exec /bin/sh -c "$cmd"
            ;;
        esac
        ;;
    esac

    # our own reboot-if-kernel-changed trigger (constructed by
    # myPushDeploy on homelab, using the exact same elevation shape so
    # it goes through the same polkit grant) — we fully control this
    # string ourselves, so it's matched exactly.
    if [ "$cmd" = "systemd-run --uid=0 --pipe --quiet --wait --collect --service-type=exec --send-sighup -- systemctl reboot" ]; then
      exec /bin/sh -c "$cmd"
    fi

    echo "vps-deploy: rejected command: $cmd" >&2
    exit 1
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    ../../profiles/default.nix
    ../../profiles/server.nix

    ../../modules/nixos/health-alerts.nix
  ];

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Define your hostname.
  networking.hostName = "vps";

  # DigitalOcean's hypervisor virtual switch apparently needs cloud-init
  # to run and "register"/arm the droplet's network before it'll pass
  # any traffic for that NIC — confirmed by an identical symptom fixed
  # this exact way in nix-community/nixos-anywhere-examples#5 (nixos-
  # anywhere-installed DO droplet: interfaces up, completely
  # unreachable, no ping even to the gateway) via
  # nixos-anywhere-examples#6/#10 (adding services.cloud-init with the
  # ConfigDrive datasource). We independently hit the same class of
  # symptom two ways: plain DHCP (NetworkManager stuck "connecting",
  # repeated 45s timeouts, no DHCPOFFER ever) and hardcoded static IPs
  # (ip neigh show stuck INCOMPLETE — ARP requests to the gateway went
  # out, TX counters increased, but nothing ever came back, on both the
  # public and private interfaces). Neither approach alone completes
  # whatever handshake DO's hypervisor expects; cloud-init is what
  # normally performs it on their stock images. DHCP is real and
  # documented to work on DO once cloud-init is running (see also
  # nixpkgs' own digital-ocean-image.nix, which avoids cloud-init but
  # only for fresh custom-image boots, not an in-place kexec conversion
  # of an already-running droplet like ours).
  networking.networkmanager.enable = lib.mkForce false;
  networking.useDHCP = lib.mkDefault true;
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [ "ConfigDrive" ];
      datasource.ConfigDrive = { };
      # We only need cloud-init for whatever handshake DO's hypervisor
      # requires to actually pass traffic — not for its usual
      # config-management role, which fights this host's declarative,
      # read-only /etc. Confirmed live: cc_set_passwords/cc_ssh tried
      # (and mostly failed, harmlessly, on read-only writes) to rewrite
      # sshd_config, delete/regenerate our real persisted SSH host key,
      # and overwrite root's authorized_keys — any of those succeeding
      # would be a real problem. Also stops cc_update_hostname from
      # clobbering networking.hostName with the droplet's stock name.
      cloud_init_modules = [ "seed_random" ];
      cloud_config_modules = [ ];
      cloud_final_modules = [ ];
      preserve_hostname = true;
    };
  };

  # This host no longer builds/pulls its own updates (myPullDeploy,
  # removed) — a from-scratch local build peaked at ~1.7GB RAM + 424MB
  # swap (measured live, 2026-08-18), too close to this droplet's ~2GB
  # ceiling to keep doing on-box. homelab now builds and pushes
  # finished closures here instead (myPushDeploy, hosts/homelab
  # configuration.nix) via the vps-deploy user below. See
  # TODO-vps-manual-steps.md.

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
      # "/etc/nixos" no longer needed — this host doesn't have its own
      # local flake checkout anymore (myPullDeploy removed, see above).
      "/var/log"
      "/var/lib/nixos" # avoids uid/gid complaints on reboot
      "/var/lib/tailscale" # node identity/state; without this, a non-reusable
      # authKeyFile is consumed on first boot then fails every boot after
      "/var/lib/caddy" # ACME certs — avoids re-requesting from Let's Encrypt every reboot
      # plain-string persisted directories are created root-owned by
      # impermanence's activation script; crowdsec runs as its own
      # system user and needs to write its local-API credentials file
      # here (confirmed live: "permission denied" writing
      # local_api_credentials.yaml until this ownership was set).
      {
        directory = "/var/lib/crowdsec";
        user = "crowdsec";
        group = "crowdsec";
        mode = "0750";
      }
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

  # push-deploy: homelab (not vps itself) builds+activates this host's
  # config, since a from-scratch build/eval on this box's own RAM peaked
  # at ~1.7GB used + ~424MB swap out of ~2GB total (measured live,
  # 2026-08-18) — too close to the edge to safely downsize the droplet
  # while myPullDeploy built locally here. See
  # TODO-vps-manual-steps.md's "offload vps rebuilds off-box" section.
  #
  # Dedicated, unprivileged, single-purpose account for that automation
  # — never root, never interactive. Its SSH key is locked to a forced
  # command (see authorizedKeys below) that only allows exactly three
  # things: copying the built closure in (`nix-store --serve --write`),
  # activating it (`switch-to-configuration switch`, elevated via
  # nixos-rebuild's polkit-based `run0` backend — NOT sudo, see the
  # polkit rule below), and rebooting if the switch changed the kernel.
  # That forced-command allowlist — not the polkit grant, which is
  # necessarily coarse since systemd-run's transient unit names aren't
  # predictable — is the actual security boundary here.
  users.users.vps-deploy = {
    isSystemUser = true;
    group = "vps-deploy";
    # sshd execs forced commands via `<user's shell> -c <command>` — a
    # real shell is required for this to work at all. nologin was tried
    # here first and was a genuine bug: since nologin doesn't understand
    # -c, it just printed its fixed refusal message for every
    # connection regardless of the forced command (confirmed live via
    # `EXECVE a0="nologin" a1="-c" a2="<dispatcher>"` in the audit log —
    # sshd invoked our dispatcher correctly, nologin just couldn't run
    # it). The actual restriction has always come from the
    # authorized_keys command=/restrict below, not from the shell —
    # this account has no interactive access regardless of what shell
    # is configured, since the SSH key itself can never request
    # anything other than the forced command.
    shell = "${pkgs.bash}/bin/bash";
    openssh.authorizedKeys.keys = [
      # dedicated homelab->vps push-deploy key (not the personal admin
      # key in vars.publicSshKeys) — private half is
      # sops.secrets.homelab_vps_deploy_key on homelab.
      "command=\"${vpsDeployDispatcher}\",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINDGczUoWFSHuf+96aLLrGd+Eqkz5KTFY1gYbSaqJJFp homelab-vps-deploy"
    ];
  };
  users.groups.vps-deploy = { };

  # org.freedesktop.systemd1.manage-units lets vps-deploy start the
  # transient root unit nixos-rebuild's run0 elevator uses for
  # switch-to-configuration (and our own reboot trigger) — the only
  # privilege this user has. It's not scoped to a specific unit name
  # (systemd-run's transient units are randomly named), so the SSH
  # forced-command allowlist above is what actually limits what ends up
  # inside that unit.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "vps-deploy") {
        return polkit.Result.YES;
      }
    });
  '';

  # needed for the nix daemon to accept the closure vps-deploy copies in
  # via `nix-store --serve --write` without additional signing friction.
  nix.settings.trusted-users = [ "vps-deploy" ];
  services.openssh = {
    enable = true;
    # NixOS's openssh module defaults openFirewall to true, which adds a
    # global `dport 22 accept` firewall rule on every interface —
    # silently undermining the tailscale-only design below (confirmed
    # live: an external non-tailscale IP reached sshd's pre-auth stage
    # on the public interface). trustedInterfaces already covers
    # tailscale0; nothing needs port 22 opened elsewhere.
    openFirewall = false;
    allowSFTP = false;
    settings.KbdInteractiveAuthentication = false;
    # PasswordAuthentication used to be set via extraConfig below
    # ("passwordAuthentication = no") — a real, live bug: NixOS's
    # openssh module defaults `settings.PasswordAuthentication` to
    # true and renders it *before* extraConfig, and sshd_config uses
    # first-directive-wins, so that line was always silently
    # overridden and password auth was actually enabled this whole
    # time (confirmed live via the rendered /etc/ssh/sshd_config).
    # Setting it as a structured option instead actually takes effect.
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
    # The nixpkgs module defaults api.server.enable to false, which
    # means the agent has no local API to talk to at all — confirmed
    # live: crowdsec.service failed with "no API client section in
    # configuration" (api.client.credentials_path stayed null, since
    # the setup script only runs `cscli machine add --auto` when the
    # server is enabled). This also cascaded into both
    # crowdsec-firewall-bouncer* units failing, since bouncer
    # registration (`cscli bouncers add`) needs that same local API
    # running. We only need a local, single-box API here (this agent
    # watching its own logs) — no remote/central LAPI involved.
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
        labels.type = "caddy";
      }
    ];
  };
  services.crowdsec-firewall-bouncer.enable = true;
  # crowdsec-firewall-bouncer-register.service declares
  # StateDirectory = "crowdsec-firewall-bouncer-register crowdsec" —
  # that second entry has systemd itself try to take over
  # /var/lib/crowdsec via its DynamicUser private-directory mechanism,
  # which collides with our impermanence bind-mount already owning
  # that path (confirmed live: "Failed to set up special execution
  # directory in /var/lib: Device or resource busy"). The register
  # script only talks to the local API over cscli, it doesn't need
  # systemd-managed access to that directory, so drop it here.
  systemd.services.crowdsec-firewall-bouncer-register.serviceConfig = {
    StateDirectory = lib.mkForce "crowdsec-firewall-bouncer-register";
    # Dropping "crowdsec" from StateDirectory above avoids the
    # migration conflict, but this unit's ProtectSystem=strict (implied
    # by DynamicUser=true) then makes /var/lib/crowdsec read-only —
    # and `cscli bouncers list/add` touch crowdsec's sqlite db directly
    # even for reads (confirmed live: "unable to set perms on
    # .../crowdsec.db: chmod ...: read-only file system"). Grant write
    # access explicitly instead, which doesn't trigger StateDirectory's
    # ownership/migration semantics.
    ReadWritePaths = [ "/var/lib/crowdsec" ];
  };
  # crowdsec-firewall-bouncer-register.service's script calls the raw
  # crowdsec package's cscli directly (not services.crowdsec's own
  # `-c=<configFile>`-wrapped cscli), so it falls back to cscli's
  # hardcoded default path /etc/crowdsec/config.yaml, which
  # services.crowdsec never actually creates there (confirmed live:
  # "open /etc/crowdsec/config.yaml: no such file or directory"; the
  # real config only ever gets passed via -c to the Nix store path).
  # Symlink it into place ourselves, reproducing the exact same
  # generation services.crowdsec uses internally (pkgs.formats.yaml
  # on settings.general) so both stay in sync automatically.
  systemd.tmpfiles.rules = [
    "L+ /etc/crowdsec/config.yaml - - - - ${
      (pkgs.formats.yaml { }).generate "crowdsec.yaml" config.services.crowdsec.settings.general
    }"
  ];

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
  # profiles/default.nix enables smartd for every host; this box has no
  # real block devices for it to monitor (single virtio disk) — it was
  # failing to start rather than just idling, so disable it outright
  # instead of leaving it a permanently-failed unit.
  services.smartd.enable = lib.mkForce false;

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    51820 # wireguard
  ];

  # TEMPORARY: sizing data to decide whether this droplet's 1GB RAM plan
  # can be downsized, or whether it's actually needed (e.g. for
  # nixos-rebuild during myPullDeploy's Thu 03:00 window). Samples
  # free/swap every 30s to a persisted log — fine-grained enough to
  # catch a multi-minute rebuild spike. REMOVE once a sizing decision
  # is made; this isn't meant to run forever.
  systemd.services.mem-usage-monitor = {
    description = "Sample memory/swap usage periodically for VPS sizing";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "mem-usage-monitor" ''
        while true; do
          ${pkgs.procps}/bin/free -m | ${pkgs.gawk}/bin/awk -v ts="$(${pkgs.coreutils}/bin/date -Iseconds)" \
            'NR==2{mt=$2;mu=$3;mf=$4;ma=$7} NR==3{su=$3} END{
              printf "%s mem_total=%s mem_used=%s mem_free=%s mem_avail=%s swap_used=%s\n", ts, mt, mu, mf, ma, su
            }' >> /var/log/vps-mem-usage.log
          sleep 30
        done
      '';
      Restart = "always";
    };
  };
}

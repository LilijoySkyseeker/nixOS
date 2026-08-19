{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  # Re-confirmed live via `ip a`/`ip route` on the real droplet: ens3
  # carries the public IP (137.184.45.18/20, default route via
  # 137.184.32.1) and ens4 is the private VPC interface
  # (10.124.0.2/20) — the reverse of what an earlier comment here
  # claimed. That earlier ens3/ens4 swap silently broke the
  # DNAT/FORWARD/rate-limit rules below (all `-i ${externalInterface}`
  # scoped): Caddy's HTTP/HTTPS kept working since it listens
  # unscoped on all interfaces, masking the bug, but real external
  # traffic to the DNAT'd game ports (25565/19132/34197) never
  # matched `-i ens4` and silently vanished — confirmed live via 0
  # packets on every nixos-nat-pre/nixos-filter-forward/vps-ratelimit
  # counter no matter how many real connection attempts were made,
  # even after ruling out DigitalOcean's Cloud Firewall product
  # entirely (removed it, no change). DigitalOcean droplet NICs do
  # NOT serve real DHCP (confirmed: NetworkManager sat in
  # "connecting (getting IP configuration)" forever, 45s DHCP timeouts,
  # never a DHCPOFFER) — nixos-infect works around this the same way,
  # by hardcoding the static address/gateway pair instead of relying
  # on DHCP. See networking config below.
  externalInterface = "ens3";

  # Forced SSH command for the vps-deploy automation user (see below) —
  # only six fixed operations are let through (see the dispatcher below
  # for exactly which); everything else is rejected. This allowlist, not
  # the polkit grant it relies on, is the real security boundary: it's
  # what stops a compromised deploy key from doing anything beyond "copy
  # in and activate a vps system closure, or reboot".
  #
  # We never re-execute $SSH_ORIGINAL_COMMAND (or any substring of it)
  # through a shell — an earlier version of this dispatcher matched
  # commands with unanchored `case ... *"..."*)` globs and then ran
  # `exec /bin/sh -c "$cmd"`, which let an attacker holding the deploy
  # key smuggle arbitrary shell metacharacters before/after a matched
  # substring and get them executed too (caught by code review). Instead:
  # classify $cmd by which known operation it *contains* (a boolean
  # check, safe regardless of what surrounds the matched text, since we
  # never act on the matched text itself), separately extract the one
  # attacker-influenceable parameter we actually need (a nix store path)
  # with a strict regex, and then `exec` a freshly constructed argv built
  # entirely from fixed strings and that validated store path — never
  # from $cmd. A crafted $cmd can at most cause a misclassification into
  # one of these six fixed, harmless operations; it can never inject
  # additional shell syntax, because nothing derived from it ever reaches
  # a shell's command-string parser again.
  vpsDeployDispatcher = pkgs.writeShellScript "vps-deploy-dispatcher" ''
    set -eu
    cmd=$SSH_ORIGINAL_COMMAND

    # Nix store paths are a fixed-width hash plus name; restrict the name
    # half to this system's own closures. head -n1 picks the first match
    # deterministically if $cmd somehow contains more than one — doesn't
    # matter which, since every consumer below only ever treats the
    # result as an opaque, syntax-validated path, not as shell input.
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

    # nixos-rebuild's pre-activation sanity check ("does this closure
    # look like a real NixOS system"). Read-only stat, no side effects.
    case "$cmd" in
      *"test -f "*"/nixos-version"*)
        require_store_path
        exec ${pkgs.coreutils}/bin/test -f "$store_path/nixos-version"
        ;;
    esac

    # nixos-rebuild's own "is systemd actually running" check — no
    # attacker-influenceable data involved at all, fixed command.
    case "$cmd" in
      *"test -d /run/systemd/system"*)
        exec ${pkgs.coreutils}/bin/test -d /run/systemd/system
        ;;
    esac

    # nixos-rebuild's `nix-env --set` step, updating the system profile
    # to point at the new generation. This is a direct filesystem
    # symlink write under root-owned /nix/var/nix/profiles, not a plain
    # nix-daemon store operation (trusted-users doesn't cover it) — it
    # only succeeds via sudo, which is aliased to run0 here (see
    # security.run0.enableSudoAlias in profiles/default.nix), not real
    # sudo.
    case "$cmd" in
      *"nix-env -p /nix/var/nix/profiles/system --set"*)
        require_store_path
        exec /run/current-system/sw/bin/sudo ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set "$store_path"
        ;;
    esac

    # nixos-rebuild's switch-to-configuration invocation — the actual
    # activation step.
    case "$cmd" in
      *"switch-to-configuration switch"*)
        require_store_path
        exec /run/current-system/sw/bin/sudo "$store_path/bin/switch-to-configuration" switch
        ;;
    esac

    # our own reboot-if-kernel-changed trigger (constructed by
    # myPushDeploy on homelab) — fixed command, no parameters.
    case "$cmd" in
      *"systemctl reboot"*)
        exec /run/current-system/sw/bin/sudo ${pkgs.systemd}/bin/systemctl reboot
        ;;
    esac

    # myPushDeploy's pre-reboot kernel-change check (also constructed by
    # homelab) — read-only, no parameters, no side effects.
    case "$cmd" in
      *"readlink /run/booted-system/kernel"*)
        exec ${pkgs.coreutils}/bin/readlink /run/booted-system/kernel
        ;;
      *"readlink /run/current-system/kernel"*)
        exec ${pkgs.coreutils}/bin/readlink /run/current-system/kernel
        ;;
    esac

    reject
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
  # configuration.nix) via the vps-deploy user below.

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
  # while myPullDeploy built locally here (now removed — see
  # hosts/homelab/configuration.nix's myPushDeploy instead).
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
  # content needed verbatim on both ends (see hosts/homelab/configuration.nix).
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

  # DNAT alone doesn't rewrite the packet's source address, so without
  # this the forwarded game-server packets leave wg0 still carrying the
  # original internet client's IP — WireGuard's cryptokey routing on the
  # homelab side only accepts inbound traffic whose source matches this
  # host's own allowedIPs entry (10.100.0.1/32 above) and silently drops
  # anything else, so the connection would otherwise die completely on
  # the way out (caught by code review; confirmed against how the
  # nat-iptables module actually builds its rules — forwardPorts alone
  # never emits a POSTROUTING rule, only internalInterfaces/internalIPs
  # do, and neither applies to this wg0-egress direction). Idempotent
  # like the ratelimit rules below, so repeat activations don't stack
  # duplicate rules.
  networking.firewall.extraCommands = ''
    iptables -t nat -C POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1 2>/dev/null \
      || iptables -t nat -A POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1

    # per-source-IP rate limiting on the forwarded game ports, since
    # DNAT'd traffic bypasses anubis/crowdsec entirely (see above). Raw
    # table so it's evaluated before conntrack/NAT and independent of
    # whatever chain names the nat/firewall modules generate internally.
    # Thresholds are deliberately loose (a real player's client won't hit
    # them) — this is a floor against basic scanning/flooding, not a full
    # DDoS mitigation; a large enough volumetric flood saturates the
    # uplink before any firewall rule gets a say regardless.
    iptables -t raw -N vps-ratelimit 2>/dev/null || iptables -t raw -F vps-ratelimit
    iptables -t raw -C PREROUTING -i ${externalInterface} -j vps-ratelimit 2>/dev/null \
      || iptables -t raw -I PREROUTING -i ${externalInterface} -j vps-ratelimit

    # minecraft: cap new-connection attempts per source IP
    iptables -t raw -A vps-ratelimit -p tcp --dport 25565 --syn \
      -m hashlimit --hashlimit-above 15/minute --hashlimit-burst 10 \
      --hashlimit-mode srcip --hashlimit-name mc-new -j DROP

    # minecraft (geyser/bedrock): cap packet rate per source IP (also
    # blunts UDP amplification/reflection abuse of this port, same as
    # the factorio rule below). 60/sec was way too low — confirmed
    # live it was dropping real Bedrock client traffic too.
    iptables -t raw -A vps-ratelimit -p udp --dport 19132 \
      -m hashlimit --hashlimit-above 1000/second --hashlimit-burst 500 \
      --hashlimit-mode srcip --hashlimit-name mc-bedrock-flood -j DROP

    # factorio: cap packet rate per source IP (also blunts UDP
    # amplification/reflection abuse of this port). 60/sec was way too
    # low for real traffic — confirmed live it dropped 90k+ packets of
    # a single legitimate client's own map download/sync, manifesting
    # as multi-KB/s speeds with random stalls to 0. Factorio's UDP
    # protocol bursts far above typical scan/flood-detection thresholds
    # during normal map sync.
    iptables -t raw -A vps-ratelimit -p udp --dport 34197 \
      -m hashlimit --hashlimit-above 2000/second --hashlimit-burst 1000 \
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
  #
  # (Tried making this box a tailscale exit node — advertise-exit-node
  # plus dropping this override to let both IPv4/IPv6 forwarding turn
  # on. Reverted by request. Two things worth knowing if this gets
  # revisited: 1) a tailscale exit node bundles 0.0.0.0/0 and ::/0
  # together — there's no CLI flag to advertise only the IPv4 default
  # route, so an exit node here would need real working IPv6
  # forwarding, not just an IPv4-only one, or opted-in clients get
  # silently broken IPv6 rather than a clean fallback. 2) enabling
  # IPv6 forwarding here was NOT what broke the vps<->homelab
  # wireguard tunnel/game servers during that experiment — that was a
  # separate, pre-existing bug: the tunnel's endpoint was pinned to
  # vps's IPv6 literal, which silently died whenever homelab's
  # RFC4941 privacy IPv6 address rotated. Fixed independently by
  # pointing that endpoint at vps's stable IPv4 instead — see
  # hosts/homelab/configuration.nix's wg0 peer entry.)
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
  # anubis's unix socket is group-owned `anubis` at mode 0770 — caddy
  # (a separate system user) needs group membership to reverse_proxy
  # into it, or every request 502s with "permission denied" (confirmed
  # live on the vps).
  users.users.caddy.extraGroups = [ "anubis" ];
  services.caddy = {
    enable = true;
    virtualHosts = {
      "jellyfin.${lib.removeSuffix "." vars.domain}" = {
        # logFormat defaults to null (no `log {}` block emitted at
        # all) — without this, caddy never wrote real per-request
        # access logs, only sparse error/tls/acme events; crowdsec's
        # `crowdsecurity/caddy-logs` parser needs the `request` object
        # only access-log entries carry, so despite heavy scanner
        # traffic hitting this host, that parser had 0 hits in its
        # entire runtime (confirmed live via its prometheus metric)
        # and crowdsec never banned anything from it.
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
            # anubis refuses to proxy without this — it doesn't infer the
            # client IP from X-Forwarded-For (confirmed live: every
            # request 500'd with "[misconfiguration] X-Real-Ip header is
            # not set" until this was added).
            header_up X-Real-Ip {remote_host}
          }
        '';
      };
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
        # Must be "syslog", not "caddy" — journalctl always emits lines
        # with the syslog envelope ("Mon DD HH:MM:SS host caddy[pid]: ")
        # prefixed onto the actual message, and only `labels.type =
        # "syslog"` routes events through crowdsecurity/syslog-logs,
        # which strips that envelope before crowdsecurity/caddy-logs
        # ever sees the line. A non-"syslog" type here falls through
        # to the non-syslog catch-all instead, which does NOT strip
        # the envelope, so caddy-logs' `UnmarshalJSON(evt.Parsed.
        # message, ...)` always failed on the leading "Mon DD ..."
        # text — confirmed live: crowdsecurity/caddy-logs had 0 hits
        # in this agent's entire runtime despite real traffic, and
        # journalctl -u crowdsec showed `UnmarshalJSON: invalid
        # character 'A' looking for beginning of value` on every
        # single caddy line. This is a known crowdsec gotcha, not
        # specific to this setup (crowdsecurity/crowdsec#4098:
        # "Journalctl sources MUST use syslog type"). Verified fixed
        # via `cscli explain --type syslog` against a real captured
        # line (with the journalctl envelope intact) — it now reaches
        # crowdsecurity/caddy-logs successfully.
        labels.type = "syslog";
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

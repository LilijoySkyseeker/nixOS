{ inputs, ... }:
{
  flake.modules.nixos."profile-default" =
    {
      config,
      pkgs-unstable,
      pkgs-stable,
      inputs,
      lib,
      vars,
      options,
      ...
    }:
    {
      imports = [
        inputs.sops-nix.nixosModules.sops
        inputs.nix-index-database.nixosModules.nix-index
        inputs.home-manager.nixosModules.home-manager
        inputs.disko.nixosModules.disko
        inputs.impermanence.nixosModules.impermanence
        inputs.nix-flatpak.nixosModules.nix-flatpak
      ];
      environment.systemPackages = with pkgs-unstable; [
        btop
        wget
        eza
        tldr
        bat
        zoxide
        git
        lazygit
        neovim
        nixfmt
        rsync
        sops # secrets management
        smartmontools
        helix
        trippy # ping+traceroute tool
        psmisc # fuser, killall, pstree
        ffmpeg
        flac
        bitwarden-cli
        topgrade
        tmux

        zfs-prune-snapshots # TEMP, zfs needs module

      ];

      security = lib.mkMerge [
        # sudo for run0 alias (only present on nixpkgs versions that ship the run0 module;
        # newer run0 modules dropped the `enable` toggle since run0 itself is always available)
        (lib.optionalAttrs (options.security ? run0) {
          run0 = {
            enableSudoAlias = true;
          }
          // lib.optionalAttrs (options.security.run0 ? enable) { enable = true; };
        })
        {
          sudo = {
            enable = false;
            execWheelOnly = true;
            package = pkgs-unstable.sudo.override { withInsults = true; };
          };
        }
      ];

      # 26.11 change for zfs security
      boot.zfs.forceImportRoot = false;

      # tailscale
      # declarative login: authKeyFile logs the host into the tailnet on boot,
      # no manual `tailscale up` needed. Each host uses its own non-reusable
      # pre-authorized key (tailscale_authkey_<hostname>) already tagged with
      # tag:<hostname> at generation time, so a leaked key only ever grants
      # that one host's identity/tag rather than a shared credential.
      services.tailscale = {
        enable = true;
        # "client", not "both": `useRoutingFeatures = "both"` makes the
        # tailscale module force net.ipv{4,6}.conf.all.forwarding on, and only
        # homelab is actually an exit node / subnet router. Defaulting to
        # "both" therefore turned on IP forwarding across the whole fleet for
        # the benefit of one host -- including on two laptops that never route
        # anything, one of which roams onto untrusted networks. This inverts
        # the default to fail safe; homelab opts back in with mkForce.
        #
        # docs/hardening.md's "Tailscale forwarding sysctls" rule already said
        # to narrow this per host, but it had only ever been applied to vps.
        #
        # Note the module sets those sysctls at mkOverride 97, so a plain
        # boot.kernel.sysctl assignment loses to it silently -- changing this
        # option is the only thing that actually moves them.
        useRoutingFeatures = "client";
        authKeyFile = config.sops.secrets."tailscale_authkey_${config.networking.hostName}".path;
        # --ssh (Tailscale's own SSH server/auth implementation) is
        # deliberately NOT enabled: once on, it intercepts ALL SSH
        # connections to that host and gates them via the tailnet ACL's
        # "ssh" block, entirely bypassing real sshd — including any
        # authorized_keys ForceCommand restriction (confirmed live: this
        # broke vps's dedicated push-deploy user's command allowlist, and
        # when no ACL "ssh" rule matched, connections were hard-rejected
        # rather than falling through to real sshd — no partial/fallback
        # mode exists). SSH still only ever travels over the tailnet either
        # way (trustedInterfaces=tailscale0 + closed public port 22 on
        # every host that matters); this only decides whether real sshd or
        # tailscale's own proxy handles the authentication, and every host
        # here relies on real sshd being the one in control of that.
        extraUpFlags = [
          "--advertise-tags=tag:${config.networking.hostName}"
        ];
      };
      sops.secrets."tailscale_authkey_${config.networking.hostName}" = { };

      # Pin github.com's host key fleet-wide.
      #
      # Every host that deploys itself fetches origin/master as root --
      # myAutoUpdate on homelab, myPullDeploy on the laptops -- and
      # deploy-guards.nix does that with StrictHostKeyChecking=accept-new.
      # That is TOFU, and on homelab it is TOFU *on every boot*, because
      # impermanence does not persist /root so root's known_hosts is empty
      # again each time (F-P7-04, F-P3-05, F-P0-07). Since a commit fetched
      # from that remote becomes root on four hosts, the remote's identity is
      # worth pinning rather than accepting.
      #
      # This key was verified against the fingerprint GitHub publishes
      # (SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU) rather than
      # simply ssh-keyscan'ed and trusted, which would have reproduced the
      # TOFU it is meant to remove. Public key, not a secret.
      #
      # If GitHub ever rotates this, unattended deploys fail closed until it
      # is updated here -- which is the intended trade, but it is why it
      # matters that a failed deploy is actually noticed (see F-P7-09).
      #
      # vps is deliberately NOT pinned here: its host key churned three times
      # during the 2026-08-25 reinstall, so a pin would be a standing
      # breakage risk, and homelab already has root on vps by design
      # (F-P0-02) so host-key TOFU is not the weak link on that path.
      programs.ssh.knownHosts."github.com" = {
        hostNames = [
          "github.com"
          "ssh.github.com"
        ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };

      # firmware updates
      services.fwupd.enable = true;

      # SMART disk health tool
      services.smartd = {
        enable = true;
        autodetect = true;
        notifications = {
          systembus-notify.enable = true;
          wall.enable = true;
          x11.enable = true;
        };
      };

      # allow cross compilation
      boot.binfmt.emulatedSystems = [
        "aarch64-linux"
      ];

      # allow unfree
      nixpkgs.config.allowUnfree = true;

      # enable a firmware regardless of licence
      hardware.enableAllFirmware = true;

      # make sure <nixpkgs> sources from the flake
      nix.nixPath = [ "nixpkgs=${inputs.nixpkgs-unstable}" ];

      # home-manager
      home-manager = {
        # also pass inputs to home-manager modules
        extraSpecialArgs = {
          inherit
            inputs
            pkgs-unstable
            pkgs-stable
            vars
            ;
        };
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup"; # Force backup conflicted files
        overwriteBackup = true;
      };

      # comma and cache
      programs.nix-index-database.comma.enable = true;

      # neovim
      programs.neovim = {
        enable = true;
        defaultEditor = lib.mkForce true;
      };

      # sops-nix support, secret managment
      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        defaultSopsFormat = "yaml";
      };

      # auto gc with nh
      programs.nh = {
        enable = true;
        clean = {
          enable = true;
          dates = "daily";
          extraArgs = "--keep-since 7d --keep 7";
        };
      };

      # file system trim for ssd
      services.fstrim.enable = true;

      # fix for buggy fish command not found
      programs.command-not-found.enable = false;

      # remove all defualt packages
      environment.defaultPackages = lib.mkForce [ ];

      # firewall
      networking.firewall.enable = true;

      # Enable Flake Support
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # direnv
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      # Bootloader.
      boot.loader.systemd-boot = {
        enable = true;
        editor = false;
      };
      boot.loader.efi.canTouchEfiVariables = true;

      # Enable networking
      networking.networkmanager.enable = true;
      networking.nameservers = [
        "8.8.8.8"
        "1.1.1.1"
      ];
      services.resolved.enable = true;

      # Select internationalisation properties.
      i18n.defaultLocale = "en_US.UTF-8";
      i18n.supportedLocales = [
        "all"
      ];
      i18n.extraLocaleSettings = {
        LC_MEASUREMENT = "en_GB.UTF-8"; # metric units
      };

      # x86_64
      nixpkgs.hostPlatform = "x86_64-linux";

      # State Version for first install, don't touch
      system.stateVersion = "23.11";
    };
}

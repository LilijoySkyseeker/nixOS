# no `inputs` here: the inner module gets its own via specialArgs
{ config, ... }:
let
  # captured before the inner module's `config` shadows the flake-parts one
  debugTools = config.flake.debugTools;
in
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
      environment.systemPackages =
        with pkgs-unstable;
        [
          btop
          wget
          eza
          tldr
          bat
          glow # markdown reader
          zoxide
          git
          lazygit
          neovim
          nixfmt
          rsync
          sops # secrets management
          smartmontools
          trippy # ping+traceroute tool
          psmisc # fuser, killall, pstree
          ffmpeg
          flac
          bitwarden-cli
          topgrade
          tmux

          zfs-prune-snapshots # TEMP, zfs needs module

        ]
        # shared with the devshell (modules/flake/debug-tools.nix); always unstable,
        # even on stable-pinned homelab, so debug tools match fleet-wide
        ++ debugTools pkgs-unstable;

      security = lib.mkMerge [
        # run0 sudo alias, only where nixpkgs ships the run0 module;
        # newer run0 modules dropped `enable`
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
      # authKeyFile logs in on boot; per-host non-reusable key, pre-tagged tag:<hostname>
      services.tailscale = {
        enable = true;
        # "client", not "both": "both" forces ip forwarding on; only homelab routes
        # (it opts back in with mkForce). the module sets those sysctls at
        # mkOverride 97, so a plain boot.kernel.sysctl loses -- change this instead
        useRoutingFeatures = "client";
        authKeyFile = config.sops.secrets."tailscale_authkey_${config.networking.hostName}".path;
        # no --ssh: tailscale ssh intercepts all ssh and bypasses real sshd,
        # including authorized_keys ForceCommand (vps push-deploy allowlist)
        extraUpFlags = [
          "--advertise-tags=tag:${config.networking.hostName}"
        ];
      };
      sops.secrets."tailscale_authkey_${config.networking.hostName}" = { };

      # pin github.com: root fetches deploys from it, and /root isn't persisted so
      # accept-new would be TOFU every boot. key checked against github's published
      # fingerprint; on rotation, unattended deploys fail closed until updated here
      programs.ssh.knownHosts."github.com" = {
        hostNames = [
          "github.com"
          "ssh.github.com"
        ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };

      # journald: persistent, size-capped; 26.05 only has `extraConfig`,
      # 26.11 only `settings.Journal`, and 26.11 no longer pins Storage
      services.journald =
        if options.services.journald ? settings then
          {
            settings.Journal = {
              Storage = "persistent";
              SystemMaxUse = lib.mkDefault "2G";
            };
          }
        else
          { extraConfig = "SystemMaxUse=2G"; };

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

      boot.tmp.useTmpfs = true;

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

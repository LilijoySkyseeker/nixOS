# no `inputs` here: the inner module gets its own via specialArgs
{ config, ... }:
let
  # captured before the inner module's `config` shadows the flake-parts one
  debugTools = config.flake.debugTools;
in
{
  flake.modules.nixos.base =
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
      # the commit this system was built from; pull-deploy/push-deploy
      # compare it with master
      system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
      environment.systemPackages =
        with pkgs-unstable;
        [
          btop
          wget
          eza
          bat
          tldr
          glow
          zoxide
          git
          rsync
          sops
          smartmontools
          psmisc
          ffmpeg
          flac
          tmux
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
          sudo.enable = false;
        }
      ];

      boot.zfs.forceImportRoot = false;

      # authKeyFile logs in on boot; per-host non-reusable key, pre-tagged tag:<hostname>
      services.tailscale = {
        enable = true;
        # "client", not "both": "both" forces ip forwarding on. the module sets those sysctls at
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

      services.fwupd.enable = true;

      services.smartd = {
        enable = true;
        autodetect = true;
        notifications = {
          systembus-notify.enable = true;
          wall.enable = true;
        };
      };

      nixpkgs.config.allowUnfree = true;

      hardware.enableAllFirmware = true;

      home-manager = {
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
        backupFileExtension = "backup";
        overwriteBackup = true;
      };

      programs.nix-index-database.comma.enable = true;

      programs.neovim = {
        enable = true;
        defaultEditor = lib.mkForce true;
      };

      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        defaultSopsFormat = "yaml";
      };

      programs.nh = {
        enable = true;
        clean = {
          enable = true;
          dates = "daily";
          extraArgs = "--keep-since 7d --keep 7";
        };
      };

      services.fstrim.enable = true;

      programs.command-not-found.enable = false;

      environment.defaultPackages = lib.mkForce [ ];

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      boot.loader.systemd-boot = {
        enable = true;
        editor = false;
      };
      boot.loader.efi.canTouchEfiVariables = true;

      boot.tmp.useTmpfs = true;

      networking.networkmanager.enable = true;
      networking.nameservers = [
        "8.8.8.8"
        "1.1.1.1"
      ];
      services.resolved.enable = true;

      i18n.defaultLocale = "en_US.UTF-8";
      i18n.extraLocaleSettings = {
        LC_MEASUREMENT = "en_GB.UTF-8";
      };

      nixpkgs.hostPlatform = "x86_64-linux";

      # State Version for first install, don't touch
      system.stateVersion = "23.11";
    };
}

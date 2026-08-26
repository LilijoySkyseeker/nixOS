{ config, inputs, ... }:
let
  nixosModules = config.flake.modules.nixos;
  homeManagerModules = config.flake.modules.homeManager;
  vars = config.flake.vars;
in
{
  flake.modules.nixos."profile-pc" =
    {
      pkgs-unstable,
      pkgs-stable,
      inputs,
      config,
      ...
    }:
    {
      imports = [
        nixosModules."virtual-machines" # (also needs home manager config)
        nixosModules.tooling
        nixosModules."profile-default"
        nixosModules.wooting
        inputs.stylix.nixosModules.stylix
        inputs.nvf.nixosModules.default
      ];

      # System installed pkgs
      environment.systemPackages =
        (with pkgs-unstable; [
          grc # Text colors
          ripgrep
          gitFull
          gh # GitHub CLI
          gjs # for kdeconnect
          restic # backups
          fd
          nixos-anywhere
          ssh-to-age
          rclone
          distrobox
          caligula # cli burning tool
          scrcpy
          isd
          kdePackages.krfb # kde remote desktop tool
          kdePackages.krdc # kde remote desktop tool
          vipsdisp # big image viewer
          yt-dlp
          android-tools

          yubikey-manager
          distrobox
          bitwarden-desktop
          thunderbird
          vscode-fhs
          easyeffects
          qpwgraph
          libreoffice
          vlc
          r2modman
          yubioath-flutter
          nicotine-plus
          vial
          element-desktop
          ungoogled-chromium
          python313Packages.nomadnet
          rns
          signal-desktop
          picard # music metadata tool
          calibre
          quodlibet

          texliveFull

          # closed source
          spotify
          claude-code

          # temp copy from stable
          feishin
          prismlauncher
          vesktop
          discord
          kdePackages.kdenlive
          wl-clipboard # for waydroid
          quickemu
          qbittorrent
          texliveSmall

        ])
        ++ (with pkgs-stable; [
        ]);

      # networking
      networking.networkmanager = {
        enable = true;
        insertNameservers = [
          "8.8.8.8"
          "1.1.1.1"
        ];
      };

      # Waydroid
      virtualisation.waydroid.enable = true;

      # Appimage
      programs.appimage = {
        enable = true;
        binfmt = true;
      };

      # distrobox and other docker
      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
      };

      #qmk, allow udev rules
      hardware.keyboard.qmk.enable = true;

      #flatpak
      # gid pinned off its dynamically-allocated default (which lands on 999)
      # to keep 999 free for the "multimedia" group — see
      # modules/nixos/nfs-homelab-mounts.nix, which needs that exact gid to
      # match homelab's NFS-exported /storage group ownership.
      users.groups.flatpak.gid = vars.gids.flatpak;
      services.flatpak = {
        enable = true;
        uninstallUnmanaged = false;
        packages = [
          "app.grayjay.Grayjay"
          "info.beyondallreason.bar"
        ];
      };

      # udev rules
      services.udev.packages = [
        pkgs-unstable.via
        pkgs-unstable.vial
      ];
      services.udev.extraRules = ''
        # 8bitdo pro 3
        # 2.4GHz/Dongle
        KERNEL=="hidraw*", ATTRS{idProduct}=="6012", ATTRS{idVendor}=="2dc8", MODE="0660", GROUP="input"
        # Bluetooth
        KERNEL=="hidraw*", KERNELS=="*2DC8:6012*", MODE="0660", GROUP="input"

        # plover
        KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
      '';

      # home-manager
      home-manager.users.lilijoy = {
        imports = [
          homeManagerModules.tooling
          homeManagerModules."tooling-desktop"
          homeManagerModules."virt-manager"
          homeManagerModules."claude-code"
          inputs.plover-flake.homeManagerModules.plover
        ];
        home = {
          stateVersion = "23.11";
          username = "lilijoy";
          homeDirectory = "/home/lilijoy";

          # fish environment variables
          sessionVariables = {
            SSH_AUTH_SOCK = "/home/<user>/.bitwarden-ssh-agent.sock"; # bitwarden ssh-agent
          };
        };
        programs.home-manager.enable = true;

        stylix.targets.firefox.profileNames = [ "default" ];
        stylix.targets.qt.platform = "qtct";

        programs.plover = {
          enable = true;
          package = inputs.plover-flake.packages.${pkgs-unstable.system}.plover-full;
          settings = {
            "Machine Configuration" = {
              machine_type = "Gemini PR";
              auto_start = true;
            };
          };
        };
      };

      # service for yubikey
      services.pcscd.enable = true;

      # restrict nix package manager to @wheel
      nix.settings.allowed-users = [ "@wheel" ];

      # sops config
      # Boot-time secret decryption (e.g. for services that need a secret
      # before login, like tailscale's authkey) needs an identity that lives
      # on the root filesystem, since /home isn't mounted yet during early
      # activation. generateKey creates that identity on first activation if
      # it doesn't already exist, so it's reproducible from a fresh install:
      # its public key just needs to be added to .sops.yaml afterwards (see
      # docs/procedures/secrets.md's "Adding a recipient" runbook for the
      # one-time step).
      #
      # Deliberately NOT setting sops.age.sshKeyPaths to lilijoy's
      # ~/.ssh key here: that NixOS option only feeds sops-install-secrets'
      # boot-time manifest (which can never read it, since /home isn't
      # mounted yet -- upstream confirms this whole class of "configured ssh
      # key path missing at activation time" as a still-open sops-nix
      # limitation, https://github.com/Mic92/sops-nix/issues/167) and has no
      # effect on interactive `sops` edits, which are driven entirely by the
      # `sops` CLI's own identity discovery (SOPS_AGE_SSH_PRIVATE_KEY_FILE
      # env var or ~/.config/sops/age/keys.txt on whatever machine runs the
      # command), independent of this module. So it was pure downside with
      # no upside -- confirmed as the fix for TODO.md's "sops-nix
      # age.keyFile fallback doesn't fire" item (it was never a fallback
      # that could fire in the first place).
      sops.age.keyFile = "/var/lib/sops-nix/key.txt";
      sops.age.generateKey = true;

      # git identity, rendered to avoid storing name/email in the nix store
      sops.secrets.git_username = { };
      sops.secrets.git_email = { };
      sops.templates."git-identity" = {
        path = "/home/lilijoy/.config/git/identity";
        owner = "lilijoy";
        content = ''
          [user]
              name = ${config.sops.placeholder.git_username}
              email = ${config.sops.placeholder.git_email}
        '';
      };

      # nh, nix helper
      environment.variables = {
        FLAKE = "/home/lilijoy/dotfiles";
        NH_FLAKE = "/home/lilijoy/dotfiles";
      };

      # Stylix
      stylix = {
        enable = true;
        autoEnable = true;
        base16Scheme = "${pkgs-stable.base16-schemes}/share/themes/gruvbox-dark-soft.yaml";
        image = ../../files/gruvbox-dark-rainbow.png;
        polarity = "dark";
        cursor.package = pkgs-unstable.capitaine-cursors-themed;
        cursor.name = "Capitaine Cursors";
        cursor.size = 24;
        fonts = {
          monospace = {
            package = pkgs-unstable.nerd-fonts.jetbrains-mono;
            name = "JetBrainsMono Nerd Font Mono";
          };
          sansSerif = {
            package = pkgs-unstable.dejavu_fonts;
            name = "DejaVu Sans";
          };
          serif = {
            package = pkgs-unstable.dejavu_fonts;
            name = "DejaVu Serif";
          };
        };
      };

      # Kde Connect
      programs.kdeconnect = {
        enable = true;
      };

      # LD fix
      programs.nix-ld.enable = true;
      programs.nix-ld.libraries = with pkgs-unstable; [
        # add any missing dynamic libraries for unpackaged programs here
      ];

      # Enable bluetooth
      hardware.bluetooth.enable = true;
      hardware.bluetooth.powerOnBoot = true;

      # Enable CUPS to print documents.
      services.printing = {
        enable = true;
        drivers = [
          pkgs-unstable.brlaser
        ];
      };
      # network printing
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };

      # Enable sound with pipewire.
      services.pulseaudio.enable = false;
      services.pulseaudio.support32Bit = true;
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users.lilijoy = {
        isNormalUser = true;
        initialPassword = "123456";
        description = "Lilijoy";
        extraGroups = [
          "networkmanager"
          "wheel"
          "dialout" # for plover
          "input" # for plover
          "docker"
        ];
      };

      # steam
      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true;
      };
      hardware.steam-hardware.enable = true;

      # feral gamemode
      programs.gamemode = {
        enable = true;
        settings = {
          cpu = {
            park_cores = "no";
            pin_cores = "yes";
          };
        };
      };

      # Mullvad vpn
      services.mullvad-vpn = {
        enable = true;
        gui.enable = true;
      };
    };
}

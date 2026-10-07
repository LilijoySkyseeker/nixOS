{ config, ... }:
let
  nixosModules = config.flake.modules.nixos;
  homeManagerModules = config.flake.modules.homeManager;
  vars = config.flake.vars;
in
{
  flake.modules.nixos."profile-pc" =
    {
      pkgs-unstable,
      inputs,
      config,
      lib,
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
      environment.systemPackages = with pkgs-unstable; [
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
        vipsdisp # big image viewer
        yt-dlp
        android-tools

        yubikey-manager
        bitwarden-desktop
        thunderbird
        vscode-fhs
        easyeffects
        qpwgraph
        libreoffice
        vlc
        r2modman
        nicotine-plus
        vial
        ungoogled-chromium
        signal-desktop
        picard # music metadata tool
        calibre

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

      ];

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

      # kde: keyboard > keyboard > key bindings > function keys > "use
      # f13-f24 as usual function keys" -- system-wide xkb option, not
      # kde/kxkbrc-specific, so applies at login and on any tty too
      services.xserver.xkb.options = "terminate:ctrl_alt_bksp,fkeys:basic_13-24";

      #flatpak
      # gid pinned off its default (999): nfs-homelab-mounts.nix needs 999 for
      # "multimedia" to match homelab's NFS /storage group
      users.groups.flatpak.gid = vars.gids.flatpak;
      services.flatpak = {
        enable = true;
        uninstallUnmanaged = false;
        packages = [
          "info.beyondallreason.bar"
        ];
      };

      # udev rules
      services.udev.packages = [
        pkgs-unstable.vial
      ];
      # no 8bitdo hidraw rules: controller access comes from uaccess
      # (50-qmk/60-steam-input rules), not the `input` group

      # home-manager
      home-manager.users.lilijoy = {
        imports = [
          homeManagerModules.tooling
          homeManagerModules."tooling-desktop"
          homeManagerModules."virt-manager"
          homeManagerModules."claude-code"
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
      };

      # service for yubikey
      services.pcscd.enable = true;

      # restrict nix package manager to @wheel
      nix.settings.allowed-users = [ "@wheel" ];

      # sops config
      # host age identity on the root fs (/home isn't mounted at early activation);
      # generateKey creates it on first boot, then add its pubkey to .sops.yaml
      # no sshKeyPaths to ~/.ssh: unreadable at boot (sops-nix#167); `sops` CLI ignores it
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
        # source path, not a package: the scheme itself needs no eval-time build
        base16Scheme = "${inputs.stylix.inputs.tinted-schemes}/base16/gruvbox-dark-soft.yaml";
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

      # scope kde connect to the tailnet: its module opens 1714-1764 host-wide with
      # no openFirewall toggle, so force the host-wide lists empty and re-add per interface
      # mkForce empties the *whole* list: a range another module adds vanishes silently;
      # the rendered firewall script should show dport 1714:1764 and no other range
      networking.firewall = {
        allowedTCPPortRanges = lib.mkForce [ ];
        allowedUDPPortRanges = lib.mkForce [ ];
        interfaces.tailscale0 = {
          allowedTCPPortRanges = [
            {
              from = 1714;
              to = 1764;
            }
          ];
          allowedUDPPortRanges = [
            {
              from = 1714;
              to = 1764;
            }
          ];
        };
      };

      # Enable bluetooth
      hardware.bluetooth.enable = true;
      hardware.bluetooth.powerOnBoot = true;

      # Enable CUPS to print documents.
      # base only; the brother queue and scanning live in
      # nixosModules."brother-mfc-l2740dw", torrent only (unfree blob, roaming laptop)
      services.printing = {
        enable = true;
        drivers = [ ];
      };

      # no avahi/mDNS: opens udp 5353 host-wide on a roaming laptop; the printer
      # has a static address, so don't re-add it for printing

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
        # no initialPassword: the repo is public, so any value is published;
        # if needed, use hashedPasswordFile from a sops secret, never a literal
        description = "Lilijoy";
        # never add `input`: read of every evdev device lets any user process
        # keylog run0/polkit, bitwarden and yubikey pin, bypassing wayland
        extraGroups = [
          "networkmanager"
          "wheel"
          "docker"
        ];
      };

      # steam
      # no remotePlay.openFirewall (host-wide ports); if wanted, scope to an interface
      programs.steam = {
        enable = true;
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

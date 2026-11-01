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
        nixosModules."virtual-machines"
        nixosModules.tooling
        nixosModules."agent-tools"
        nixosModules."profile-default"
        nixosModules.wooting
        inputs.stylix.nixosModules.stylix
        inputs.nvf.nixosModules.default
      ];

      environment.systemPackages = with pkgs-unstable; [
        ripgrep
        gh
        codex
        nodejs
        fd
        nixos-anywhere
        ssh-to-age
        caligula
        scrcpy
        vipsdisp
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
        picard
        calibre
        readest

        spotify
        claude-code
        chatgpt
        inputs.llm-agents.packages.${pkgs-unstable.stdenv.hostPlatform.system}.claude-desktop

        feishin
        prismlauncher
        vesktop
        discord
        kdePackages.kdenlive
        wl-clipboard
        quickemu
        qbittorrent

      ];

      programs.appimage = {
        enable = true;
        binfmt = true;
      };

      hardware.keyboard.qmk.enable = true;

      # kde: keyboard > keyboard > key bindings > function keys > "use
      # f13-f24 as usual function keys" -- system-wide xkb option, not
      # kde/kxkbrc-specific, so applies at login and on any tty too
      services.xserver.xkb.options = "terminate:ctrl_alt_bksp,fkeys:basic_13-24";

      # gid pinned off its default (999): nfs-homelab-mounts.nix needs 999 for
      # "multimedia" to match homelab's NFS /storage group
      users.groups.flatpak.gid = vars.gids.flatpak;
      services.flatpak = {
        enable = true;
        packages = [
          "info.beyondallreason.bar"
        ];
      };

      services.udev.packages = [
        pkgs-unstable.vial
      ];

      home-manager.users.lilijoy = {
        imports = [
          homeManagerModules.tooling
          homeManagerModules."tooling-desktop"
          homeManagerModules."virt-manager"
          homeManagerModules."claude-code"
          homeManagerModules."paseo-desktop"
        ];
        home = {
          stateVersion = "23.11";
          username = "lilijoy";
          homeDirectory = "/home/lilijoy";
        };
        programs.home-manager.enable = true;

        stylix.targets.firefox.profileNames = [ "default" ];
        # qtct set QT_STYLE_OVERRIDE=kvantum, which broke Plasma 6.7 QML (black desktop); Plasma themes Qt itself.
        stylix.targets.qt.enable = false;
      };

      services.pcscd.enable = true;

      nix.settings.allowed-users = [ "@wheel" ];

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

      environment.variables = {
        NH_FLAKE = "/home/lilijoy/dotfiles";
      };

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

      hardware.bluetooth.enable = true;

      services.printing.enable = true;

      # no avahi/mDNS: opens udp 5353 host-wide on a roaming laptop; the printer
      # has a static address, so don't re-add it for printing

      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

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
        ];
      };

      # no remotePlay.openFirewall (host-wide ports); if wanted, scope to an interface
      programs.steam = {
        enable = true;
      };

      programs.gamemode = {
        enable = true;
        settings = {
          cpu = {
            park_cores = "no";
            pin_cores = "yes";
          };
        };
      };

      # every steam game starts under `reaper SteamLaunch AppId=…`: register
      # each one with gamemode, whose reaper drops it again when it exits
      systemd.user.services.steam-gamemode = {
        description = "Run every Steam game under gamemode";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.getExe (
            pkgs-unstable.writeShellApplication {
              name = "steam-gamemode";
              runtimeInputs = with pkgs-unstable; [
                procps
                systemd
              ];
              text = ''
                gm=(com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode)
                while sleep 3; do
                  # own processes only: another user (agent) can't toggle this session's gamemode
                  for pid in $(pgrep -u "$UID" -f '^[^ ]*/reaper SteamLaunch AppId='); do
                    # 2: gamemode is on and this pid is registered
                    [ "$(busctl --user call "''${gm[@]}" QueryStatusByPID ii $$ "$pid" 2>/dev/null)" = "i 2" ] && continue
                    busctl --user call "''${gm[@]}" RegisterGameByPID ii $$ "$pid" >/dev/null || true
                  done
                done
              '';
            }
          );
          Restart = "on-failure";
        };
      };

      services.mullvad-vpn = {
        enable = true;
        gui.enable = true;
      };
    };
}

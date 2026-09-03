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

      # kde: keyboard > keyboard > key bindings > function keys > "use
      # f13-f24 as usual function keys" -- system-wide xkb option, not
      # kde/kxkbrc-specific, so applies at login and on any tty too
      # plan: 2026-09-01-declare-f13-f24-as-usual-function-keys-via-xkb-on-pc-hosts.md#G1
      services.xserver.xkb.options = "terminate:ctrl_alt_bksp,fkeys:basic_13-24";

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
      # No services.udev.extraRules here any more. It held two 8bitdo Pro 3
      # hidraw rules and plover's uinput rule; plover is gone, and the
      # 8bitdo pair was dead config that never worked (confirmed by the
      # user, and visible on-box): they ask for MODE="0660" GROUP="input",
      # but live every /dev/hidraw* is 0666 root:plugdev with a uaccess
      # ACL, because 50-qmk.rules (all hidraw, GROUP=plugdev,
      # TAG+=uaccess) and 60-steam-input.rules (vendor 2dc8, TAG+=uaccess)
      # both sort after 99-local.rules for those attributes. Controller
      # access came from uaccess the whole time, never from the group --
      # so the rules bought nothing and their only effect was to make the
      # `input` grant above look load-bearing when it was not.

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
      # no upside -- confirmed as the fix in
      # 2026-08-18-sops-nix-age-keyfile-fallback-doesn-t-actually-fir.md
      # (it was never a fallback that could fire in the first place).
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

      # Scope KDE Connect to the tailnet (audit decision D9, 2026-08-27).
      #
      # `programs.kdeconnect` opens TCP+UDP 1714-1764 host-wide and gives
      # you no say in it: the pinned nixpkgs module sets
      # `networking.firewall.allowedTCPPortRanges` unconditionally inside
      # its own `mkIf cfg.enable`, with no `openFirewall` option to turn
      # off (checked against nixos/modules/programs/kdeconnect.nix at the
      # pinned rev, not assumed). So the only way to narrow it is to
      # mkForce the host-wide lists empty and re-add the range scoped to
      # an interface.
      #
      # mkForce on the *whole list* is safe here only because kdeconnect
      # is the only thing left contributing a port range on these hosts —
      # Steam's remote play (27031-27035) is disabled just below, and
      # avahi is gone entirely. If a future module adds a range and it
      # silently disappears, this is why. The rendered firewall script is
      # the place to check: `grep -oE 'dport [0-9]+:[0-9]+'` over it
      # should list 1714:1764 and nothing else.
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

      # LD fix
      programs.nix-ld.enable = true;
      programs.nix-ld.libraries = with pkgs-unstable; [
        # add any missing dynamic libraries for unpackaged programs here
      ];

      # Enable bluetooth
      hardware.bluetooth.enable = true;
      hardware.bluetooth.powerOnBoot = true;

      # Enable CUPS to print documents.
      #
      # Base only -- shared by both PC hosts. The actual printer queue and
      # scanning are declared in nixosModules."brother-mfc-l2740dw" and
      # wired into torrent only (modules/flake/hosts.nix), not here: both
      # ensurePrinters' deviceUri and sane-airscan's WSD discovery are
      # network-supplied-identity risks D9 was written to avoid on a
      # roaming laptop.
      # plan: 2026-08-27-set-up-the-new-network-printer-scanner-brother-mfc.md#F1
      services.printing = {
        enable = true;
        drivers = [ ];
      };

      # No avahi/mDNS. It was here for exactly one thing — discovering the
      # old network printer — and it opened UDP 5353 host-wide on both a
      # desktop and a laptop that roams onto untrusted networks, where
      # mDNS broadcasts the hostname and service list to whoever is
      # listening. Removed rather than interface-scoped (audit decision
      # D9, option c): a static printer address needs no discovery
      # protocol at all, which is strictly less surface than firewalling
      # one. Re-adding avahi is not the way to set up the new printer.
      # (F-P1-04, F-P5-06)

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
        # No initialPassword here. This repo is public, so any value set here
        # is a published credential rather than a weak one -- it previously
        # read "123456" (F-P1-03). Removing it does not change an already-set
        # password: initialPassword only applies when the account is created,
        # so this stops publishing the value but does not itself remediate a
        # host where it was never changed. torrent is confirmed clear (its
        # password was last changed after install); thinkpad was offline
        # during the audit and still needs `passwd -S lilijoy` checked.
        #
        # If a declarative password is ever wanted here, use
        # hashedPasswordFile pointing at a sops secret -- never a literal.
        description = "Lilijoy";
        # `dialout` and `input` were both here "for plover", and plover is
        # gone (declared unused, 2026-08-27). `input` in particular was the
        # single worst grant on these hosts (F-P1-01): /dev/input/event* is
        # root:input 0660 with no uaccess ACL -- systemd deliberately does
        # not uaccess-tag keyboards -- so the membership was the *only*
        # thing granting it, and it granted read of every input device on
        # the machine. Under Wayland, which otherwise blocks X11-style input
        # snooping, evdev read is the bypass. Anything running as lilijoy
        # could capture, in plaintext, the run0/polkit password (typed on
        # every elevation, since wheelNeedsPassword is true), the
        # lock-screen password, the Bitwarden master password and the
        # YubiKey PIN -- then register its own polkit agent and answer its
        # own prompt for root, with no further vulnerability and no race.
        extraGroups = [
          "networkmanager"
          "wheel"
          "docker"
        ];
      };

      # steam
      #
      # `remotePlay.openFirewall` dropped 2026-08-27 (audit decision D9):
      # it opened TCP 27036/27037 and UDP 27031-27036 host-wide, on a
      # desktop and on a laptop that roams onto untrusted networks, for a
      # feature that is not used. Steam itself is unaffected — this only
      # ever controlled the in-home-streaming listener, not the client,
      # not the store, not games. If remote play is ever wanted again,
      # turn it back on scoped to an interface rather than host-wide.
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

{ config, pkgs, pkgs-unstable, inputs, lib, ... }: {
  imports = [
    inputs.stylix.nixosModules.stylix
    ../modules/nixos/virtual-machines.nix # (also needs home manager config)
    ./default.nix
    ../custom-packages/tpm-fido/package.nix
    #../modules/nixos/copypartymount.nix
  ];

  # System installed pkgs
  environment.systemPackages = (with pkgs; [
    # STABLE installed packages

    grc # Text colors
    ripgrep
    gitFull
    nvtopPackages.full
    gjs # for kdeconnect
    restic # backups
    fd
    nixos-anywhere
    ssh-to-age
    rclone

    yubikey-manager

    distrobox

    gnome-extension-manager
    baobab # gnome disk usage utilty
    gnome.gnome-tweaks
    bitwarden
    thunderbird
    vscode-fhs
    python3
    cider
    kdenlive
    qbittorrent
    jellyfin-media-player
    easyeffects
    qpwgraph
    youtube-music
    qalculate-gtk
    libreoffice
    vial
    vlc
    r2modman
    yubioath-flutter
    vesktop

    obsidian
    spotify
  ]) ++ (with pkgs-unstable; [ 
    feishin
    prismlauncher
  ]); # UNSTABLE installed packages

  # home-manager
  home-manager.users.lilijoy = {
    imports = [ ../modules/home-manager/tooling.nix ];
    home.stateVersion = "23.11";
    home.username = "lilijoy";
    home.homeDirectory = "/home/lilijoy";
    programs.home-manager.enable = true;

    # fzf
    programs.fzf = {
      enable = true;
      enableFishIntegration = true;
    };

    # KDE Connect
    services.kdeconnect = {
      enable = true;
      indicator = true;
      package = pkgs.gnomeExtensions.gsconnect;
    };

    # Numlock on login
    xsession.numlock.enable = true;

    # Virtual-machine (also neeed nixos module)
    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = [ "qemu:///system" ];
        uris = [ "qemu:///system" ];
      };
    };

    # zoxide
    programs.zoxide = {
      enable = true;
      enableFishIntegration = true;
    };

    # OBS Studio
    programs.obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [ obs-pipewire-audio-capture ];
    };

    # BTOP
    programs.btop = {
      enable = true;
      settings = {
        color_theme = lib.mkDefault "night-owl";
        update_ms = 1000;
        cpu_single_graph = true;
        proc_per_core = true;
        proc_sorting = "cpu direct";
      };
    };

    # Firefox
    programs.firefox = { enable = true; };

    # fish
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting # Disable greeting
        tide configure --auto --style=Rainbow --prompt_colors='16 colors' --show_time='12-hour format' --rainbow_prompt_separators=Angled --powerline_prompt_heads=Sharp --powerline_prompt_tails=Flat --powerline_prompt_style='Two lines, character and frame' --prompt_connection=Dotted --powerline_right_prompt_frame=Yes --prompt_spacing=Sparse --icons='Many icons' --transient=No
        set -g fish_key_bindings fish_vi_key_bindings
        clear
      '';
      plugins = [
        {
          name = "grc";
          src = pkgs.fishPlugins.grc.src;
        }
        {
          name = "tide";
          src = pkgs.fishPlugins.tide.src;
        }
      ];
      functions = {
        nsr.body =
          "\n              nix shell nixpkgs/nixos-unstable#$argv[1] --command $argv\n              ";
        ns.body =
          "\n              nix shell 'nixpkgs/nixos-unstable#'{$argv}\n            ";
        nhu.body =
          "\n              git add --all && nh os build --update && git add --all\n              ";
        nht.body =
          "\n              git add --all && nh os test\n              ";
        nhb.body =
          "\n              git add --all && nh os boot && git diff --staged | bat --paging always --pager less && git commit -a && git push\n              ";
        nhs.body =
          "\n              git add --all && nh os switch && git diff --staged | bat --paging always --pager less && git commit -a && git push\n              ";
        gds.body =
          "\n              git add --all && git diff --staged | bat --paging always --pager less\n              ";
      };
      shellAliases = {
        e =
          "eza --group-directories-first --header --git --git-ignore --icons --all --long --mounts";
        et =
          "eza --tree --group-directories-first --header --git --git-ignore --icons --all --long --mounts";
        etl =
          "eza --tree --group-directories-first --header --git --git-ignore --icons --all --long --mounts --level";
      };
      shellAbbrs = {
        rsync = "rsync --verbose --recursive --progress --human-readable";
      };
    };

    # bat
    programs.bat = {
      enable = true;
      config = { pager = "never"; };
    };

    # eza
    programs.eza = {
      enable = true;
      enableBashIntegration = false;
      enableFishIntegration = false;
    };

    # GNOME config: Use 'dconf watch /'
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = lib.mkDefault "prefer-dark";
        enable-hot-corners = false;
        show-battery-percentage = true;
        clock-format = "12h";
        clock-show-weekday = true;
        clock-show-seconds = true;
      };
      "org/gtk/settings/file-chooser" = { clock-format = "12h"; };
      "org/gtk/gtk4/settings/file-chooser" = { show-hidden = true; };
      "org/gnome/desktop/peripherals/mouse" = { accel-profile = "flat"; };

      "org/gnome/mutter" = {
        dynamic-workspaces = false;
        workspaces-only-on-primary = true;
        check-alive-timeout = "uint32 60000";
        experimental-features = [ "variable-refresh-rate" ];
      };
      "org/gnome/settings-daemon/plugins/power" = {
        idle-dim = false;
        sleep-inactive-battery-type = "nothing";
        sleep-inactive-ac-type = "nothing";
        #           power-button-action = "interactive";
      };
      "org/gnome/desktop/wm/preferences" = {
        num-workspaces = 6;
        focus-mode = "sloppy";
        auto-raise = false;
        button-layout = "appmenu:minimize,maximize,close";
      };

      # Clipboard Indicator
      "org/gnome/shell/extensions/clipboard-indicator" = {
        enable-keybindings = false;
        history-size = 100;
      };

      # Dash to Panel
      "org/gnome/shell/extensions/dash-to-panel" = {
        multi-monitors = false;
        animate-appicon-hover = true;
        show-favorites = false;
        group-apps = false;
        group-apps-use-fixed-width = false;
        isolate-workspaces = true;
        appicon-padding = 0;
        appicon-margin = 4;
        tray-padding = 4;
        icon-padding = 0;
      };

      # Openweather
      "org/gnome/shell/extensions/openweatherrefined" = {
        refresh-interval-current = 600;
        refresh-interval-forecast = 3600;
        loc-refresh-interval = 60;
        disable-forecast = false;
        use-system-icons = true;
        delay-ext-init = 15;
        unit = "fahrenheit";
        wind-speed-unit = "mph";
        pressure-unit = "atm";
        clock-format = "12h";
        simplify-degrees = true;
        weather-provider = "openweathermap";
        custom-keys = [ "34f3635c44f16c3c385e875bdbbfb445" ];
        position-in-panel = "right";
        position-index = 0;
        show-text-in-panel = true;
        show-comment-in-panel = true;
        show-sunsetrise-in-panel = true;
        sun-in-panel-first = false;
        menu-alignment = 82;
        translate-condition = true;
        decimal-places = 0;
        pressure-decimal-places = -2;
        speed-decimal-places = -1;
        location-text-lenght = 0;
        hi-contrast = "none";
        center-forecast = true;
        show-comment-in-forecast = true;
        days-forecast = 5;
        expand-forecast = true;
        my-loc-prov = "ipinfoio";
        geolocation-provider = "openstreetmaps";
      };

      # Tiling Assistant
      "org/gnome/shell/extensions/tiling-assistant" = {
        maximize-with-gap = true;
        enable-tiling-popup = false;
        enable-raise-tile-group = false;
        dynamic-keybinding-behavior = 2;
        active-window-hint = 1;
        monitor-switch-grace-period = true;
      };

      # ddterm
      "org/gnome/shell/extensions/ddterm" = {
        window-monitor = "current";
        show-animation-duration = 0.1;
        theme-variant = "dark";
      };

      # Tiling Shell
#     "org/gnome/shell/extensions/tilingshell" = {
#       overridden-settings = ''
#         "{\"org.gnome.mutter.keybindings\":{\"toggle-tiled-right\":\"['<Super>Right']\",\"toggle-tiled-left\":\"['<Super>Left']\"},\"org.gnome.desktop.wm.keybindings\":{\"maximize\":\"['<Super>Up']\",\"unmaximize\":\"['<Super>Down', '<Alt>F5']\"},\"org.gnome.mutter\":{\"edge-tiling\":\"false\"}}"
#       '';
      };

      # enabled extensions
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = [
          "dash-to-panel@jderose9.github.com"
          "clipboard-indicator@tudmotu.com"
          "openweather-extension@penguin-teal.github.io"
          "tiling-assistant@leleat-on-github"
          "ddterm@amezin.github.com"
          "gsconnect@andyholmes.github.io"
          "batterytimepercentagecompact@sagrland.de"
          "battery-usage-wattmeter@halfmexicanhalfamazing.gmail.com"
          "smart-auto-move@khimaros.com"
#         "tilingshell@ferrarodomenico.com"
        ];
      };
    };

    # Gnome extension packages
    home.packages = (with pkgs.gnomeExtensions; [
      # STABLE
      dash-to-panel
      clipboard-indicator
      tiling-assistant
      ddterm
      battery-time-percentage-compact
      battery-usage-wattmeter
      smart-auto-move
    ]) ++ (with pkgs-unstable.gnomeExtensions;
      [
        # UNSTABLE
        openweather-refined
        tiling-shell
      ]);
  };

  # tpm-fido
  tpm-fido.enable = true;

  # ssh key type order
  programs.ssh.hostKeyAlgorithms = [ "ssh-ed25519" "ecdsa" ];

  # service for yubikey
  services.pcscd.enable = true;

  # restric nix package manager to @wheel
  nix.settings.allowed-users = [ "@wheel" ];

  # sops config
  sops.age.sshKeyPaths =
    [ "/home/lilijoy/.ssh/id_ed25519" "/home/lilijoy/.ssh/id_ed25519" ];
  sops.secrets = {
    open_weather_key = { };
    restic = { owner = config.users.users.lilijoy.name; };
  };

  # nh, nix helper
  programs.nh.flake = "/home/lilijoy/dotfiles";

  # Stylix
  stylix = {
    enable = true;
    autoEnable = true;
    base16Scheme =
      "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = /home/lilijoy/dotfiles/files/gruvbox-dark-rainbow.png;
    polarity = "dark";
    cursor.package = pkgs.capitaine-cursors-themed;
    cursor.name = "Capitaine Cursors";
  };

  # Disable uneeded GNOME apps
  environment.gnome.excludePackages = with pkgs.gnome; [
    totem # video player
    geary # mail
    gnome-calculator
    gnome-shell-extensions
  ];

  # Kde Connect
  programs.kdeconnect = {
    enable = true;
    package = pkgs.gnomeExtensions.gsconnect;
  };

  # Enable X11 and Gnome
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Docker
  virtualisation.docker = { enable = true; };

  # Intel CPU freq stuck fix
  boot.kernelParams = [ "intel_pstate=active" ];

  # LD fix
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs;
    [
      # add any missing dynamic libraries for unpackaged programs here
    ];

  # sudo
  security.sudo = {
    execWheelOnly = true;
    package = pkgs.sudo.override { withInsults = true; };
  };

  # Enable bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable CUPS to print documents.
  services.printing.enable =
    false; # DISABLED DUE TO VULNERABILITY https://www.evilsocket.net/2024/09/26/Attacking-UNIX-systems-via-CUPS-Part-I/

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
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
    description = "Lilijoy";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # Git
  programs.git = { enable = true; };

  # fish
  programs.fish = {
    enable = true;
    vendor.completions.enable = true;
  };
  programs.bash = {
    # switch to fish in interactive shell
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };
  environment.shellAliases =
    lib.mkForce { }; # clear all shell aliases, using fish functions instead

  # steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    package = with pkgs;
      steam.override {
        extraPkgs = pkgs: [
          # for FAF, https://discord.com/channels/197033481883222026/1228471001633914950/1228506126900006982
          jq
          cabextract
          wget
        ];
      };
  };

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

  # fonts
  fonts.packages = with pkgs; [ (nerdfonts.override { fonts = [ "Meslo" ]; }) ];

  # Mullvad vpn
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  # Theme KDE apps like gnome
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };
}

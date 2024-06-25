{ config, pkgs, lib, ... }:
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "lilijoy";
  home.homeDirectory = "/home/lilijoy";

  # Allow Unfree
  nixpkgs.config.allowUnfree = true;

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
      autoconnect = ["qemu:///system"];
      uris = ["qemu:///system"];
    };
  };

  # zoxide
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # Git
  programs.git = {
    enable = true;
    userName = "LilijoySkyseeker";
    userEmail = "lilijoyskyseeker@gmail.com";
  };

  # OBS Studio
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
    obs-pipewire-audio-capture
    ];
  };

  # BTOP
  programs.btop = {
    enable = true;
    settings = {
      color_theme = lib.mkDefault "night-owl";
      update_ms = 1000;
      cpu_single_graph = true;
      per_core = true;
    };
  };

  # Firefox
  programs.firefox = {
    enable = true;
  };      

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
      { name = "grc"; src = pkgs.fishPlugins.grc.src; }
      { name = "tide"; src = pkgs.fishPlugins.tide.src; }
    ];
    functions = {
      nsr = {
        body = "
          nix shell nixpkgs/nixos-unstable#$argv[1] --command $argv
        ";
      };
      ns = {
        body = "
          nix shell 'nixpkgs/nixos-unstable#'{$argv}
        ";
      };
      #__fish_command_not_found_handler = {
      #    body = "nsr $argv";
      #};
    };
    shellAliases = lib.mkForce {
      cat = "bat $argv";
      ls = "eza";
      lt = "eza --tree";
      ltl = "eza --tree --level";
    };
  };

  # eza
  programs.eza = {
    enable = true;
    extraOptions = ["--group-directories-first" "--header" "--git" "--icons" "--all" "--long" "--mounts"];
    enableBashIntegration = false;
    enableFishIntegration = false;
  };

  # NVIM
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    extraConfig = ''
"     set langmap=qq,ww,fe,pr,bt,jy,lu,ui,yo,\\;p,aa,rs,sd,tf,gg,mh,nj,ek,il,o\\;,xz,cx,dc,vv,zb,kn,hm,QQ,WW,FE,PR,BT,JY,LU,UI,YO,:P,AA,RS,SD,TF,GG,MH,NJ,EK,IL,O:,XZ,CX,DC,VV,ZB,KN,HM

      nmap j gj
      nmap k gk
      nmap H ^
      nmap L $

      syntax on

      set fileformat=unix
      set encoding=UTF-8

      au BufNewFile,BufRead *.py
			\ set tabstop=4 |
			\ set softtabstop=4 |
			\ set shiftwidth=4 |

      set tabstop=2
      set softtabstop=2
      set shiftwidth=2
      set autoindent
      set smartindent
      set smarttab
      set expandtab

      set list
      set listchars=eol:.,tab:>-,trail:~,extends:>,precedes:<

      set cursorline
      set number
      set scrolloff=8
      set signcolumn=number

      set relativenumber

      set showcmd
      set noshowmode
      set conceallevel=1

      set noerrorbells visualbell t_vb=
      set noswapfile
      set nobackup
      set undodir=~/.config/nvim/undodir
      set undofile
      set clipboard=unnamed
      set clipboard=unnamedplus

      set ignorecase
      set smartcase
      set incsearch
      set hlsearch

      set mouse=a

      if exists('g:vscode')
          " VSCode extension
      else
          " ordinary Neovim
      endif
      '';
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
    "org/gtk/settings/file-chooser" = {
      clock-format = "12h";
    };
    "org/gtk/gtk4/settings/file-chooser" = {
      show-hidden = true;
    };
    "org/gnome/desktop/peripherals/mouse" = {
      accel-profile = "flat";
    };
    "org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = [
        "launch-new-instance@gnome-shell-extensions.gcampax.github.com"
        "dash-to-panel@jderose9.github.com"
        "appindicatorsupport@rgcjonas.gmail.com"
        "clipboard-indicator@tudmotu.com"
        "tiling-assistant@leleat-on-github"
        "openweather-extension@penguin-teal.github.io"
        "ddterm@amezin.github.com"
        "gsconnect@andyholmes.github.io"
      ];
    };
    "org/gnome/mutter" = {
      dynamic-workspaces = true;
      workspaces-only-on-primary = true;
      check-alive-timeout = 60000;
      experimental-features = ["variable-refresh-rate"];
    };
    "org/gnome/settings-daemon/plugins/power" = {
      idle-dim = false;
      sleep-inactive-battery-type = "nothing";
      sleep-inactive-ac-type = "nothing";
      power-button-action = "interactive";
    };
    "org/gnome/desktop/wm/preferences" = {
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
    };

    # Tiling Assistant
    "org/gnome/shell/extensions/tiling-assistant" = {
      enable-tiling-popup = false;
      enable-raise-tile-group = false;
      dynamic-keybinding-behavior = 2;
      active-window-hint = 1;
      monitor-switch-grace-period = true;
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
    own-api-translate = false;
    use-default-own-key = false;
    appid = "34f3635c44f16c3c385e875bdbbfb445";
    position-in-panel = "right";
    position-index = 0;
    show-text-in-panel = true;
    show-comment-in-panel = true;
    show-sunrise-in-panel = true;
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

  # ddterm
  "org/gnome/shell/extensions/ddterm" = {
    window-monitor = "current";
    show-animation-duration = 0.1;
    theme-variant = "dark";
  };
  };

  # Home Enviorment Packages
  home.packages = with pkgs; [
  gnomeExtensions.dash-to-panel
  gnomeExtensions.clipboard-indicator
  gnomeExtensions.tiling-assistant
  gnomeExtensions.openweather
  gnomeExtensions.ddterm
  ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}

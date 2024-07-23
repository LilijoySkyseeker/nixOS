{ config, pkgs, pkgs-unstable, lib, ... }:
{ 
# Home Manager needs a bit of information about you and the paths it should
# manage.
  home.username = "lilijoy";
  home.homeDirectory = "/home/lilijoy";

# Allow Unfree
  nixpkgs.config.allowUnfree = true;

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
      proc_per_core = true;
      proc_sorting = "cpu direct";
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
      nsr.body = "
        nix shell nixpkgs/nixos-unstable#$argv[1] --command $argv
        ";
      ns.body = "
        nix shell 'nixpkgs/nixos-unstable#'{$argv}
      ";
      nhu.body = "
        git add --all && nh os build --update && git add --all
        ";
      nht.body = "
        git add --all && nh os test
        ";
      nhb.body = "
        git add --all && git diff --staged | bat --paging always --pager less && git commit -a && nh os boot && git push
        ";
      nhs.body = "
        git add --all && git diff --staged | bat --paging always --pager less && git commit -a && nh os switch && git push
        ";
      gds.body = "
        git add --all && git diff --staged | bat --paging always --pager less
        ";
    };
    shellAliases = {
      e = "eza --group-directories-first --header --git --icons --all --long --mounts";
      et = "eza --tree --group-directories-first --header --git --icons --all --long --mounts";
      etl = "eza --tree --group-directories-first --header --git --icons --all --long --mounts --level";
      rsync = "rsync --verbose --recursive --progress --human-readable";
    };
    shellAbbrs = {

    };
  };

# bat
  programs.bat = {
    enable = true;
    config = {
      pager = "never";
    };
  };

# eza
  programs.eza = {
    enable = true;
    enableBashIntegration = false;
    enableFishIntegration = false;
  };

# NVIM
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    extraConfig = ''
      "     set langmap=qq,ww,fe,pr,bt,jy,lu,ui,yo,\\;p,aa,rs,sd,tf,gg,mh,nj,ek,il,o\\;,xz,cx,dc,vv,zb,kn,hm,QQ,WW,FE,PR,BT,JY,LU,UI,YO,:P,AA,RS,SD,TF,GG,MH,NJ,EK,IL,O:,XZ,CX,DC,VV,ZB,KN,HM

      nmap j gj
      nmap k gk
      nmap H ^
      nmap L $

      xnoremap p pgvy

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

      "      set relativenumber

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

      set foldmethod=indent
      set nofoldenable

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
    "org/gnome/mutter" = {
      dynamic-workspaces = true;
      workspaces-only-on-primary = true;
      check-alive-timeout = "uint32 60000";
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
      ];
    };
  };

# Gnome extension packages
  home.packages =
    (with pkgs.gnomeExtensions; [ # STABLE
      dash-to-panel
      clipboard-indicator
      tiling-assistant
      ddterm
    ])
    ++
    (with pkgs-unstable.gnomeExtensions; [ # UNSTABLE
      openweather-refined
    ]);

# Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}


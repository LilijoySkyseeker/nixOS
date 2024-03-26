{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "lilijoy";
  home.homeDirectory = "/home/lilijoy";

  imports = [
  ../../modules/home-manager/tools/git.nix

  ];

  # Allow Unfree
  nixpkgs.config.allowUnfree = true;

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
      color_theme = "night_owl";
      update_ms = 1000;
      cpu_single_graph = true;
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

    '';
    plugins = [
      { name = "grc"; src = pkgs.fishPlugins.grc.src; }
      { name = "tide"; src = pkgs.fishPlugins.tide.src; }
    ];
  };

  # NVIM
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    extraConfig = ''
      set langmap=qq,ww,fe,pr,bt,jy,lu,ui,yo,\\;p,aa,rs,sd,tf,gg,mh,nj,ek,il,o\\;,xz,cx,dc,vv,zb,kn,hm,QQ,WW,FE,PR,BT,JY,LU,UI,YO,:P,AA,RS,SD,TF,GG,MH,NJ,EK,IL,O:,XZ,CX,DC,VV,ZB,KN,HM

      nmap j gj
      nmap k gk

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
      "nnoremap <CR> :noh<CR><CR>:<backspace>

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
      color-scheme = "prefer-dark";
      enable-hot-corners = false;
      show-battery-percentage = true;
    };
    "org/gtk/gtk4/settings/file-chooser" = {
      show-hidden = true;
    };
    "org/gnome/desktop/peripherals/mouse" = {
      accel-profile = "flat";
    };
    "org/gnome/shell" = {
      last-selected-power-profile = "performance";
      disable-user-extensions = false;
      enabled-extensions = [
        "launch-new-instance@gnome-shell-extensions.gcampax.github.com"
        "dash-to-panel@jderose9.github.com"
        "appindicatorsupport@rgcjonas.gmail.com"
        "gsconnect@andyholmes.github.io"
        "clipboard-indicator@tudmotu.com"
        "forge@jmmaranan.com"
      ];
    };
    "org/gnome/mutter" = {
      dynamic-workspaces = true;
      workspaces-only-on-primary = true;
    };
    "org/gnome/settings-daemon/plugins/power" = {
      idle-dim = false;
      sleep-inactive-battery-type = "nothing";
      sleep-inactive-ac-type = "nothing";
      power-button-action = "interactive";
    };
#    "org/gnome/desktop/session" = {
#      idle-delay = "uint32 0";
#    };
    "org/gnome/desktop/wm/preferences" = {
      focus-mode = "sloppy";
      auto-raise = true;
    };
#    "org/gnome/desktop/wm/keybindings" = {
#      close = ["<Shift><Super>q"];
#      switch-to-workspace-left = ["<Shift><Super>1"];
#      switch-to-workspace-right = ["<Shift><Super>2"];
#    };

    # Dash to Panel
    "org/gnome/shell/extensions/dash-to-panel" = {
      multi-monitors = false;
#      panel-sizes = {"0":32,"1":32,"2":32};
#      panel-element-positions = {"0":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}],"1":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}],"2":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}]};
      animate-appicon-hover = true;
      show-favorites = false;
      group-apps = false;
    };

    # Clipboard Indicator
    "org/gnome/shell/extensions/clipboard-indicator" = {
      enable-keybindings = false;
      history-size = "100";
    };

    # Forge
    "org/gnome/shell/extensions/forge" = {
      tabbed-tiling-mode-enabled = false;
      stacked-tiling-mode-enabled = false;
    };



  };

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    gnome-extension-manager
    baobab # gnome disk usage utilty
    gnome.gnome-tweaks
    discord
    bitwarden
    thunderbird
    eclipses.eclipse-java
    vscode-fhs
    nicotine-plus
    cider
    prismlauncher
    kdenlive
    qbittorrent
    jellyfin-media-player


  gnomeExtensions.dash-to-panel
#  gnomeExtensions.appindicatorsupport  # tempory error
  gnomeExtensions.gsconnect
  gnomeExtensions.clipboard-indicator
  gnomeExtensions.forge
  ];

  home.file = {

  };

  home.sessionVariables = {

  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}

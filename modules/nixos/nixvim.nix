{inputs, ...}: {
  imports = [
    inputs.nixvim.nixosModules.nixvim
  ];

  # nixvim config
  programs.nixvim = {
    enable = true;
    clipboard.providers.xclip.enable = true;
    clipboard.register = "unnamedplus";
    globals.mapleader = " ";
    viAlias = true;
    vimAlias = true;
    options = {
    };
    plugins = {
      nix.enable = true;
      lualine.enable = true;
      lsp = {
        enable = true;
        servers = {
          nil_ls.enable = true;
        };
      };
    };
    extraConfigVim = ''
      nmap j gj
      nmap k gk
      nmap H ^
      nmap L $

      xnoremap p pgvy

      syntax on

      set fileformat=unix
      set encoding=UTF-8

      set tabstop=2
      set softtabstop=2
      set shiftwidth=2
      set autoindent
      set smartindent
      set smarttab
      set expandtab

      set list
      set listchars=tab:>-,trail:~,extends:>,precedes:<

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

      set ignorecase
      set smartcase
      set incsearch
      set hlsearch

      set mouse=a

      set foldmethod=indent
      set nofoldenable
    '';
  };
}

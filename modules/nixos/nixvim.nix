{ inputs, lib, ... }:
{
  imports = [ inputs.nixvim.nixosModules.nixvim ];

  programs.neovim = {
    enable = true;
    defaultEditor = lib.mkForce true;
  };

  # nixvim config
  programs.nixvim = {
    enable = true;
    clipboard.providers.xclip.enable = true;
    clipboard.register = "unnamedplus";
    globals.mapleader = " ";
    viAlias = true;
    vimAlias = true;
    opts = { };
    plugins = {
      nix.enable = true;
      lualine.enable = true;
      lsp = {
        enable = true;
        servers = {
          nil_ls.enable = false; # nix
          nixd = {
            enable = true;
            extraOptions = {
              nixpkgs.expr = "import <nixpkgs> { }";
              formatting.command = "nixfmt-rfc-style";
              options = {
                nixos.expr = ''(builtins.getFlake "/home/lilijoy/dotfiles").nixosConfigurations.CONFIGNAME.options'';
                home_manager.expr = ''(builtins.getFlake "/home/lilijoy/dotfiles").homeConfigurations.CONFIGNAME.options'';
              };
            };
          };
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
    extraConfigLua = ''
      -- Extra nvim-lspconfig configuration
      -- Common LSP key mappings
      local function set_cmn_lsp_keybinds()
      	local lsp_keybinds = {
      		{
      			key = "K",
      			action = vim.lsp.buf.hover,
      			options = {
      				buffer = 0,
      				desc = "hover [K]noledge with LSP",
      			},
      		},
      		{
      			key = "gd",
      			action = vim.lsp.buf.definition,
      			options = {
      				buffer = 0,
      				desc = "[g]o to [d]efinition with LSP",
      			},
      		},
      		{
      			key = "gy",
      			action = vim.lsp.buf.type_definition,
      			options = {
      				buffer = 0,
      				desc = "[g]o to t[y]pe definition with LSP",
      			},
      		},
      		{
      			key = "gi",
      			action = vim.lsp.buf.implementation,
      			options = {
      				buffer = 0,
      				desc = "[g]o to [i]mplementation with LSP",
      			},
      		},
      		{
      			key = "<leader>dj",
      			action = vim.diagnostic.goto_next,
      			options = {
      				buffer = 0,
      				desc = "Go to next [d]iagnostic with LSP",
      			},
      		},
      		{
      			key = "<leader>dk",
      			action = vim.diagnostic.goto_prev,
      			options = {
      				buffer = 0,
      				desc = "Go to previous [d]iagnostic with LSP",
      			},
      		},
      		{
      			key = "<leader>r",
      			action = vim.lsp.buf.rename,
      			options = {
      				buffer = 0,
      				desc = "[r]ename variable with LSP",
      			},
      		},
      	}

      	for _, bind in ipairs(lsp_keybinds) do
      		vim.keymap.set("n", bind.key, bind.action, bind.options)
      	end
      end

      -- Additional lsp-config
      capabilities.textDocument.completion.completionItem.snippetSupport = true

      -- Individual LSP configs

      -- Nix LSP
      require("lspconfig").nixd.setup({
      	on_attach = function()
      		set_cmn_lsp_keybinds()
      	end,
      	settings = {
      		nixd = {
      			formatting = {
      				command = { "nixfmt" },
      			},
      		},
      	},
      })
    '';
  };
}

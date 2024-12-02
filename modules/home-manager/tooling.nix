{ pkgs, lib, ... }:
{
  # Git
  programs.git = {
    enable = true;
    userName = "LilijoySkyseeker";
    userEmail = "lilijoyskyseeker@gmail.com";
  };

  # fzf
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
  };

  # KDE Connect
  services.kdeconnect = {
    enable = true;
    indicator = true;
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
      nsr.body = "\nnix shell nixpkgs/nixos-unstable#$argv[1] --command $argv\n";
      ns.body = "\nnix shell 'nixpkgs/nixos-unstable#'{$argv}\n";
      nhu.body = "\ngit add --all && nh os build --update && git add --all\n";
      nht.body = "\ngit add --all && nh os test\n";
      nhb.body = "\ngit add --all && nh os boot && git diff --staged | bat --paging always --pager less && git commit -a && git push\n";
      nhs.body = "\ngit add --all && nh os switch && git diff --staged | bat --paging always --pager less && git commit -a && git push\n";
      gds.body = "\ngit add --all && git diff --staged | bat --paging always --pager less\n";
    };
    shellAliases = {
      e = "eza --group-directories-first --header --git --git-ignore --icons --all --long --mounts";
      et = "eza --tree --group-directories-first --header --git --git-ignore --icons --all --long --mounts";
      etl = "eza --tree --group-directories-first --header --git --git-ignore --icons --all --long --mounts --level";
    };
    shellAbbrs = {
      rsync = "rsync --verbose --recursive --progress --human-readable";
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
}

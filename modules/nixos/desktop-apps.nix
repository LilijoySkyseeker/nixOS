_: {
  flake.modules.nixos."desktop-apps" =
    {
      pkgs-unstable,
      inputs,
      vars,
      ...
    }:
    {
      environment.systemPackages = with pkgs-unstable; [
        ripgrep
        gh
        codex
        nodejs
        nixos-anywhere
        ssh-to-age
        caligula
        scrcpy
        vipsdisp
        yt-dlp
        android-tools

        bitwarden-desktop
        thunderbird
        vscode-fhs
        easyeffects
        qpwgraph
        libreoffice
        vlc
        r2modman
        nicotine-plus
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
      # gid pinned off its default (999): nfs-homelab-mounts.nix needs 999 for
      # "multimedia" to match homelab's NFS /storage group
      users.groups.flatpak.gid = vars.gids.flatpak;
      services.flatpak = {
        enable = true;
        packages = [
          "info.beyondallreason.bar"
        ];
      };
    };
}

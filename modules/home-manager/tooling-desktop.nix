{ config, ... }:
let
  ips = config.flake.vars.tailnetIPv4;
in
{
  flake.modules.homeManager."tooling-desktop" =
    {
      lib,
      pkgs-stable,
      pkgs-unstable,
      config,
      ...
    }:
    {
      # bash: unknown command fetches and runs it from nixpkgs; desktop only (docs/accepted-risks.md AR-4)
      programs.bash.initExtra = ''
        command_not_found_handle() { comma "$@"; }
      '';

      # KDE Connect
      services.kdeconnect = {
        enable = true;
        indicator = true;
      };

      # kde connect: broadcast and mDNS don't cross tailscale0, so announce to the PCs
      # directly; replaces IPs added in the app, the phone's app needs both by hand
      home.activation.kdeconnectCustomDevices = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs-unstable.kdePackages.kconfig}/bin/kwriteconfig6 --file kdeconnect/config \
          --group General --key customDevices "${ips.torrent},${ips.thinkpad}"
      '';

      # OBS Studio
      programs.obs-studio = {
        enable = true;
        plugins = with pkgs-stable.obs-studio-plugins; [ obs-pipewire-audio-capture ];
      };

      # Obsidian
      programs.obsidian = {
        enable = true;
        package = pkgs-unstable.obsidian;
        cli.enable = true;
      };

      # Firefox
      programs.firefox = {
        enable = true;
        configPath = "${config.xdg.configHome}/mozilla/firefox";
      };
    };
}

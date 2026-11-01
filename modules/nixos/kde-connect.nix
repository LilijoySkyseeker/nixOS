{ config, ... }:
let
  ips = config.flake.vars.tailnetIPv4;
in
{
  flake.modules.nixos."kde-connect" = { lib, ... }: {
    home-manager.users.lilijoy = { lib, pkgs-unstable, ... }: {
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
    };

    programs.kdeconnect = {
      enable = true;
    };

    # scope kde connect to the tailnet: its module opens 1714-1764 host-wide with
    # no openFirewall toggle, so force the host-wide lists empty and re-add per interface
    # mkForce empties the *whole* list: a range another module adds vanishes silently;
    # the rendered firewall script should show dport 1714:1764 and no other range
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
  };
}

_: {
  flake.modules.nixos.kde =
    { pkgs-stable, ... }:
    {
      services.xserver.enable = true;
      services.displayManager.sddm.enable = true;
      services.displayManager.sddm.wayland.enable = true;
      services.desktopManager.plasma6.enable = true;

      environment.systemPackages = with pkgs-stable; [
        kdePackages.filelight
        qalculate-qt
      ];

      programs.partition-manager.enable = true;

      # TODO: drop when polkit-kde-agent-1 shows the requesting command upstream
      nixpkgs.overlays = [
        (_: prev: {
          kdePackages = prev.kdePackages.overrideScope (
            _: kprev: {
              polkit-kde-agent-1 = kprev.polkit-kde-agent-1.overrideAttrs (old: {
                patches = (old.patches or [ ]) ++ [ ./polkit-kde-agent-show-requester.patch ];
              });
            }
          );
        })
      ];
    };
}

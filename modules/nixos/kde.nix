_: {
  flake.modules.nixos.kde =
    { pkgs-stable, ... }:
    {
      # KDE Plasma
      services.xserver.enable = true;
      services.displayManager.sddm.enable = true;
      services.displayManager.sddm.wayland.enable = true;
      services.desktopManager.plasma6.enable = true;

      # System installed pkgs
      environment.systemPackages = with pkgs-stable; [
        qalculate-qt
      ];

      # kde partition manager
      programs.partition-manager.enable = true;

      # polkit-kde-agent: show the command line of the process asking, since
      # run0's prompt only names a randomly named transient unit
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

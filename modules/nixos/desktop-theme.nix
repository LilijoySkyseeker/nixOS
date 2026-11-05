_: {
  flake.modules.nixos."desktop-theme" = { pkgs-unstable, inputs, ... }: {
    imports = [ inputs.stylix.nixosModules.stylix ];
    stylix = {
      enable = true;
      autoEnable = true;
      # source path, not a package: the scheme itself needs no eval-time build
      base16Scheme = "${inputs.stylix.inputs.tinted-schemes}/base16/gruvbox-dark-soft.yaml";
      image = ../../files/gruvbox-dark-rainbow.png;
      polarity = "dark";
      cursor.package = pkgs-unstable.capitaine-cursors-themed;
      cursor.name = "Capitaine Cursors";
      cursor.size = 24;
      fonts = {
        monospace = {
          package = pkgs-unstable.nerd-fonts.jetbrains-mono;
          name = "JetBrainsMono Nerd Font Mono";
        };
        sansSerif = {
          package = pkgs-unstable.dejavu_fonts;
          name = "DejaVu Sans";
        };
        serif = {
          package = pkgs-unstable.dejavu_fonts;
          name = "DejaVu Serif";
        };
      };
    };
    home-manager.users.lilijoy = {
      stylix.targets.firefox.profileNames = [ "default" ];
      # qtct set QT_STYLE_OVERRIDE=kvantum, which broke Plasma 6.7 QML (black desktop); Plasma themes Qt itself.
      stylix.targets.qt.enable = false;
    };
  };
}

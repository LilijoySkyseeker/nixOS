{ config, inputs, ... }:
let
  scheme = "${inputs.stylix.inputs.tinted-schemes}/base16/gruvbox-dark-soft.yaml";
  # parsed in pure Nix (no IFD), so the servers, which have no stylix, get it too
  c = (config.flake.pkgsUnstable.callPackage inputs.stylix.inputs.base16.lib { }).mkSchemeAttrs {
    yaml = scheme;
    use-ifd = "never";
  };
in
{
  # one colour scheme for stylix on the PCs and for the shell on every host
  flake.theme = {
    inherit scheme;
    # colour names as stylix's starship target maps them, plus base01/base02
    palette = with c.withHashtag; {
      black = base00;
      inherit base01 base02 base04;
      bright-black = base03;
      white = base05;
      bright-white = base07;
      red = base08;
      orange = base09;
      yellow = base0A;
      green = base0B;
      cyan = base0C;
      blue = base0D;
      purple = base0E;
      brown = base0F;
    };
    # each host's name is written in its own colour in the prompt and the
    # login summary; vps red because it's public-facing
    hostColours = {
      torrent = "cyan";
      thinkpad = "purple";
      homelab = "orange";
      vps = "red";
    };
  };
}

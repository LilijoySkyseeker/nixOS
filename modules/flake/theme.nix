{
  config,
  inputs,
  lib,
  ...
}:
let
  scheme = "${inputs.stylix.inputs.tinted-schemes}/base16/gruvbox-dark-soft.yaml";
  # parsed in pure Nix (no IFD), so the servers, which have no stylix, get it too
  c = (config.flake.pkgsUnstable.callPackage inputs.stylix.inputs.base16.lib { }).mkSchemeAttrs {
    yaml = scheme;
    use-ifd = "never";
  };
  # stylix's starship target's names, plus base01, base02 and base04
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
in
{
  flake.theme = {
    inherit scheme palette;
    ansi =
      name:
      let
        h = lib.removePrefix "#" palette.${name};
        byte = i: toString (lib.fromHexString (builtins.substring i 2 h));
      in
      "\\e[0;38;2;${byte 0};${byte 2};${byte 4}m";
    hostColours = {
      torrent = "cyan";
      thinkpad = "purple";
      homelab = "orange";
      vps = "red";
    };
  };
}

{ ... }:
{
  # fix for stupid home manager bug:  https://github.com/nix-community/home-manager/issues/4199#issuecomment-1620657055
  home.file."/home/lilijoy/.gtkrc-2.0".force = true;

  # Plasma Manager: `nix run github:nix-community/plasma-manager`
  programs.plasma = {
    enable = false; # DISABLED
    shortcuts = {
      "KDE Keyboard Layout Switcher"."Switch to Next Keyboard Layout" =
        "Meta+Space\\, Meta+Alt+K\\, ,Meta+Alt+K,Switch to Next Keyboard Layout";
      "kwin"."Overview" = [
        "Meta"
        "Alt+F1"
        "Meta+W,Meta+W,Toggle Overview"
      ];
      "kwin"."Window Close" = [
        "Meta+Q"
        "Alt+F4\\, Alt+F4\\, ,Alt+F4,Close Window"
      ];
      "kwin"."Window Maximize" = "Meta+Shift+Up\\, Meta+PgUp\\, ,Meta+PgUp,Maximize Window";
      "plasmashell"."activate application launcher" = [
        "none,Meta"
        "Alt+F1,Activate Application Launcher"
      ];
    };
    configFile = {
      "kcminputrc"."Keyboard"."RepeatDelay" = 250;
      "kcminputrc"."Libinput/9494/303/Cooler Master Technology Inc. MM710 Gaming Mouse"."PointerAccelerationProfile" =
        1;
      "ksmserverrc"."General"."confirmLogout" = false;
      "kwinrc"."NightColor"."Active" = true;
      "kwinrc"."NightColor"."LatitudeFixed" = 37.78412;
      "kwinrc"."NightColor"."LongitudeFixed" = "-79.44253";
      "kwinrc"."NightColor"."Mode" = "Location";
      "kwinrc"."NightColor"."NightTemperature" = 3500;
      "kwinrc"."Windows"."FocusPolicy" = "FocusFollowsMouse";
      "kwinrc"."Xwayland"."Scale" = 1;
      "kxkbrc"."Layout"."DisplayNames" = ",";
      "kxkbrc"."Layout"."LayoutList" = "us,us";
      "kxkbrc"."Layout"."Use" = true;
      "kxkbrc"."Layout"."VariantList" = ",colemak_dh";
      "plasma-localerc"."Formats"."LANG" = "en_US.UTF-8";
      "plasmanotifyrc"."Applications/firefox"."Seen" = true;
      "plasmanotifyrc"."Applications/vesktop"."Seen" = true;
      "spectaclerc"."General"."autoSaveImage" = true;
      "spectaclerc"."GuiConfig"."captureMode" = 0;
      "spectaclerc"."ImageSave"."imageCompressionQuality" = 100;
      "spectaclerc"."ImageSave"."translatedScreenshotsFolder" = "Screenshots";
      "spectaclerc"."VideoSave"."translatedScreencastsFolder" = "Screencasts";
    };
    dataFile = {
      "dolphin/view_properties/global/.directory"."Dolphin"."SortHiddenLast" = true;
      "dolphin/view_properties/global/.directory"."Dolphin"."SortOrder" = 1;
      "dolphin/view_properties/global/.directory"."Dolphin"."ViewMode" = 1;
      "dolphin/view_properties/global/.directory"."Settings"."HiddenFilesShown" = true;
    };
  };
}

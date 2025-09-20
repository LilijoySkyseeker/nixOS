{ ... }:
{
  # fix for stupid home manager bug:  https://github.com/nix-community/home-manager/issues/4199#issuecomment-1620657055
  # home.file."/home/lilijoy/.tkrc-2.0".force = true;

  # Plasma Manager: `nix run github:nix-community/plasma-manager`
  programs.plasma = {
    enable = true;
    shortcuts = {
      "ActivityManager"."switch-to-activity-6bb29d64-4a53-48df-9e22-ad1363fdf2d6" = [ ];
      "KDE Keyboard Layout Switcher"."Switch keyboard layout to English (Colemak-DH)" = [ ];
      "KDE Keyboard Layout Switcher"."Switch keyboard layout to English (US)" = [ ];
      "KDE Keyboard Layout Switcher"."Switch keyboard layout to English (intl., with AltGr dead keys)" =
        "none,none,Cambiar la distribución de teclado a English (intl.\\, with AltGr dead keys)";
      "KDE Keyboard Layout Switcher"."Switch keyboard layout to Spanish (Latin American)" = [ ];
      "KDE Keyboard Layout Switcher"."Switch to Last-Used Keyboard Layout" = "Meta+Alt+L";
      "KDE Keyboard Layout Switcher"."Switch to Next Keyboard Layout" =
        "Meta+Space,Meta+Alt+K,Cambiar a la siguiente distribución de teclado";
      "kaccess"."Toggle Screen Reader On and Off" = "Meta+Alt+S";
      "kcm_touchpad"."Disable Touchpad" = "Touchpad Off";
      "kcm_touchpad"."Enable Touchpad" = "Touchpad On";
      "kcm_touchpad"."Toggle Touchpad" = [
        "Touchpad Toggle"
        "Meta+Ctrl+Zenkaku Hankaku,Touchpad Toggle"
        "Touchpad Toggle"
        "Meta+Ctrl+Touchpad Toggle"
        "Meta+Ctrl+Zenkaku Hankaku,Toggle Touchpad"
      ];
      "kmix"."decrease_microphone_volume" = "Microphone Volume Down";
      "kmix"."decrease_volume" = "Volume Down";
      "kmix"."decrease_volume_small" = "Shift+Volume Down";
      "kmix"."increase_microphone_volume" = "Microphone Volume Up";
      "kmix"."increase_volume" = "Volume Up";
      "kmix"."increase_volume_small" = "Shift+Volume Up";
      "kmix"."mic_mute" = [
        "Microphone Mute"
        "Meta+Volume Mute,Microphone Mute"
        "Meta+Volume Mute,Silenciar el micrófono"
      ];
      "kmix"."mute" = "Volume Mute";
      "ksmserver"."Halt Without Confirmation" = "Meta+Ctrl+Alt+Shift+S,,Apagar sin confirmación";
      "ksmserver"."Lock Session" = [
        "Meta+L"
        "Screensaver,Meta+L"
        "Screensaver,Bloquear la sesión"
      ];
      "ksmserver"."Log Out" = "Ctrl+Alt+Del";
      "ksmserver"."Log Out Without Confirmation" = "none,,Cerrar sesión sin confirmación";
      "ksmserver"."LogOut" = "none,,Cerrar sesión";
      "ksmserver"."Reboot" = "none,,Reiniciar";
      "ksmserver"."Reboot Without Confirmation" = "Meta+Ctrl+Alt+Shift+R,,Reiniciar sin confirmación";
      "ksmserver"."Shut Down" = "none,,Apagar";
      "kwin"."Activate Window Demanding Attention" = "Meta+Ctrl+A";
      "kwin"."Cycle Overview" = [ ];
      "kwin"."Cycle Overview Opposite" = [ ];
      "kwin"."Decrease Opacity" = "none,,Disminuir opacidad de la ventana activa en un 5%";
      "kwin"."Edit Tiles" = "Meta+T";
      "kwin"."Expose" = "Ctrl+F9";
      "kwin"."ExposeAll" = [
        "Ctrl+F10"
        "Launch (C),Ctrl+F10"
        "Launch (C),Conmutar las ventanas presentes (todos los escritorios)"
      ];
      "kwin"."ExposeClass" = "Ctrl+F7";
      "kwin"."ExposeClassCurrentDesktop" = [ ];
      "kwin"."Grid View" = "Meta+G";
      "kwin"."Increase Opacity" = "none,,Incrementar opacidad de la ventana activa en un 5%";
      "kwin"."Kill Window" = "Meta+Ctrl+Esc";
      "kwin"."Move Tablet to Next Output" = [ ];
      "kwin"."MoveMouseToCenter" = "Meta+F6";
      "kwin"."MoveMouseToFocus" = "Meta+F5";
      "kwin"."MoveZoomDown" = [ ];
      "kwin"."MoveZoomLeft" = [ ];
      "kwin"."MoveZoomRight" = [ ];
      "kwin"."MoveZoomUp" = [ ];
      "kwin"."Overview" = [
        "Meta+F1"
        "Meta"
        "Alt+F1"
        "Meta+W,Meta+W,Conmutar a la vista general"
      ];
      "kwin"."Setup Window Shortcut" = "none,,Configurar el atajo de teclado de la ventana";
      "kwin"."Show Desktop" = "Meta+D";
      "kwin"."Suspend Compositing" = "Alt+Shift+F12";
      "kwin"."Switch One Desktop Down" = "Meta+Ctrl+Down";
      "kwin"."Switch One Desktop Up" = "Meta+Ctrl+Up";
      "kwin"."Switch One Desktop to the Left" = "Meta+Ctrl+Left";
      "kwin"."Switch One Desktop to the Right" = "Meta+Ctrl+Right";
      "kwin"."Switch Window Down" = "Meta+Alt+Down";
      "kwin"."Switch Window Left" = "Meta+Alt+Left";
      "kwin"."Switch Window Right" = "Meta+Alt+Right";
      "kwin"."Switch Window Up" = "Meta+Alt+Up";
      "kwin"."Switch to Desktop 1" = "Ctrl+F1";
      "kwin"."Switch to Desktop 10" = "none,,Cambiar al escritorio 10";
      "kwin"."Switch to Desktop 11" = "none,,Cambiar al escritorio 11";
      "kwin"."Switch to Desktop 12" = "none,,Cambiar al escritorio 12";
      "kwin"."Switch to Desktop 13" = "none,,Cambiar al escritorio 13";
      "kwin"."Switch to Desktop 14" = "none,,Cambiar al escritorio 14";
      "kwin"."Switch to Desktop 15" = "none,,Cambiar al escritorio 15";
      "kwin"."Switch to Desktop 16" = "none,,Cambiar al escritorio 16";
      "kwin"."Switch to Desktop 17" = "none,,Cambiar al escritorio 17";
      "kwin"."Switch to Desktop 18" = "none,,Cambiar al escritorio 18";
      "kwin"."Switch to Desktop 19" = "none,,Cambiar al escritorio 19";
      "kwin"."Switch to Desktop 2" = "Ctrl+F2";
      "kwin"."Switch to Desktop 20" = "none,,Cambiar al escritorio 20";
      "kwin"."Switch to Desktop 3" = "Ctrl+F3";
      "kwin"."Switch to Desktop 4" = "Ctrl+F4";
      "kwin"."Switch to Desktop 5" = "none,,Cambiar al escritorio 5";
      "kwin"."Switch to Desktop 6" = "none,,Cambiar al escritorio 6";
      "kwin"."Switch to Desktop 7" = "none,,Cambiar al escritorio 7";
      "kwin"."Switch to Desktop 8" = "none,,Cambiar al escritorio 8";
      "kwin"."Switch to Desktop 9" = "none,,Cambiar al escritorio 9";
      "kwin"."Switch to Next Desktop" = "none,,Cambiar al siguiente escritorio";
      "kwin"."Switch to Next Screen" = "none,,Cambiar a la siguiente pantalla";
      "kwin"."Switch to Previous Desktop" = "none,,Cambiar al escritorio anterior";
      "kwin"."Switch to Previous Screen" = "none,,Cambiar a la pantalla anterior";
      "kwin"."Switch to Screen 0" = "none,,Cambiar a la pantalla 0";
      "kwin"."Switch to Screen 1" = "none,,Cambiar a la pantalla 1";
      "kwin"."Switch to Screen 2" = "none,,Cambiar a la pantalla 2";
      "kwin"."Switch to Screen 3" = "none,,Cambiar a la pantalla 3";
      "kwin"."Switch to Screen 4" = "none,,Cambiar a la pantalla 4";
      "kwin"."Switch to Screen 5" = "none,,Cambiar a la pantalla 5";
      "kwin"."Switch to Screen 6" = "none,,Cambiar a la pantalla 6";
      "kwin"."Switch to Screen 7" = "none,,Cambiar a la pantalla 7";
      "kwin"."Switch to Screen Above" = "none,,Cambiar a la pantalla superior";
      "kwin"."Switch to Screen Below" = "none,,Cambiar a la pantalla inferior";
      "kwin"."Switch to Screen to the Left" = "none,,Cambiar a la pantalla de la izquierda";
      "kwin"."Switch to Screen to the Right" = "none,,Cambiar a la pantalla de la derecha";
      "kwin"."Toggle Night Color" = [ ];
      "kwin"."Toggle Window Raise/Lower" = "none,,Conmutar pasar la ventana al frente/atrás";
      "kwin"."Walk Through Windows" = "Alt+Tab";
      "kwin"."Walk Through Windows (Reverse)" = "Alt+Shift+Tab";
      "kwin"."Walk Through Windows Alternative" = "none,,Recorrer las ventanas de modo alternativo";
      "kwin"."Walk Through Windows Alternative (Reverse)" =
        "none,,Recorrer las ventanas de modo alternativo (hacia atrás)";
      "kwin"."Walk Through Windows of Current Application" =
        "none,Alt+`,Recorrer las ventanas de la aplicación actual";
      "kwin"."Walk Through Windows of Current Application (Reverse)" = "Alt+~";
      "kwin"."Walk Through Windows of Current Application Alternative" =
        "none,,Recorrer las ventanas de la aplicación actual de modo alternativo";
      "kwin"."Walk Through Windows of Current Application Alternative (Reverse)" =
        "none,,Recorrer las ventanas de la aplicación actual de modo alternativo (hacia atrás)";
      "kwin"."Window Above Other Windows" = "none,,Mantener la ventana sobre las demás";
      "kwin"."Window Below Other Windows" = "none,,Mantener la ventana bajo las demás";
      "kwin"."Window Close" = [
        "Meta+Shift+Q"
        "Alt+F4,Alt+F4,Cerrar la ventana"
      ];
      "kwin"."Window Custom Quick Tile Bottom" =
        "none,,Situar ventana en mosaico personalizado en la parte inferior";
      "kwin"."Window Custom Quick Tile Left" =
        "none,,Situar ventana en mosaico personalizado a la izquierda";
      "kwin"."Window Custom Quick Tile Right" =
        "none,,Situar ventana en mosaico personalizado a la derecha";
      "kwin"."Window Custom Quick Tile Top" =
        "none,,Situar ventana en mosaico personalizado en la parte superior";
      "kwin"."Window Fullscreen" = "none,,Ventana en pantalla completa";
      "kwin"."Window Grow Horizontal" = "none,,Expandir la ventana horizontalmente";
      "kwin"."Window Grow Vertical" = "none,,Expandir la ventana verticalmente";
      "kwin"."Window Lower" = "none,,Mover la ventana hacia atrás";
      "kwin"."Window Maximize" = [
        "Meta+PgUp"
        "Meta+Shift+Up,Meta+PgUp,Maximizar la ventana"
      ];
      "kwin"."Window Maximize Horizontal" = "none,,Maximizar la ventana horizontalmente";
      "kwin"."Window Maximize Vertical" = "none,,Maximizar la ventana verticalmente";
      "kwin"."Window Minimize" = "Meta+PgDown";
      "kwin"."Window Move" = "none,,Mover la ventana";
      "kwin"."Window Move Center" = "none,,Mover ventana al centro";
      "kwin"."Window No Border" = "none,,Conmutar barra de título y marco de la ventana";
      "kwin"."Window On All Desktops" = "none,,Mantener la ventana en todos los escritorios";
      "kwin"."Window One Desktop Down" = "Meta+Ctrl+Shift+Down";
      "kwin"."Window One Desktop Up" = "Meta+Ctrl+Shift+Up";
      "kwin"."Window One Desktop to the Left" = "Meta+Ctrl+Shift+Left";
      "kwin"."Window One Desktop to the Right" = "Meta+Ctrl+Shift+Right";
      "kwin"."Window One Screen Down" = "none,,Mover ventana una pantalla abajo";
      "kwin"."Window One Screen Up" = "none,,Mover ventana una pantalla arriba";
      "kwin"."Window One Screen to the Left" = "none,,Mover ventana una pantalla a la izquierda";
      "kwin"."Window One Screen to the Right" = "none,,Mover ventana una pantalla a la derecha";
      "kwin"."Window Operations Menu" = "Alt+F3";
      "kwin"."Window Pack Down" = "none,,Mover la ventana abajo";
      "kwin"."Window Pack Left" = "none,,Mover la ventana a la izquierda";
      "kwin"."Window Pack Right" = "none,,Mover la ventana a la derecha";
      "kwin"."Window Pack Up" = "none,,Mover la ventana arriba";
      "kwin"."Window Quick Tile Bottom" = "Meta+Down";
      "kwin"."Window Quick Tile Bottom Left" =
        "none,,Situar la ventana en mosaico en la parte inferior izquierda";
      "kwin"."Window Quick Tile Bottom Right" =
        "none,,Situar la ventana en mosaico en la parte inferior derecha";
      "kwin"."Window Quick Tile Left" = "Meta+Left";
      "kwin"."Window Quick Tile Right" = "Meta+Right";
      "kwin"."Window Quick Tile Top" = "Meta+Up";
      "kwin"."Window Quick Tile Top Left" =
        "none,,Situar la ventana en mosaico en la parte superior izquierda";
      "kwin"."Window Quick Tile Top Right" =
        "none,,Situar la ventana en mosaico en la parte superior derecha";
      "kwin"."Window Raise" = "none,,Mover la ventana hacia adelante";
      "kwin"."Window Resize" = "none,,Redimensionar la ventana";
      "kwin"."Window Shade" = "none,,Recoger la ventana";
      "kwin"."Window Shrink Horizontal" = "none,,Encoger la ventana horizontalmente";
      "kwin"."Window Shrink Vertical" = "none,,Encoger la ventana verticalmente";
      "kwin"."Window to Desktop 1" = "Ctrl+Shift+F1,,Ventana al escritorio 1";
      "kwin"."Window to Desktop 10" = "none,,Ventana al escritorio 10";
      "kwin"."Window to Desktop 11" = "none,,Ventana al escritorio 11";
      "kwin"."Window to Desktop 12" = "none,,Ventana al escritorio 12";
      "kwin"."Window to Desktop 13" = "none,,Ventana al escritorio 13";
      "kwin"."Window to Desktop 14" = "none,,Ventana al escritorio 14";
      "kwin"."Window to Desktop 15" = "none,,Ventana al escritorio 15";
      "kwin"."Window to Desktop 16" = "none,,Ventana al escritorio 16";
      "kwin"."Window to Desktop 17" = "none,,Ventana al escritorio 17";
      "kwin"."Window to Desktop 18" = "none,,Ventana al escritorio 18";
      "kwin"."Window to Desktop 19" = "none,,Ventana al escritorio 19";
      "kwin"."Window to Desktop 2" = "Ctrl+Shift+F2,,Ventana al escritorio 2";
      "kwin"."Window to Desktop 20" = "none,,Ventana al escritorio 20";
      "kwin"."Window to Desktop 3" = "Ctrl+Shift+F3,,Ventana al escritorio 3";
      "kwin"."Window to Desktop 4" = "Ctrl+Shift+F4,,Ventana al escritorio 4";
      "kwin"."Window to Desktop 5" = "none,,Ventana al escritorio 5";
      "kwin"."Window to Desktop 6" = "none,,Ventana al escritorio 6";
      "kwin"."Window to Desktop 7" = "none,,Ventana al escritorio 7";
      "kwin"."Window to Desktop 8" = "none,,Ventana al escritorio 8";
      "kwin"."Window to Desktop 9" = "none,,Ventana al escritorio 9";
      "kwin"."Window to Next Desktop" = "none,,Ventana al siguiente escritorio";
      "kwin"."Window to Next Screen" = "Meta+Shift+Right";
      "kwin"."Window to Previous Desktop" = "none,,Ventana al escritorio anterior";
      "kwin"."Window to Previous Screen" = "Meta+Shift+Left";
      "kwin"."Window to Screen 0" = "none,,Mover ventana a la pantalla 0";
      "kwin"."Window to Screen 1" = "none,,Mover ventana a la pantalla 1";
      "kwin"."Window to Screen 2" = "none,,Mover ventana a la pantalla 2";
      "kwin"."Window to Screen 3" = "none,,Mover ventana a la pantalla 3";
      "kwin"."Window to Screen 4" = "none,,Mover ventana a la pantalla 4";
      "kwin"."Window to Screen 5" = "none,,Mover ventana a la pantalla 5";
      "kwin"."Window to Screen 6" = "none,,Mover ventana a la pantalla 6";
      "kwin"."Window to Screen 7" = "none,,Mover ventana a la pantalla 7";
      "kwin"."disableInputCapture" = "none,Meta+Shift+Esc,Desactivar la captura de la entrada activa";
      "kwin"."karousel-column-move-end" = "Meta+Ctrl+Shift+End,none,Karousel: Move column to end";
      "kwin"."karousel-column-move-left" = "Meta+Ctrl+Shift+A,none,Karousel: Move column left";
      "kwin"."karousel-column-move-right" = "Meta+Ctrl+Shift+D,none,Karousel: Move column right";
      "kwin"."karousel-column-move-start" = "Meta+Ctrl+Shift+Home,none,Karousel: Move column to start";
      "kwin"."karousel-column-move-to-column-1" =
        "Meta+Ctrl+Shift+1,none,Karousel: Move column to position 1";
      "kwin"."karousel-column-move-to-column-10" = [ ];
      "kwin"."karousel-column-move-to-column-11" = [ ];
      "kwin"."karousel-column-move-to-column-12" = [ ];
      "kwin"."karousel-column-move-to-column-2" =
        "Meta+Ctrl+Shift+2,none,Karousel: Move column to position 2";
      "kwin"."karousel-column-move-to-column-3" =
        "Meta+Ctrl+Shift+3,none,Karousel: Move column to position 3";
      "kwin"."karousel-column-move-to-column-4" =
        "Meta+Ctrl+Shift+4,none,Karousel: Move column to position 4";
      "kwin"."karousel-column-move-to-column-5" =
        "Meta+Ctrl+Shift+5,none,Karousel: Move column to position 5";
      "kwin"."karousel-column-move-to-column-6" =
        "Meta+Ctrl+Shift+6,none,Karousel: Move column to position 6";
      "kwin"."karousel-column-move-to-column-7" =
        "Meta+Ctrl+Shift+7,none,Karousel: Move column to position 7";
      "kwin"."karousel-column-move-to-column-8" =
        "Meta+Ctrl+Shift+8,none,Karousel: Move column to position 8";
      "kwin"."karousel-column-move-to-column-9" =
        "Meta+Ctrl+Shift+9,none,Karousel: Move column to position 9";
      "kwin"."karousel-column-move-to-desktop-1" =
        "Meta+Ctrl+Shift+F1,none,Karousel: Move column to desktop 1";
      "kwin"."karousel-column-move-to-desktop-10" =
        "Meta+Ctrl+Shift+F10,none,Karousel: Move column to desktop 10";
      "kwin"."karousel-column-move-to-desktop-11" =
        "Meta+Ctrl+Shift+F11,none,Karousel: Move column to desktop 11";
      "kwin"."karousel-column-move-to-desktop-12" =
        "Meta+Ctrl+Shift+F12,none,Karousel: Move column to desktop 12";
      "kwin"."karousel-column-move-to-desktop-2" =
        "Meta+Ctrl+Shift+F2,none,Karousel: Move column to desktop 2";
      "kwin"."karousel-column-move-to-desktop-3" =
        "Meta+Ctrl+Shift+F3,none,Karousel: Move column to desktop 3";
      "kwin"."karousel-column-move-to-desktop-4" =
        "Meta+Ctrl+Shift+F4,none,Karousel: Move column to desktop 4";
      "kwin"."karousel-column-move-to-desktop-5" =
        "Meta+Ctrl+Shift+F5,none,Karousel: Move column to desktop 5";
      "kwin"."karousel-column-move-to-desktop-6" =
        "Meta+Ctrl+Shift+F6,none,Karousel: Move column to desktop 6";
      "kwin"."karousel-column-move-to-desktop-7" =
        "Meta+Ctrl+Shift+F7,none,Karousel: Move column to desktop 7";
      "kwin"."karousel-column-move-to-desktop-8" =
        "Meta+Ctrl+Shift+F8,none,Karousel: Move column to desktop 8";
      "kwin"."karousel-column-move-to-desktop-9" =
        "Meta+Ctrl+Shift+F9,none,Karousel: Move column to desktop 9";
      "kwin"."karousel-column-toggle-stacked" =
        "Meta+X,none,Karousel: Toggle stacked layout for focused column";
      "kwin"."karousel-column-width-decrease" = "Meta+Ctrl+-,none,Karousel: Decrease column width";
      "kwin"."karousel-column-width-increase" = "Meta+Ctrl++,none,Karousel: Increase column width";
      "kwin"."karousel-columns-squeeze-left" = [ ];
      "kwin"."karousel-columns-squeeze-right" =
        "Meta+Ctrl+D,none,Karousel: Squeeze right column onto the screen";
      "kwin"."karousel-columns-width-equalize" = [ ];
      "kwin"."karousel-cycle-preset-widths" = "Meta+R,none,Karousel: Cycle through preset column widths";
      "kwin"."karousel-cycle-preset-widths-reverse" =
        "Meta+Shift+R,none,Karousel: Cycle through preset column widths in reverse";
      "kwin"."karousel-focus-1" = [ ];
      "kwin"."karousel-focus-10" = [ ];
      "kwin"."karousel-focus-11" = [ ];
      "kwin"."karousel-focus-12" = [ ];
      "kwin"."karousel-focus-2" = [ ];
      "kwin"."karousel-focus-3" = [ ];
      "kwin"."karousel-focus-4" = [ ];
      "kwin"."karousel-focus-5" = [ ];
      "kwin"."karousel-focus-6" = [ ];
      "kwin"."karousel-focus-7" = [ ];
      "kwin"."karousel-focus-8" = [ ];
      "kwin"."karousel-focus-9" = [ ];
      "kwin"."karousel-focus-down" = [ ];
      "kwin"."karousel-focus-end" = "Meta+End,none,Karousel: Move focus to end";
      "kwin"."karousel-focus-left" = "Meta+A,none,Karousel: Move focus left";
      "kwin"."karousel-focus-next" = [ ];
      "kwin"."karousel-focus-previous" = [ ];
      "kwin"."karousel-focus-right" = [ ];
      "kwin"."karousel-focus-start" = "Meta+Home,none,Karousel: Move focus to start";
      "kwin"."karousel-focus-up" = [ ];
      "kwin"."karousel-grid-scroll-end" = "Meta+Alt+End,none,Karousel: Scroll to end";
      "kwin"."karousel-grid-scroll-focused" = "Meta+Alt+Return,none,Karousel: Center focused window";
      "kwin"."karousel-grid-scroll-left" = "Meta+Alt+PgUp,none,Karousel: Scroll left";
      "kwin"."karousel-grid-scroll-left-column" =
        "Meta+Alt+A,none,Karousel: Scroll one column to the left";
      "kwin"."karousel-grid-scroll-right" = "Meta+Alt+PgDown,none,Karousel: Scroll right";
      "kwin"."karousel-grid-scroll-right-column" =
        "Meta+Alt+D,none,Karousel: Scroll one column to the right";
      "kwin"."karousel-grid-scroll-start" = "Meta+Alt+Home,none,Karousel: Scroll to start";
      "kwin"."karousel-screen-switch" =
        "Meta+Ctrl+Return,none,Karousel: Move Karousel grid to the current screen";
      "kwin"."karousel-tail-move-to-desktop-1" = [ ];
      "kwin"."karousel-tail-move-to-desktop-10" =
        "Meta+Ctrl+Alt+Shift+F10,none,Karousel: Move this and all following columns to desktop 10";
      "kwin"."karousel-tail-move-to-desktop-11" =
        "Meta+Ctrl+Alt+Shift+F11,none,Karousel: Move this and all following columns to desktop 11";
      "kwin"."karousel-tail-move-to-desktop-12" =
        "Meta+Ctrl+Alt+Shift+F12,none,Karousel: Move this and all following columns to desktop 12";
      "kwin"."karousel-tail-move-to-desktop-2" = [ ];
      "kwin"."karousel-tail-move-to-desktop-3" = [ ];
      "kwin"."karousel-tail-move-to-desktop-4" = [ ];
      "kwin"."karousel-tail-move-to-desktop-5" = [ ];
      "kwin"."karousel-tail-move-to-desktop-6" = [ ];
      "kwin"."karousel-tail-move-to-desktop-7" = [ ];
      "kwin"."karousel-tail-move-to-desktop-8" = [ ];
      "kwin"."karousel-tail-move-to-desktop-9" = [ ];
      "kwin"."karousel-window-move-down" = [ ];
      "kwin"."karousel-window-move-end" = "Meta+Shift+End,none,Karousel: Move window to end";
      "kwin"."karousel-window-move-left" = "Meta+Shift+A,none,Karousel: Move window left";
      "kwin"."karousel-window-move-next" = [ ];
      "kwin"."karousel-window-move-previous" = [ ];
      "kwin"."karousel-window-move-right" = "Meta+Shift+D,none,Karousel: Move window right";
      "kwin"."karousel-window-move-start" = "Meta+Shift+Home,none,Karousel: Move window to start";
      "kwin"."karousel-window-move-to-column-1" = "Meta+Shift+1,none,Karousel: Move window to column 1";
      "kwin"."karousel-window-move-to-column-10" = [ ];
      "kwin"."karousel-window-move-to-column-11" = [ ];
      "kwin"."karousel-window-move-to-column-12" = [ ];
      "kwin"."karousel-window-move-to-column-2" = "Meta+Shift+2,none,Karousel: Move window to column 2";
      "kwin"."karousel-window-move-to-column-3" = "Meta+Shift+3,none,Karousel: Move window to column 3";
      "kwin"."karousel-window-move-to-column-4" = "Meta+Shift+4,none,Karousel: Move window to column 4";
      "kwin"."karousel-window-move-to-column-5" = "Meta+Shift+5,none,Karousel: Move window to column 5";
      "kwin"."karousel-window-move-to-column-6" = "Meta+Shift+6,none,Karousel: Move window to column 6";
      "kwin"."karousel-window-move-to-column-7" = "Meta+Shift+7,none,Karousel: Move window to column 7";
      "kwin"."karousel-window-move-to-column-8" = "Meta+Shift+8,none,Karousel: Move window to column 8";
      "kwin"."karousel-window-move-to-column-9" = "Meta+Shift+9,none,Karousel: Move window to column 9";
      "kwin"."karousel-window-move-up" = "Meta+Shift+W,none,Karousel: Move window up";
      "kwin"."karousel-window-toggle-floating" = [ ];
      "kwin"."view_actual_size" = "Meta+0";
      "kwin"."view_zoom_in" = [
        "Meta++"
        "Meta+=,Meta++"
        "Meta+=,Ampliar"
      ];
      "kwin"."view_zoom_out" = "Meta+-";
      "mediacontrol"."mediavolumedown" = "none,,Bajar el volumen multimedia";
      "mediacontrol"."mediavolumeup" = "none,,Subir el volumen multimedia";
      "mediacontrol"."nextmedia" = "Media Next";
      "mediacontrol"."pausemedia" = "Media Pause";
      "mediacontrol"."playmedia" = "none,,Iniciar la reproducción multimedia";
      "mediacontrol"."playpausemedia" = "Media Play";
      "mediacontrol"."previousmedia" = "Media Previous";
      "mediacontrol"."stopmedia" = "Media Stop";
      "org_kde_powerdevil"."Decrease Keyboard Brightness" = "Keyboard Brightness Down";
      "org_kde_powerdevil"."Decrease Screen Brightness" = "Monitor Brightness Down";
      "org_kde_powerdevil"."Decrease Screen Brightness Small" = "Shift+Monitor Brightness Down";
      "org_kde_powerdevil"."Hibernate" = "Hibernate";
      "org_kde_powerdevil"."Increase Keyboard Brightness" = "Keyboard Brightness Up";
      "org_kde_powerdevil"."Increase Screen Brightness" = "Monitor Brightness Up";
      "org_kde_powerdevil"."Increase Screen Brightness Small" = "Shift+Monitor Brightness Up";
      "org_kde_powerdevil"."PowerDown" = "Power Down";
      "org_kde_powerdevil"."PowerOff" = "Power Off";
      "org_kde_powerdevil"."Sleep" = [
        "Meta+S"
        "Sleep,Sleep,Suspender"
      ];
      "org_kde_powerdevil"."Toggle Keyboard Backlight" = "Keyboard Light On/Off";
      "org_kde_powerdevil"."Turn Off Screen" = [ ];
      "org_kde_powerdevil"."powerProfile" = [
        "Battery"
        "Meta+B,Battery"
        "Meta+B,Cambiar perfil de energía"
      ];
      "plasmashell"."activate application launcher" = [
        "none,Meta"
        "Alt+F1,Activar el lanzador de aplicaciones"
      ];
      "plasmashell"."activate task manager entry 1" = "Meta+1";
      "plasmashell"."activate task manager entry 10" = "none,,Activar la entrada 10 del gestor de tareas";
      "plasmashell"."activate task manager entry 2" = "Meta+2";
      "plasmashell"."activate task manager entry 3" = "Meta+3";
      "plasmashell"."activate task manager entry 4" = "Meta+4";
      "plasmashell"."activate task manager entry 5" = "Meta+5";
      "plasmashell"."activate task manager entry 6" = "Meta+6";
      "plasmashell"."activate task manager entry 7" = "Meta+7";
      "plasmashell"."activate task manager entry 8" = "Meta+8";
      "plasmashell"."activate task manager entry 9" = "Meta+9";
      "plasmashell"."clear-history" = "none,,Borrar historial del portapapeles";
      "plasmashell"."clipboard_action" = "Meta+Ctrl+X";
      "plasmashell"."cycle-panels" = "Meta+Alt+P";
      "plasmashell"."cycleNextAction" = "none,,Siguiente elemento del historial";
      "plasmashell"."cyclePrevAction" = "none,,Anterior elemento del historial";
      "plasmashell"."manage activities" = "none,Meta+Q,Mostrar el selector de actividad";
      "plasmashell"."next activity" = [ ];
      "plasmashell"."previous activity" = [ ];
      "plasmashell"."repeat_action" =
        "Meta+Ctrl+R,,Invocar manualmente la acción en el portapapeles actual";
      "plasmashell"."show dashboard" = "Ctrl+F12";
      "plasmashell"."show-barcode" = "none,,Mostrar código de barras...";
      "plasmashell"."show-on-mouse-pos" = "Meta+V";
      "plasmashell"."stop current activity" = "none,Meta+S,Detener la actividad actual";
      "plasmashell"."switch to next activity" = "none,,Cambiar a la actividad siguiente";
      "plasmashell"."switch to previous activity" = "none,,Cambiar a la actividad anterior";
      "plasmashell"."toggle do not disturb" = "none,,Conmutar no molestar";
      "services/Vial.desktop"."_launch" = "Meta+Ctrl+Alt+Shift+F9";
      "services/btop.desktop"."_launch" = "Meta+Esc";
      "services/com.github.th_ch.youtube_music.desktop"."_launch" = "Meta+Ctrl+Alt+Shift+F4";
      "services/discord.desktop"."_launch" = "Meta+Ctrl+Alt+Shift+F6";
      "services/feishin.desktop"."_launch" = "Meta+Ctrl+Alt+Shift+F1";
      "services/firefox.desktop"."_launch" = "Meta+Ctrl+Alt+Shift+F5";
      "services/nvtop.desktop"."_launch" = "Meta+Shift+Esc";
      "services/obsidian.desktop"."_launch" = "Meta+Ctrl+Alt+Shift+F8";
      "services/org.kde.plasma-systemmonitor.desktop"."_launch" = [ ];
      "services/org.kde.spectacle.desktop"."ActiveWindowScreenShot" = [ ];
      "services/org.kde.spectacle.desktop"."FullScreenScreenShot" = [ ];
      "services/org.kde.spectacle.desktop"."RecordRegion" = [ ];
      "services/org.kde.spectacle.desktop"."RecordScreen" = [ ];
      "services/org.kde.spectacle.desktop"."RecordWindow" = [ ];
      "services/org.kde.spectacle.desktop"."RectangularRegionScreenShot" = "Shift+Print";
      "services/org.kde.spectacle.desktop"."WindowUnderCursorScreenShot" = [ ];
      "services/sh.cider.genten.desktop"."_launch" = "Meta+Ctrl+Alt+Shift+F2";
      "services/spotify.desktop"."_launch" = "Meta+Ctrl+Alt+Shift+F3";
      "services/steam.desktop"."Library" = "Meta+Ctrl+Alt+Shift+F7";
    };
    configFile = {
      "baloofilerc"."General"."dbVersion" = 2;
      "baloofilerc"."General"."exclude filters" =
        "*~,*.part,*.o,*.la,*.lo,*.loT,*.moc,moc_*.cpp,qrc_*.cpp,ui_*.h,cmake_install.cmake,CMakeCache.txt,CTestTestfile.cmake,libtool,config.status,confdefs.h,autom4te,conftest,confstat,Makefile.am,*.gcode,.ninja_deps,.ninja_log,build.ninja,*.csproj,*.m4,*.rej,*.gmo,*.pc,*.omf,*.aux,*.tmp,*.po,*.vm*,*.nvram,*.rcore,*.swp,*.swap,lzo,litmain.sh,*.orig,.histfile.*,.xsession-errors*,*.map,*.so,*.a,*.db,*.qrc,*.ini,*.init,*.img,*.vdi,*.vbox*,vbox.log,*.qcow2,*.vmdk,*.vhd,*.vhdx,*.sql,*.sql.gz,*.ytdl,*.tfstate*,*.class,*.pyc,*.pyo,*.elc,*.qmlc,*.jsc,*.fastq,*.fq,*.gb,*.fasta,*.fna,*.gbff,*.faa,po,CVS,.svn,.git,_darcs,.bzr,.hg,CMakeFiles,CMakeTmp,CMakeTmpQmake,.moc,.obj,.pch,.uic,.npm,.yarn,.yarn-cache,__pycache__,node_modules,node_packages,nbproject,.terraform,.venv,venv,core-dumps,lost+found";
      "baloofilerc"."General"."exclude filters version" = 9;
      "dolphinrc"."DetailsMode"."PreviewSize" = 16;
      "dolphinrc"."DetailsMode"."RightPadding" = 0;
      "dolphinrc"."ExtractDialog"."3 screens: Height" = 480;
      "dolphinrc"."ExtractDialog"."3 screens: Width" = 858;
      "dolphinrc"."ExtractDialog"."3840x2160 screen: Height" = 1080;
      "dolphinrc"."ExtractDialog"."3840x2160 screen: Width" = 2264;
      "dolphinrc"."ExtractDialog"."DirHistory[$e]" =
        "$HOME/Applications/,/run/media/lilijoy/Ventoy/Images/,$HOME/.local/share/kwin/scripts/,/run/media/lilijoy/Ventoy/ISOs/";
      "dolphinrc"."General"."ViewPropsTimestamp" = "2024,12,2,15,11,18.292";
      "dolphinrc"."KFileDialog Settings"."Places Icons Auto-resize" = false;
      "dolphinrc"."KFileDialog Settings"."Places Icons Static Size" = 22;
      "dolphinrc"."Notification Messages"."warnAboutRisksBeforeActingAsAdmin" = false;
      "dolphinrc"."PreviewSettings"."Plugins" =
        "audiothumbnail,ebookthumbnail,appimagethumbnail,djvuthumbnail,opendocumentthumbnail,svgthumbnail,exrthumbnail,kraorathumbnail,directorythumbnail,comicbookthumbnail,windowsexethumbnail,jpegthumbnail,imagethumbnail,windowsimagethumbnail,cursorthumbnail,fontthumbnail,gsthumbnail,rawthumbnail,mltpreview,blenderthumbnail,mobithumbnail,ffmpegthumbs";
      "dolphinrc"."Search"."Location" = "Everywhere";
      "kactivitymanagerdrc"."activities"."6bb29d64-4a53-48df-9e22-ad1363fdf2d6" = "Default";
      "kactivitymanagerdrc"."main"."currentActivity" = "6bb29d64-4a53-48df-9e22-ad1363fdf2d6";
      "katerc"."General"."Days Meta Infos" = 30;
      "katerc"."General"."Save Meta Infos" = true;
      "katerc"."General"."Session Manager Sort Column" = 0;
      "katerc"."General"."Session Manager Sort Order" = 0;
      "katerc"."General"."Show Full Path in Title" = false;
      "katerc"."General"."Show Menu Bar" = true;
      "katerc"."General"."Show Status Bar" = true;
      "katerc"."General"."Show Tab Bar" = true;
      "katerc"."General"."Show Url Nav Bar" = true;
      "katerc"."KTextEditor Renderer"."Animate Bracket Matching" = false;
      "katerc"."KTextEditor Renderer"."Auto Color Theme Selection" = true;
      "katerc"."KTextEditor Renderer"."Color Theme" = "gruvbox Dark";
      "katerc"."KTextEditor Renderer"."Line Height Multiplier" = 1;
      "katerc"."KTextEditor Renderer"."Show Indentation Lines" = false;
      "katerc"."KTextEditor Renderer"."Show Whole Bracket Expression" = false;
      "katerc"."KTextEditor Renderer"."Text Font" = "Hack,10,-1,7,400,0,0,0,0,0,0,0,0,0,0,1";
      "katerc"."KTextEditor Renderer"."Text Font Features" = "";
      "katerc"."KTextEditor Renderer"."Word Wrap Marker" = false;
      "katerc"."Kate Print Settings/Margins"."bottom" = 0;
      "katerc"."Kate Print Settings/Margins"."left" = 0;
      "katerc"."Kate Print Settings/Margins"."right" = 0;
      "katerc"."Kate Print Settings/Margins"."top" = 0;
      "katerc"."Printing/HeaderFooter"."FooterBackground" = "211,211,211";
      "katerc"."Printing/HeaderFooter"."FooterBackgroundEnabled" = false;
      "katerc"."Printing/HeaderFooter"."FooterEnabled" = true;
      "katerc"."Printing/HeaderFooter"."FooterForeground" = "0,0,0";
      "katerc"."Printing/HeaderFooter"."FooterFormatCenter" = "";
      "katerc"."Printing/HeaderFooter"."FooterFormatLeft" = "";
      "katerc"."Printing/HeaderFooter"."FooterFormatRight" = "%U";
      "katerc"."Printing/HeaderFooter"."HeaderBackground" = "211,211,211";
      "katerc"."Printing/HeaderFooter"."HeaderBackgroundEnabled" = false;
      "katerc"."Printing/HeaderFooter"."HeaderEnabled" = true;
      "katerc"."Printing/HeaderFooter"."HeaderFooterFont" = "Hack,10,-1,7,400,0,0,0,0,0,0,0,0,0,0,1";
      "katerc"."Printing/HeaderFooter"."HeaderForeground" = "0,0,0";
      "katerc"."Printing/HeaderFooter"."HeaderFormatCenter" = "%f";
      "katerc"."Printing/HeaderFooter"."HeaderFormatLeft" = "%y";
      "katerc"."Printing/HeaderFooter"."HeaderFormatRight" = "%p";
      "katerc"."Printing/Layout"."BackgroundColorEnabled" = false;
      "katerc"."Printing/Layout"."BoxColor" = "invalid";
      "katerc"."Printing/Layout"."BoxEnabled" = false;
      "katerc"."Printing/Layout"."BoxMargin" = 6;
      "katerc"."Printing/Layout"."BoxWidth" = 1;
      "katerc"."Printing/Layout"."Font" = "Hack,10,-1,7,400,0,0,0,0,0,0,0,0,0,0,1";
      "katerc"."Printing/Text"."DontPrintFoldedCode" = true;
      "katerc"."Printing/Text"."Legend" = false;
      "katerc"."Printing/Text"."LineNumbers" = false;
      "katerc"."filetree"."editShade" = "97,90,75";
      "katerc"."filetree"."listMode" = false;
      "katerc"."filetree"."middleClickToClose" = false;
      "katerc"."filetree"."shadingEnabled" = true;
      "katerc"."filetree"."showCloseButton" = false;
      "katerc"."filetree"."showFullPathOnRoots" = false;
      "katerc"."filetree"."showToolbar" = true;
      "katerc"."filetree"."sortRole" = 0;
      "katerc"."filetree"."viewShade" = "97,90,75";
      "kcminputrc"."Keyboard"."NumLock" = 0;
      "kcminputrc"."Keyboard"."RepeatDelay" = 175;
      "kcminputrc"."Keyboard"."RepeatRate" = 40;
      "kcminputrc"."Libinput/65067/65467/sadekbaroudi ffkb Mouse"."NaturalScroll" = false;
      "kcminputrc"."Libinput/65067/65467/sadekbaroudi ffkb Mouse"."PointerAcceleration" = "-0.930";
      "kcminputrc"."Libinput/65067/65467/sadekbaroudi ffkb Mouse"."PointerAccelerationProfile" = 1;
      "kcminputrc"."Libinput/9494/303/Cooler Master Technology Inc. MM710 Gaming Mouse"."PointerAccelerationProfile" =
        1;
      "kcminputrc"."Mouse"."X11LibInputXAccelProfileFlat" = true;
      "kded5rc"."Module-browserintegrationreminder"."autoload" = false;
      "kded5rc"."Module-device_automounter"."autoload" = false;
      "kdeglobals"."DirSelect Dialog"."DirSelectDialog Size" = "828,584";
      "kdeglobals"."DirSelect Dialog"."Splitter State" =
        "\x00\x00\x00\xff\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x8c\x00\x00\x02\xa8\x00\xff\xff\xff\xff\x01\x00\x00\x00\x01\x00";
      "kdeglobals"."General"."XftAntialias" = true;
      "kdeglobals"."General"."XftHintStyle" = "hintslight";
      "kdeglobals"."General"."XftSubPixel" = "none";
      "kdeglobals"."General"."font" = "DejaVu Sans,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1";
      "kdeglobals"."General"."menuFont" = "DejaVu Sans,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1";
      "kdeglobals"."General"."smallestReadableFont" = "DejaVu Sans,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1";
      "kdeglobals"."General"."toolBarFont" = "DejaVu Sans,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1";
      "kdeglobals"."KFileDialog Settings"."Allow Expansion" = false;
      "kdeglobals"."KFileDialog Settings"."Automatically select filename extension" = true;
      "kdeglobals"."KFileDialog Settings"."Breadcrumb Navigation" = false;
      "kdeglobals"."KFileDialog Settings"."Decoration position" = 2;
      "kdeglobals"."KFileDialog Settings"."LocationCombo Completionmode" = 5;
      "kdeglobals"."KFileDialog Settings"."PathCombo Completionmode" = 5;
      "kdeglobals"."KFileDialog Settings"."Show Bookmarks" = false;
      "kdeglobals"."KFileDialog Settings"."Show Full Path" = false;
      "kdeglobals"."KFileDialog Settings"."Show Inline Previews" = true;
      "kdeglobals"."KFileDialog Settings"."Show Preview" = false;
      "kdeglobals"."KFileDialog Settings"."Show Speedbar" = true;
      "kdeglobals"."KFileDialog Settings"."Show hidden files" = true;
      "kdeglobals"."KFileDialog Settings"."Sort by" = "Name";
      "kdeglobals"."KFileDialog Settings"."Sort directories first" = true;
      "kdeglobals"."KFileDialog Settings"."Sort hidden files last" = true;
      "kdeglobals"."KFileDialog Settings"."Sort reversed" = true;
      "kdeglobals"."KFileDialog Settings"."Speedbar Width" = 140;
      "kdeglobals"."KFileDialog Settings"."View Style" = "DetailTree";
      "kdeglobals"."KScreen"."ScreenScaleFactors" = "DP-1=1;DP-2=1;DP-3=1;";
      "kdeglobals"."KShortcutsDialog Settings"."Dialog Size" = "600,480";
      "kdeglobals"."PreviewSettings"."EnableRemoteFolderThumbnail" = false;
      "kdeglobals"."PreviewSettings"."MaximumRemoteSize" = 0;
      "kdeglobals"."Shortcuts"."Quit" = "; Ctrl+Q";
      "kdeglobals"."WM"."activeBackground" = "50,48,47";
      "kdeglobals"."WM"."activeBlend" = "250,189,47";
      "kdeglobals"."WM"."activeFont" = "DejaVu Sans,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1";
      "kdeglobals"."WM"."activeForeground" = "213,196,161";
      "kdeglobals"."WM"."inactiveBackground" = "50,48,47";
      "kdeglobals"."WM"."inactiveBlend" = "102,92,84";
      "kdeglobals"."WM"."inactiveForeground" = "213,196,161";
      "kiorc"."Confirmations"."ConfirmDelete" = false;
      "kiorc"."Confirmations"."ConfirmEmptyTrash" = true;
      "kiorc"."Confirmations"."ConfirmTrash" = false;
      "kiorc"."Executable scripts"."behaviourOnLaunch" = "execute";
      "kscreenlockerrc"."Daemon"."Timeout" = 60;
      "ksmserverrc"."General"."confirmLogout" = false;
      "ksmserverrc"."General"."loginMode" = "emptySession";
      "ktrashrc"."\\/home\\/lilijoy\\/.local\\/share\\/Trash"."Days" = 31;
      "ktrashrc"."\\/home\\/lilijoy\\/.local\\/share\\/Trash"."LimitReachedAction" = 0;
      "ktrashrc"."\\/home\\/lilijoy\\/.local\\/share\\/Trash"."Percent" = 10;
      "ktrashrc"."\\/home\\/lilijoy\\/.local\\/share\\/Trash"."UseSizeLimit" = true;
      "ktrashrc"."\\/home\\/lilijoy\\/.local\\/share\\/Trash"."UseTimeLimit" = true;
      "kwalletrc"."Wallet"."First Use" = false;
      "kwinrc"."Activities/LastVirtualDesktop"."6bb29d64-4a53-48df-9e22-ad1363fdf2d6" =
        "ed1a686e-9f1b-43f2-b396-2ccc1f9c240c";
      "kwinrc"."Desktops"."Id_1" = "ed1a686e-9f1b-43f2-b396-2ccc1f9c240c";
      "kwinrc"."Desktops"."Id_2" = "5d45f9df-a602-43ca-b6f0-b76797e27aa2";
      "kwinrc"."Desktops"."Id_3" = "d31c4472-3ed8-4c6a-884b-dd74305a4408";
      "kwinrc"."Desktops"."Id_4" = "a6d3c18a-e611-45c2-a522-7810675e4761";
      "kwinrc"."Desktops"."Number" = 4;
      "kwinrc"."Desktops"."Rows" = 1;
      "kwinrc"."Effect-overview"."BorderActivate" = 9;
      "kwinrc"."NightColor"."Active" = true;
      "kwinrc"."NightColor"."LatitudeFixed" = 37.78412;
      "kwinrc"."NightColor"."LongitudeFixed" = "-79.44253";
      "kwinrc"."NightColor"."Mode" = "Location";
      "kwinrc"."NightColor"."NightTemperature" = 3500;
      "kwinrc"."Plugins"."karouselEnabled" = false;
      "kwinrc"."Script-karousel"."gapsOuterBottom" = 8;
      "kwinrc"."Script-karousel"."gapsOuterLeft" = 8;
      "kwinrc"."Script-karousel"."gapsOuterRight" = 8;
      "kwinrc"."Script-karousel"."gapsOuterTop" = 8;
      "kwinrc"."Script-karousel"."noLayering" = true;
      "kwinrc"."Script-karousel"."scrollingCentered" = true;
      "kwinrc"."Script-karousel"."scrollingLazy" = false;
      "kwinrc"."Script-karousel"."tiledKeepBelow" = false;
      "kwinrc"."Script-karousel"."untileOnDrag" = false;
      "kwinrc"."Tiling"."padding" = 4;
      "kwinrc"."Tiling/0be6e33a-29bf-5b81-ba08-46ef7895bea1"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/2e4a745a-2029-5de2-9dd7-96278d814acb"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/39425973-5f67-5bf1-9c79-1a401746e7df"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/6281bd20-8f16-5c6d-8195-5d7357f89b6c"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/8bceacb3-02ac-55f6-89fe-ec5a3585ef22"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/92e842d7-5928-5c43-884a-4912e7cc82ed"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/96ca6dc5-9569-5113-9974-a4837092cc22"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/9c45c7ae-01d7-542d-adf0-6552eb05840a"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/9c6cf28f-bc50-55a2-9e90-30ab5d714ac6"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/a7ac4cb7-5a40-562d-9ecf-1a4b3f19e7a4"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/b9fa6997-28d9-514f-9f55-4fe5ec2acaad"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Tiling/eda1d245-9ba3-5c95-82a9-08614efff0f8"."tiles" =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      "kwinrc"."Windows"."FocusPolicy" = "FocusFollowsMouse";
      "kwinrc"."Xwayland"."Scale" = 1;
      "kxkbrc"."Layout"."DisplayNames" = ",";
      "kxkbrc"."Layout"."LayoutList" = "us,us";
      "kxkbrc"."Layout"."Options" = "compose:ins";
      "kxkbrc"."Layout"."ResetOldOptions" = true;
      "kxkbrc"."Layout"."Use" = true;
      "kxkbrc"."Layout"."VariantList" = "altgr-intl,colemak_dh";
      "plasma-localerc"."Formats"."LANG" = "en_US.UTF-8";
      "plasma-localerc"."Formats"."LC_TIME" = "es_419.UTF-8";
      "plasma-localerc"."Translations"."LANGUAGE" = "es";
      "plasmanotifyrc"."Applications/discord"."Seen" = true;
      "plasmanotifyrc"."Applications/firefox"."Seen" = true;
      "plasmanotifyrc"."Applications/net.mkiol.SpeechNote"."Seen" = true;
      "plasmanotifyrc"."Applications/org.gnome.Boxes"."Seen" = true;
      "plasmanotifyrc"."Applications/org.qbittorrent.qBittorrent"."Seen" = true;
      "plasmanotifyrc"."Applications/thunderbird"."Seen" = true;
      "plasmanotifyrc"."Applications/vesktop"."Seen" = true;
      "plasmaparc"."General"."AudioFeedback" = false;
      "spectaclerc"."Annotations"."annotationToolType" = 6;
      "spectaclerc"."Annotations"."rectangleFillColor" = "0,0,0";
      "spectaclerc"."General"."autoSaveImage" = true;
      "spectaclerc"."General"."launchAction" = "UseLastUsedCapturemode";
      "spectaclerc"."GuiConfig"."captureMode" = 4;
      "spectaclerc"."ImageSave"."imageCompressionQuality" = 100;
      "spectaclerc"."ImageSave"."lastImageSaveLocation" =
        "file:///home/lilijoy/Pictures/Screenshots/Captura de pantalla_20250809_114721.png";
      "spectaclerc"."ImageSave"."translatedScreenshotsFolder" = "Screenshots";
      "spectaclerc"."VideoSave"."translatedScreencastsFolder" = "Screencasts";
    };
    dataFile = {
      "kate/anonymous.katesession"."Document 0"."URL" = "";
      "kate/anonymous.katesession"."Kate Plugins"."cmaketoolsplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."compilerexplorer" = false;
      "kate/anonymous.katesession"."Kate Plugins"."eslintplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."externaltoolsplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."formatplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katebacktracebrowserplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katebuildplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katecloseexceptplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katecolorpickerplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katectagsplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katefilebrowserplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katefiletreeplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."kategdbplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."kategitblameplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katekonsoleplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."kateprojectplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."katereplicodeplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katesearchplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."katesnippetsplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katesqlplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katesymbolviewerplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katexmlcheckplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."katexmltoolsplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."keyboardmacrosplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."ktexteditorpreviewplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."latexcompletionplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."lspclientplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."openlinkplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."rainbowparens" = false;
      "kate/anonymous.katesession"."Kate Plugins"."rbqlplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."tabswitcherplugin" = true;
      "kate/anonymous.katesession"."Kate Plugins"."templateplugin" = false;
      "kate/anonymous.katesession"."Kate Plugins"."textfilterplugin" = true;
      "kate/anonymous.katesession"."MainWindow0"."Active ViewSpace" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-H-Splitter" = "0,1498,0";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-0-Bar-0-TvList" =
        "kate_private_plugin_katefiletreeplugin,kateproject,kateprojectgit,lspclient_symbol_outline";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-0-LastSize" = 200;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-0-SectSizes" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-0-Splitter" = 1987;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-1-Bar-0-TvList" = "";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-1-LastSize" = 200;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-1-SectSizes" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-1-Splitter" = 1987;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-2-Bar-0-TvList" = "";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-2-LastSize" = 200;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-2-SectSizes" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-2-Splitter" = 1498;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-3-Bar-0-TvList" =
        "output,diagnostics,kate_plugin_katesearch,kateprojectinfo,kate_private_plugin_katekonsoleplugin";
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-3-LastSize" = 200;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-3-SectSizes" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-3-Splitter" = 1149;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-Style" = 2;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-Sidebar-Visible" = true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-diagnostics-Position" = 3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-diagnostics-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-diagnostics-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_plugin_katesearch-Position" = 3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_plugin_katesearch-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_plugin_katesearch-Visible" =
        false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Position" =
        0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Visible" =
        false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Position" =
        3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Visible" =
        false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateproject-Position" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateproject-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateproject-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectgit-Position" = 0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectgit-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectgit-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectinfo-Position" = 3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectinfo-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-kateprojectinfo-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-lspclient_symbol_outline-Position" =
        0;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-lspclient_symbol_outline-Show-Button-In-Sidebar" =
        true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-lspclient_symbol_outline-Visible" =
        false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-output-Position" = 3;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-output-Show-Button-In-Sidebar" = true;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-ToolView-output-Visible" = false;
      "kate/anonymous.katesession"."MainWindow0"."Kate-MDI-V-Splitter" = "0,1987,0";
      "kate/anonymous.katesession"."MainWindow0 Settings"."WindowState" = 8;
      "kate/anonymous.katesession"."MainWindow0-Splitter 0"."Children" = "MainWindow0-ViewSpace 0";
      "kate/anonymous.katesession"."MainWindow0-Splitter 0"."Orientation" = 2;
      "kate/anonymous.katesession"."MainWindow0-Splitter 0"."Sizes" = 1987;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."Active View" = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."Count" = 1;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."Documents" = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."View 0" = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0 0"."CursorColumn" = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0 0"."CursorLine" = 5;
      "kate/anonymous.katesession"."Open Documents"."Count" = 1;
      "kate/anonymous.katesession"."Open MainWindows"."Count" = 1;
      "kate/anonymous.katesession"."Plugin:kateprojectplugin:"."projects" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."BinaryFiles" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."CurrentExcludeFilter" = "-1";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."CurrentFilter" = "-1";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."ExcludeFilters" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."ExpandSearchResults" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Filters" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."FollowSymLink" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."HiddenFiles" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."MatchCase" = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Place" = 1;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Recursive" = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Replaces" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."Search" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeAllProjects" =
        true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeCurrentFile" =
        true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeFolder" = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeOpenFiles" =
        true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchAsYouTypeProject" = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchDiskFiles" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SearchDiskFiless" = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."SizeLimit" = 128;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0"."UseRegExp" = false;
    };
  };
}

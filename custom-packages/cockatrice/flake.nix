{
  description = "Cockatrice 3.0.2 — cross-platform virtual tabletop for multiplayer card games";

  # ---------------------------------------------------------------------------
  # Inputs
  # ---------------------------------------------------------------------------
  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # ---------------------------------------------------------------------------
  # Outputs
  # ---------------------------------------------------------------------------
  outputs = { self, nixpkgs, flake-utils }:
    let
      # Platforms Cockatrice builds on
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in

    # Per-system outputs (packages, apps, devShells)
    flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # ------------------------------------------------------------------
        # Package derivation
        # ------------------------------------------------------------------
        cockatrice = pkgs.stdenv.mkDerivation rec {
          pname   = "cockatrice";
          version = "3.0.2";

          # Source: official GitHub release tag
          # Tag format used by the project: YYYY-MM-DD-Release-X.Y.Z
          src = pkgs.fetchFromGitHub {
            owner = "Cockatrice";
            repo  = "Cockatrice";
            rev   = "2026-06-26-Release-${version}";
            hash  = "sha256-sIjL+GW9bL9pT9jFqNQDw4kxBTod7t4iy0kVji630uk=";
          };

          # ----------------------------------------------------------------
          # Build-time tools
          # ----------------------------------------------------------------
          nativeBuildInputs = with pkgs; [
            cmake                 # build system (requires ≥3.16 for Qt6)
            pkg-config            # used by cmake find-modules
            ninja                 # faster parallel build
            protobuf              # provides the `protoc` code-generator
            qt6.qttools           # provides lrelease / lupdate for translations
            qt6.wrapQtAppsHook    # rewrites $out/bin/* to set QT_PLUGIN_PATH etc.
          ];

          # ----------------------------------------------------------------
          # Link-time / runtime libraries
          # ----------------------------------------------------------------
          buildInputs = with pkgs; [
            # Protobuf C++ runtime (headers + .so)
            protobuf

            # Qt6 modules required by the Cockatrice client and Oracle tool
            # (see cmake/FindQtRuntime.cmake: Concurrent, Gui, Multimedia,
            #  Network, PrintSupport, Svg, WebSockets, Widgets, Xml)
            qt6.qtbase            # Core, Gui, Widgets, Network, Xml, PrintSupport, Concurrent
            qt6.qtsvg             # Svg
            qt6.qtmultimedia      # Multimedia
            qt6.qtwebsockets      # WebSockets
            qt6.qtimageformats    # extra image format plugins (BMP/TGA/TIFF/WEBP)

            # Optional: decompression support for Oracle card-database downloads
            zlib
            xz
          ];

          # ----------------------------------------------------------------
          # CMake flags
          # ----------------------------------------------------------------
          cmakeFlags = [
            # Build the GUI client
            "-DWITH_CLIENT=ON"
            # Build Oracle (card-database downloader / updater)
            "-DWITH_ORACLE=ON"
            # Do NOT build Servatrice (the dedicated server) by default;
            # flip to ON if you want the server binary as well.
            "-DWITH_SERVER=OFF"

            # Release optimisations; no debug symbols
            "-DCMAKE_BUILD_TYPE=Release"
            # Disable -Werror in release builds
            "-DWARNING_AS_ERROR=OFF"
            # Do not regenerate .ts translation files during build
            "-DUPDATE_TRANSLATIONS=OFF"
            # Do not build the test suite
            "-DTEST=OFF"
            # Never try to use vcpkg (Linux always uses system libs)
            "-DUSE_VCPKG=OFF"
            # Disable ccache wrapper (Nix sandbox manages caching externally)
            "-DUSE_CCACHE=OFF"
            # Explicitly prefer Qt6 (the version found first wins;
            # nixpkgs only exposes Qt6 via qt6.* so this is always true)
            "-DFORCE_USE_QT5=OFF"
          ];

          # wrapQtAppsHook calls qt6.wrapQtAppsHook which needs the
          # full list of Qt libraries to construct QT_PLUGIN_PATH
          dontWrapQtApps = false;

          # ----------------------------------------------------------------
          # Post-install: ensure the desktop entry and icon land correctly
          # ----------------------------------------------------------------
          postInstall = ''
            # Cockatrice installs a .desktop file and hicolor icon via CPack;
            # verify they are present so the launcher shows in app menus.
            echo "=== Installed files ==="
            find $out -type f | sort | head -60
          '';

          # ----------------------------------------------------------------
          # Metadata
          # ----------------------------------------------------------------
          meta = with pkgs.lib; {
            description  = "Cross-platform virtual tabletop for multiplayer card games";
            longDescription = ''
              Cockatrice is an open-source, multiplatform application for playing
              tabletop card games (e.g. Magic: The Gathering) over a network.
              The server architecture prevents cheating by design.
              The bundled Oracle tool downloads and manages card databases.
              A single-player/offline mode lets you playtest decks locally.
            '';
            homepage     = "https://cockatrice.github.io/";
            downloadPage = "https://github.com/Cockatrice/Cockatrice/releases";
            license      = licenses.gpl2Only;
            platforms    = platforms.linux ++ platforms.darwin;
            mainProgram  = "cockatrice";
            # No official Nixpkgs maintainer yet — add yourself here if you
            # intend to keep this package up to date.
            maintainers  = [ ];
          };
        };

        # ------------------------------------------------------------------
        # Variant: also build Servatrice (the server daemon)
        # ------------------------------------------------------------------
        cockatriceWithServer = cockatrice.overrideAttrs (old: {
          pname = "cockatrice-with-server";
          cmakeFlags = (builtins.filter
            (f: f != "-DWITH_SERVER=OFF")
            old.cmakeFlags
          ) ++ [ "-DWITH_SERVER=ON" ];

          # Servatrice needs the SQL and WebSocket Qt modules
          buildInputs = old.buildInputs ++ (with pkgs; [
            qt6.qtbase   # already present — Sql is part of qtbase
          ]);
        });

      in
      {
        # ------------------------------------------------------------------
        # Packages
        # ------------------------------------------------------------------
        packages = {
          default             = cockatrice;
          cockatrice          = cockatrice;
          cockatriceWithServer = cockatriceWithServer;
        };

        # ------------------------------------------------------------------
        # Runnable apps  (nix run .#cockatrice / nix run .#oracle)
        # ------------------------------------------------------------------
        apps = {
          default = {
            type    = "app";
            program = "${cockatrice}/bin/cockatrice";
          };
          cockatrice = {
            type    = "app";
            program = "${cockatrice}/bin/cockatrice";
          };
          oracle = {
            type    = "app";
            program = "${cockatrice}/bin/oracle";
          };
        };

        # ------------------------------------------------------------------
        # Development shell  (nix develop)
        # ------------------------------------------------------------------
        devShells.default = pkgs.mkShell {
          # Inherit all build inputs from the package
          inputsFrom = [ cockatrice ];
          packages   = with pkgs; [
            ccache        # speeds up incremental rebuilds
            gdb           # debugger
            clang-tools   # clang-format / clangd LSP
            ninja         # faster builds than make
          ];

          shellHook = ''
            echo "Cockatrice ${cockatrice.version} dev shell"
            echo "Build example:"
            echo "  cmake -B build -G Ninja -DWITH_CLIENT=ON -DWITH_ORACLE=ON -DCMAKE_BUILD_TYPE=Debug"
            echo "  cmake --build build -j\$(nproc)"
          '';
        };
      }
    )

    # ------------------------------------------------------------------------
    # System-independent outputs (NixOS module, overlay)
    # ------------------------------------------------------------------------
    // {
      # -----------------------------------------------------------------------
      # NixOS Module
      # Usage in your system flake:
      #
      #   inputs.cockatrice.url = "path:/path/to/this/flake";
      #
      #   nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      #     modules = [
      #       inputs.cockatrice.nixosModules.default
      #       {
      #         programs.cockatrice.enable = true;
      #       }
      #     ];
      #   };
      # -----------------------------------------------------------------------
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.cockatrice;
        in
        {
          options.programs.cockatrice = {
            enable = lib.mkEnableOption
              "Cockatrice virtual tabletop for multiplayer card games";

            package = lib.mkOption {
              type        = lib.types.package;
              description = "The Cockatrice package to install.";
              # Fall back gracefully when the flake's packages aren't in scope
              default     = self.packages.${pkgs.stdenv.hostPlatform.system}.cockatrice;
              defaultText = lib.literalExpression
                "cockatrice flake packages.\${system}.cockatrice";
            };

            withServer = lib.mkOption {
              type        = lib.types.bool;
              default     = false;
              description = ''
                If true, also install Servatrice (the Cockatrice server daemon)
                alongside the client. Installs the server-variant package.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages =
              if cfg.withServer
              then [ self.packages.${pkgs.stdenv.hostPlatform.system}.cockatriceWithServer ]
              else [ cfg.package ];
          };
        };

      # Also expose under the canonical alias
      nixosModules.cockatrice = self.nixosModules.default;

      # -----------------------------------------------------------------------
      # Nixpkgs overlay  (add cockatrice to any nixpkgs instance)
      #
      # Usage:
      #   nixpkgs.overlays = [ inputs.cockatrice.overlays.default ];
      # -----------------------------------------------------------------------
      overlays.default = final: prev: {
        cockatrice           = self.packages.${prev.stdenv.hostPlatform.system}.cockatrice;
        cockatriceWithServer = self.packages.${prev.stdenv.hostPlatform.system}.cockatriceWithServer;
      };
    };
}

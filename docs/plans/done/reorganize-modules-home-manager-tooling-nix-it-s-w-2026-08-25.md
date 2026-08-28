---
slug: reorganize-modules-home-manager-tooling-nix-it-s-w
created: 2026-08-25
status: done
frozen: true
---

# reorganize `modules/home-manager/tooling.nix` — it's wholesale-applied to every server host's root profile via `modules/profiles/server.nix`, but mixes universal CLI tools (fzf, zoxide, git, helix, bat, eza, fish) in with desktop-only GUI apps: `services.kdeconnect` (phone-sync daemon), `programs.obs-studio` (screen recording), `programs.obsidian` (notes app), and `programs.firefox` (a whole browser) — all pulled onto headless servers for no reason. Noticed live via `nix why-depends` while sanity-checking vps's actual built closure during its reinstall (traced kdeconnect-kde/qtspeech/ktextwidgets to exactly this path); confirmed with the user this is a real problem worth fixing, not just a decision point — applies identically to homelab, predates this session's changes. Fix direction: split `tooling.nix` into a CLI-only piece (safe for `server.nix` to keep using) and a desktop-GUI piece (kdeconnect/obs-studio/obsidian/firefox, kept only in `modules/profiles/PC.nix`'s home-manager import list). Not done as part of the vps reinstall itself — real refactor across the fleet, needs its own branch and a rebuild-check on every affected host (server.nix hosts *and* PC.nix hosts) before merging

## Original plan

- [x] **2026-08-25: reorganize `modules/home-manager/tooling.nix` — it's
      wholesale-applied to every server host's root profile via
      `modules/profiles/server.nix`, but mixes universal CLI tools (fzf,
      zoxide, git, helix, bat, eza, fish) in with desktop-only GUI apps:
      `services.kdeconnect` (phone-sync daemon), `programs.obs-studio`
      (screen recording), `programs.obsidian` (notes app), and
      `programs.firefox` (a whole browser) — all pulled onto headless
      servers for no reason. Noticed live via `nix why-depends` while
      sanity-checking vps's actual built closure during its reinstall
      (traced kdeconnect-kde/qtspeech/ktextwidgets to exactly this path);
      confirmed with the user this is a real problem worth fixing, not
      just a decision point — applies identically to homelab, predates
      this session's changes. Fix direction: split `tooling.nix` into a
      CLI-only piece (safe for `server.nix` to keep using) and a
      desktop-GUI piece (kdeconnect/obs-studio/obsidian/firefox, kept
      only in `modules/profiles/PC.nix`'s home-manager import list).
      Not done as part of the vps reinstall itself — real refactor
      across the fleet, needs its own branch and a rebuild-check on
      every affected host (server.nix hosts *and* PC.nix hosts) before
      merging.

      **2026-08-26: landed.** `modules/home-manager/tooling.nix` kept the
      CLI-only pieces (helix, git, fzf, zoxide, btop, fish, bat, eza) and
      dropped the four GUI ones; a new `modules/home-manager/
      tooling-desktop.nix` (registers as `flake.modules.homeManager.
      "tooling-desktop"`) holds `services.kdeconnect`/`programs.
      obs-studio`/`programs.obsidian`/`programs.firefox`, wired only into
      `modules/profiles/PC.nix`'s `home-manager.users.lilijoy.imports`
      list. `modules/profiles/server.nix` needed no change — it already
      only imported `homeManagerModules.tooling`, so server hosts
      automatically stop getting the GUI apps once `tooling.nix` itself
      no longer defines them. `nixos-rebuild build` succeeded on all four
      affected hosts (vps, homelab, thinkpad, torrent); confirmed with
      `nix path-info -r` against vps's and thinkpad's real built
      `system.build.toplevel` that obsidian/obs-studio/firefox/kdeconnect
      are now absent from vps's closure while still present in
      thinkpad's (a PC host) — the actual bug this item was about is
      fixed, not just the wiring. Not yet deployed to any host.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

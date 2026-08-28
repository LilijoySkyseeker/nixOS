---
slug: homelab-s-host-firewall-has-no-real-protection-aga
created: 2026-08-26
status: done
frozen: true
---

# homelab's host firewall has no real protection against its own already-public IPv6 address — currently only saved by the ISP router's own (undocumented, unconfigured-by-this- repo) inbound IPv6 firewall

## Original plan

- [x] **2026-08-26: homelab's host firewall has no real protection
      against its own already-public IPv6 address — currently only
      saved by the ISP router's own (undocumented, unconfigured-by-this-
      repo) inbound IPv6 firewall.** Surfaced while reviewing whether to
      add IPv6 to the vps's game-port forwarding (see the item above).
      Confirmed live: homelab's LAN NIC (`enp3s0`) already has a real,
      globally-routable IPv6 GUA (ISP RA-delegated, e.g.
      `2600:1010:a022:496c::/64`) — unlike its IPv4 address, which stays
      private/CGNAT'd behind the home router and is only reachable
      externally via vps's DNAT'd WireGuard tunnel. Several of
      homelab's services open their ports host-wide rather than
      interface-scoped (unlike `modules/services/nfs.nix` and
      `samba.nix`, which correctly scope to
      `networking.firewall.interfaces.tailscale0.*`):
      - `services.openssh` (`hosts/homelab/configuration.nix`) has no
        `openFirewall = false` — vps's config explicitly sets this
        ("force port 22 closed"), homelab never got the same treatment
        — so NixOS's default `openFirewall = true` leaves port 22 open
        on every interface.
      - `services.jellyfin.openFirewall = true` plus an explicit
        `networking.firewall.allowedTCPPorts`/`allowedUDPPorts = [ 8096 ]`
        (`modules/services/jellyfin.nix`) — meant to be reached only via
        vps's Caddy+Anubis proxy, but exposed raw and unchallenged on
        every interface at the host level.
      - `modules/services/minecraft.nix`/`factorio.nix` also open their
        ports host-wide (relevant if the parked IPv6 game-ports item
        above is ever revived).
      Live-tested from vps (a genuine external vantage point, not a
      self-connect) 2026-08-26: connections to homelab's real IPv6 GUA
      on both port 22 and port 8096 timed out — not reachable in
      practice right now — while a control connection from the same vps
      to a known-good external IPv6 endpoint succeeded immediately,
      ruling out a vps-side IPv6 egress problem. So something upstream
      (almost certainly the ISP-provided router's own default-deny
      inbound IPv6 firewall) is the only thing actually blocking this
      today — not anything this repo declares or controls, and nothing
      that would survive a router replacement/firmware change/ISP
      config change unnoticed. Needs: decide on a fix (e.g. move sshd
      and jellyfin to explicit `networking.firewall.interfaces.*`
      scoping, matching the nfs.nix/samba.nix pattern) — note jellyfin
      is more nuanced than a straight tailscale0-only copy, since
      `openFirewall` likely also covers LAN auto-discovery (DLNA/
      Chromecast-style clients), and IPv6 breaks the usual "LAN
      interface ⇒ private-only" assumption since the LAN NIC now
      carries a public address too — a same-interface allow can't
      distinguish a real LAN neighbor from an internet host arriving on
      that same NIC. Not yet fixed; flagged for a decision, not treated
      as an active fire since nothing is currently reachable.

      **2026-08-26: landed.** `services.openssh.openFirewall = false` +
      `networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ]`
      on homelab (`f93ca49`); jellyfin/minecraft/factorio re-scoped to
      `tailscale0`+`wg0` only, dropping jellyfin's `openFirewall`/LAN
      auto-discovery entirely and its vestigial UDP 8096 rule
      (`deaf882`, `9134a47`). Verified via `nixos-rebuild dry-build` plus
      direct inspection of the generated firewall-start scripts at each
      step, then confirmed surviving a real reboot (not just a live
      firewall reload) 2026-08-26 — fresh SSH over tailscale worked
      immediately post-boot, and the temporary LAN-IPv4-only SSH
      fallback added during the switch-over was removed once that was
      confirmed (`0a774e5`). The broader "audit everything else on
      homelab" pass this specific finding fed into remains open — see
      the active TODO.md security-audit item.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

---
slug: caddy-hits-a-permission-denied-race-against-the-an
created: 2026-08-18
status: done
frozen: true
---

# caddy hits a permission-denied race against the anubis unix socket right after vps reboots

## Original plan

- [x] **2026-08-18: caddy hits a permission-denied race against the
      anubis unix socket right after vps reboots.** Found trawling
      vps's logs: from 03:18–03:47 (right after a 23:47 reboot), every
      request to `jellyfin.skyseekerlabs.net` 502'd with `dial unix
      /run/anubis/anubis-jellyfin/anubis.sock: connect: permission
      denied` (36 requests total), then self-resolved and hasn't
      recurred since. `caddy`'s `id` showed it *is* in the `anubis`
      group (`users.users.caddy.extraGroups = [ "anubis" ]`), so this
      looked like a boot-order race, not a missing-permission bug.
      Re-checked live 2026-08-25 (no reboot since 2026-08-20, so no
      fresh data on the race itself at that point) — socket perms and
      group membership both correct, journal history showed the
      "permission denied" signature confined to the single Aug 18
      window, consistent with a self-resolved boot-order race.

      **Root cause identified and landed 2026-08-26**
      (`hosts/vps/configuration.nix`, branch
      `worktree-caddy-anubis-boot-order`): confirmed against the pinned
      nixpkgs source (`nixos/modules/services/networking/anubis.nix`)
      that the anubis module sets `DynamicUser = true` with `Type =
      simple` and no `systemd.sockets.*` unit — the unix socket is
      created by the anubis process itself, and its `anubis` group is
      a *transient* dynamic group that exists only while
      `anubis-jellyfin.service` is active, not a static system group.
      If caddy's process is spawned before that unit has started, its
      one-time supplementary-group resolution (`extraGroups = [
      "anubis" ]`) simply finds no such group — exactly matching the
      observed "permission denied" signature confined to a narrow
      post-boot window. Fix: added
      `systemd.services.caddy.after`/`wants = [ "anubis-jellyfin.service"
      ]`, which guarantees systemd allocates the dynamic group (part
      of *starting* that unit, before `Type = simple`'s immediate
      "started" transition) before caddy is even dispatched.

      Build-tested (`nixos-rebuild build --flake .#vps`), deployed
      live (`nixos-rebuild switch --flake .#vps --target-host
      root@vps`), and confirmed across a real reboot (the vps droplet
      had also just been recreated the same day — host key change
      verified as legitimate via journal/auth-log inspection and a
      matching already-trusted Tailscale-IP known_hosts entry before
      proceeding). Post-reboot journal shows `anubis-jellyfin.service`
      starting before `caddy.service` as intended, zero "permission
      denied" occurrences, `getent group anubis` includes `caddy`, and
      `jellyfin.skyseekerlabs.net` serves `HTTP 302` normally. A
      separate, unrelated transient 502 was observed for a few seconds
      immediately post-boot (wg0's WireGuard handshake to homelab
      re-establishing after the reboot) — self-healed within ~10s, not
      connected to the anubis socket race this item was about.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

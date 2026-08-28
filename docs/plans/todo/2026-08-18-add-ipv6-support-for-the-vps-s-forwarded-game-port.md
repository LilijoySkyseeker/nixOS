---
slug: add-ipv6-support-for-the-vps-s-forwarded-game-port
created: 2026-08-18
status: todo
frozen: false
---

# add IPv6 support for the vps's forwarded game ports — reviewed 2026-08-26, parked as a long-term/low-priority project, not actively planned

## Original plan

- [ ] **2026-08-18: add IPv6 support for the vps's forwarded game
      ports — reviewed 2026-08-26, parked as a long-term/low-priority
      project, not actively planned.** (Minecraft 25565/19132, Factorio
      34197/34198 — the latter added 2026-08-20 for `new.factorio`, same
      treatment needed). Currently IPv4-only: `net.ipv6.conf.all.forwarding`
      is explicitly off on the vps and there are no `ip6tables` DNAT
      rules for these ports, so `minecraft`/`factorio`'s DNS records
      were made A-only (`modules/services/octodns.nix`) after a live
      bug where the AAAA records
      advertised IPv6 reachability that didn't exist, silently
      breaking any client (confirmed: a Bedrock client) that prefers
      IPv6 when a hostname resolves to both. The apex still has an
      AAAA record since Caddy on the vps itself is native IPv6, no
      forwarding needed — this item is specifically about the DNAT'd
      raw TCP/UDP game ports.
      **Confirmed still unaddressed, 2026-08-25**: `net.ipv6.conf.all.
      forwarding` is still `0` live on vps, no ip6tables DNAT rules for
      these ports exist beyond the stock empty `nixos-nat-pre` chain.

      **2026-08-26 cost/benefit review, parked:** benefit is narrow —
      dual-stack clients (the large majority in 2026) already connect
      fine over the existing A records today; this would only help
      clients with *no* IPv4 path at all (genuinely IPv6-only networks),
      an unconfirmed and likely small slice of this server's actual
      whitelisted/friends-and-family player base. Cost is real and
      non-trivial, so not worth it speculatively:
      - True per-interface IPv6 forwarding doesn't exist on current
        mainline kernels (confirmed against an active 2025 LKML patch
        thread, `force_forwarding`, proposing to add it) — the only
        lever available is the blanket `net.ipv6.conf.all.forwarding`
        sysctl, a broader posture change than "wg0 egress only" as
        originally scoped above (narrowable via firewall FORWARD-chain
        rules, but not avoidable at the sysctl level).
      - Bigger issue found during this review: homelab's LAN interface
        already carries a real, globally-routable IPv6 address today
        (ISP RA-delegated, confirmed live). Making the game containers
        IPv6-reachable needs Docker dual-stack
        (`virtualisation.docker.daemon.settings.ipv6`), and
        `modules/services/minecraft.nix`/`factorio.nix` currently open
        their ports host-wide, not interface-scoped — so without *also*
        re-scoping those to `wg0` only, this would make the game
        containers directly reachable from the raw internet over IPv6,
        bypassing every one of vps's defenses (CrowdSec, fail2ban,
        per-IP rate limiting) entirely. This exact exposure pattern
        (host-wide firewall rule + homelab's already-public IPv6)
        already exists today for sshd/jellyfin, independent of this
        item — see the new item immediately below.
      - Full scope ends up touching wg0 addressing on both hosts, vps's
        NAT/DNAT plus a full parallel set of ip6tables rate-limit rules,
        homelab's Docker daemon (bounces both game containers on
        deploy), CrowdSec's tailnet allowlist, and DNS — roughly
        doubling the surface of an already carefully-tuned setup, in a
        corner (dual-stack Docker + WireGuard + custom ip6tables chains)
        fiddly enough that it's hard to fully validate without a real
        client on a real IPv6 path — this repo's other "confirmed
        deployed, not confirmed with a real client" items suggest that
        gap tends to linger.
      Conclusion: not worth pursuing unless a specific player is
      confirmed IPv6-only. Revisit if that ever comes up; otherwise this
      can sit indefinitely.

      **2026-08-26: long-term direction, separate from the above
      near-term "not worth it" call.** The parked verdict is about
      *this specific, narrow* ask (game-port forwarding only, bolted on
      ad hoc). The actual long-term goal for this repo is full dual-stack
      IPv4+IPv6 support everywhere, with the architecture and docs
      treating IPv6 as a first-class default going forward rather than
      an afterthought retrofitted host-by-host — i.e. new services and
      new hosts should be designed dual-stack from the start (including
      the "does this interface's IPv6 address also happen to be public"
      question this session kept running into), instead of repeating
      the same host-wide-firewall-rule-plus-surprise-public-IPv6
      discovery each time. That's a real architecture/documentation
      project of its own — worth scoping once the homelab
      security-audit item above has run its course and the general
      pattern (interface-scoped firewall rules as the default, not the
      exception; dual-stack assumed rather than special-cased) is
      better understood across the whole fleet, not just vps/homelab.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

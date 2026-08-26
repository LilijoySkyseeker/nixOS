# Live verification log

The Phase 1 audits are deliberately static — agents read the config and
the pinned nixpkgs source, and were instructed not to touch running
machines. This file records the few checks that were run against live
hosts anyway, because a static reading could not settle them and the
answer changed a finding's severity.

Everything here was read-only. No host was modified.

---

## 2026-08-26 — homelab: do docker-published game ports bypass the firewall, and are they exposed on IPv6?

**Why it needed a live check.** P4's F-P4-02 concluded that the four
game ports are published by docker as bare `-p` mappings, which DNAT in
the `nat` table and deliver via `FORWARD`, never traversing `nixos-fw`
in `INPUT` — making the eight interface-scoped rules in `minecraft.nix`
and `factorio.nix` ineffective for those ports. P4 could not determine
statically whether docker also publishes on IPv6. That mattered a great
deal: homelab has no public IPv4 (ISP CGNAT) but does carry real global
IPv6, so IPv4-only exposure is LAN-wide while IPv6 exposure would be
**internet-wide, unfiltered and unrate-limited**. MEDIUM versus
CRITICAL turned on it.

**Commands run** (as root over SSH, with the user's explicit
permission): `ip -6 addr show scope global`, `ss -tlnp`, `ss -ulnp`,
`iptables -t nat -S`, `ip6tables -t nat -S`, `iptables -S nixos-fw`.

**Results.**

IPv4 DNAT rules exist and carry **no interface match**, so they apply on
every IPv4 interface:

```
-A DOCKER -p tcp -m tcp --dport 25565 -j DNAT --to-destination 172.17.0.3:25565
-A DOCKER -p udp -m udp --dport 19132 -j DNAT --to-destination 172.17.0.3:19132
-A DOCKER -p udp -m udp --dport 34197 -j DNAT --to-destination 172.17.0.2:34197
-A DOCKER -p udp -m udp --dport 34198 -j DNAT --to-destination 172.17.0.4:34198
```

IPv6: `ip6tables -t nat -S` matched **nothing** for any of the four
ports. There are no IPv6 DNAT rules. This independently confirms the
comment at `modules/services/octodns.nix:49-51`.

`nixos-fw` contains all ten expected interface-scoped rules
(`tailscale0` and `wg0` only), correctly written. They are simply in the
INPUT path, which DNAT'd traffic never reaches — so for these four
ports they are decorative.

Listeners: all four bound by `dockerd` on `0.0.0.0`, none on `::`.
homelab has 3 global-scope IPv6 addresses.

Separately observed: `jellyfin` binds `0.0.0.0:8096`. This is **not** the
same problem — jellyfin is a native service whose traffic does traverse
`nixos-fw`, so its interface-scoped rules are genuinely effective. The
bind address is not what determines exposure; the packet path is.

**Conclusions.**

1. F-P4-02 is CONFIRMED. The interface-scoped rules for the four game
   ports do not constrain anything.
2. Exposure is **LAN-wide (adversary A4), not internet-wide.** The only
   internet path to these servers remains vps's deliberate wg0
   forwarding, which is the intended design.
3. A live, unrecorded dependency: the only thing keeping four game
   servers off homelab's real public IPv6 is docker's default of not
   enabling IPv6 for containers. `hosts/homelab/configuration.nix:39-41`
   sets `userland-proxy = false` as an unremarked performance tweak and
   nothing anywhere records that the host's internet exposure rests on
   that default holding. This is threat model §7.1 — a security property
   resting on an unstated assumption about the network — and it is the
   same class of mistake that triggered this entire audit.

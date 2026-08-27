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

---

## 2026-08-26 — torrent: is the "CGNAT illusion" also true here?

**Why it needed a live check.** P1 reported that torrent holds a
globally-routable IPv6 address and that the shared desktop profile
opens 106 ports host-wide. The threat model's exposure table recorded
torrent's public v6 as "unknown / varies". If P1 was right, the exact
condition that triggered this whole audit exists on the daily driver
too. This machine *is* torrent, so the check is a local unprivileged
read.

**Confirmed.**

- `ip -6 addr show scope global` — a `2600:1010:a022:496c::/64`
  RA-delegated GUA (one `mngtmpaddr` plus several privacy-extension
  temporaries), alongside the tailscale `fd7a:115c:a1e0::/128`.
- `ip -6 route show default` — `default via <router> dev enp8s0 proto
  ra`. A real v6 default route, not link-local only.
- IPv6 listeners on non-loopback addresses: `sshd [::]:22`, `rpcbind
  [::]:111`, `LLMNR [::]:5355`, `mDNS [::]:5353`, and **`kdeconnectd`
  on `*:1716`, TCP and UDP**, bound on all addresses including the GUA.
- `getent group input` → `lilijoy` (P1's F-P1-01 keylogger path).
- `getent group docker` → **does not exist**. Threat model §4.3 path 1
  was wrong and has been corrected.
- `getent group libvirtd` → `lilijoy`, arriving transitively via
  `PC.nix:18` → `virtual-machines.nix:11`.

**Could NOT be determined, and matters.** Reading the actual firewall
ruleset requires root, and this audit does not escalate. An initial
attempt appeared to return an empty `nixos-fw` chain; that was a
**silent permission failure**, not an empty ruleset — recorded here
because it is an easy and dangerous misreading, and reporting "the
firewall is empty" on that basis would have been badly wrong.

So the open question stands: **are those 106 host-wide ports, KDE
Connect's 1716 especially, actually reachable on torrent's public IPv6
from off-LAN?** If they are, it is a live internet exposure on the
daily driver of the same class as the homelab finding that began this
audit. P5 owns settling it.

---

## 2026-08-26 — is torrent's host-wide port range actually reachable from the internet?

**Why it needed a live check.** P5 confirmed, without root, that
torrent's *host* firewall accepts KDE Connect's 1714-1764 and mDNS 5353
on all interfaces (`firewall-start`'s store path matches the evaluated
config, and it installs those rules via `ip46tables` with no `-i`),
while `kdeconnectd` is bound `*:1716` and the host holds a routable
IPv6 GUA. Only the ISP CPE stood between that and the open internet,
and its behaviour is not knowable from any config in this repo.

**Method.** Probe torrent's stable GUA from `vps`, which is off-LAN and
on the public internet, with a sanity check against a known-open host
to prove the probe path works.

```
port 1716: closed/filtered
port 22:   closed/filtered
port 5353: closed/filtered
sanity — cloudflare 2606:4700:4700::1111 443: OPEN
```

**Result: not currently reachable.** The ISP CPE is filtering inbound
IPv6. The sanity check rules out the probe itself being broken.

**What this does and does not mean.** It is *not* "this is fine", and
it is not the same as the ports being closed:

- The host firewall is wide open on 102+ ports on a globally-routable
  address. The **only** thing preventing internet exposure is a
  third-party consumer router's default inbound filter — unversioned,
  unmanaged by this repo, invisible to `nixos-rebuild`, and liable to
  change on a firmware update, a settings reset, a router swap, or an
  ISP configuration push. Nothing anywhere records that the daily
  driver's security depends on it.
- This is threat model §7.1 again, in its purest form: a security
  property resting on an unstated assumption about the network. It is
  the same shape as the homelab CGNAT assumption that triggered this
  audit — and that one turned out to have quietly stopped being true.
- **For thinkpad it provides nothing.** A roaming laptop on a
  conference, hotel or coffee-shop network has no such CPE guarantee,
  and many public networks hand out routable IPv6 with no inbound
  filtering at all. The same 102 ports travel with it.

So the correct framing for remediation is that the CPE is a
coincidence, not a control. Interface-scoping these rules — the pattern
`nfs.nix`/`samba.nix`/`jellyfin.nix` already use, and which port 22
already uses on this very host, proving the mechanism works and simply
was not applied here — removes the dependency entirely.


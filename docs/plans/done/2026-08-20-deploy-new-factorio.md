---
slug: deploy-new-factorio
created: 2026-08-20
status: done
frozen: true
---

# deploy `new.factorio`

## Original plan

- [ ] **2026-08-20: deploy `new.factorio`** — merged to master
      (`c7796c9`), not yet deployed. A second Factorio server
      (`modules/services/factorio.nix`'s `factorio-new` container,
      floating `stable` tag, fresh random world) alongside the
      existing `old.factorio` (still pinned to the experimental
      2.1.14 line). Needs: `nixos-rebuild switch` on homelab (brings
      up the container) and vps (opens the 34198/udp DNAT/firewall/
      ratelimit rules), then an `octodns-sync` run (or its hourly
      timer) to push the new `old.factorio`/`new.factorio` A + SRV
      records to Cloudflare. See `hosts/vps/README.md`'s Status
      section. Once deployed, verify: `new.factorio` reachable by
      hostname alone (SRV lookup, untested — first real use of SRV
      records in this repo) and by `:34198`, `docker-factorio-new`'s
      preStart actually rsyncs `old.factorio`'s mods on a real start,
      and `old.factorio` (34197) still works unaffected.

      **2026-08-21: reported unreachable from an actual game client —
      needs investigation.** Everything checked so far looks healthy,
      which makes this confusing:
      - `factorio-new` container on homelab: up 7h, in-game
        (`ServerMultiplayerManager` state `InGame`), authenticated with
        Factorio's auth server, and registered on the public matching
        server (`MatchingServer.cpp: Matching server game '1232520' has
        been created`) at `97.206.73.106:34198` per its own logs.
      - `new.factorio.skyseekerlabs.net` resolves correctly to the vps
        (`137.184.45.18`), and a UDP probe (`nc -u -z -v`) to
        `:34198` got no ICMP unreachable back.
      - Despite both of the above, the user reports the client cannot
        actually connect/join.
      Not yet checked (as of 2026-08-21): whether the vps's DNAT/
      firewall/ratelimit rules for 34198 were actually deployed — the
      container could be up on homelab while the vps-side forwarding was
      never switched; the SRV-record lookup was also unverified; and a
      UDP `nc` probe getting no ICMP-unreachable isn't proof the DNAT
      rule itself forwards traffic all the way through.

      **2026-08-25 live triage: every infra layer now checks out.** On
      vps, `iptables -t nat -L nixos-nat-pre -n -v` shows the DNAT rule
      live and correct (`udp dpt:34198 to:10.100.0.2:34198`), alongside
      the working 25565/19132/34197 rules. DNS resolves correctly both
      ways: `dig SRV _factorio._udp.new.factorio.skyseekerlabs.net` →
      `0 0 34198 new.factorio.skyseekerlabs.net.`, and the A record
      resolves to vps's IPv4. The `factorio-new` container itself is
      still up (21h) alongside `factorio-main`/`minecraft-vanilla-plus`.
      vps's `current-system` was rebuilt today (2026-08-25 13:21, likely
      via the auto-updater rearchitect's deploy), so the 34198 rule's
      packet counters were freshly zeroed and can't confirm whether real
      client traffic has hit it since — that's the one thing this
      triage pass couldn't settle. Given everything on the infra side is
      now confirmed correctly configured and deployed, the original
      "vps-side forwarding was never switched" hypothesis no longer
      holds as an explanation; what's still missing is a genuine
      client-join retest to confirm the original Aug 21 report is
      actually resolved.

      **2026-08-26: still marked as needing an actual fix, not just more
      diagnosis** — flagged explicitly by the user rather than left to
      linger as an open investigation. Note this now also intersects with
      this session's homelab firewall re-scoping (see the security-audit
      item above): `modules/services/factorio.nix`'s 34197/34198 UDP
      rules moved from host-wide to `tailscale0`/`wg0`-interface-scoped
      only, which is exactly the DNAT'd-through-wg0 path `new.factorio`
      traffic already takes — shouldn't regress anything, but the
      pending client-join retest should happen *after* that firewall
      change lands, not before, so a retest failure can't be
      misattributed to the wrong change.

      **2026-08-26: that firewall change has now landed and is
      reboot-verified** (`deaf882`, `9134a47`, `0a774e5` — see
      `docs/DONE.md`), so the client-join retest is unblocked. Still
      needs a real game client to actually attempt joining
      `new.factorio` — not something checkable from infra inspection
      alone.

      **2026-08-27: closed by removing the server, not by fixing it.**
      The user declared `new.factorio` unused, so the whole second
      server was deleted rather than debugged further -- which also
      retires the client-join retest this entry had been waiting on
      since 2026-08-21. Removed: the `factorio-new` container, its
      `/srv/factorio/new` volume and persistence entry, its
      mod-mirroring `preStart`, the 34198/udp firewall rules on
      homelab and the DNAT + hashlimit rules on vps, and the
      `new.factorio` A + SRV records.

      The surviving server's names were simplified at the same time:
      `old.factorio` is gone and the one server is now just
      `factorio.<domain>`, with its SRV record moved to
      `_factorio._udp.factorio`. Its in-game display name lost the
      "(old)" suffix. DNS is declarative, so `octodns-sync` retires
      the stale Cloudflare records on its next run.

      Left behind on purpose: `/srv/factorio/new`'s data still exists
      on homelab and is no longer persisted declaratively -- it holds
      a factorio account token and the game password, tracked as a
      user-action item (F-P4-04) in
      `docs/audits/2026-08-26/user-actions.md`.

## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

---
slug: do-a-full-security-audit-hardening-pass-on-homelab
created: 2026-08-26
status: in-progress
frozen: false
---

# do a full security audit / hardening pass on homelab

## Original plan

- [ ] **2026-08-26: do a full security audit / hardening pass on
      homelab.** Triggered by the IPv6 review above: homelab's LAN NIC
      turned out to already carry a real, globally-routable public IPv6
      address (ISP RA-delegated), which quietly changes the risk model
      for every host-wide (non-interface-scoped) firewall rule on that
      box — a class of gap that was invisible under IPv4-only CGNAT.
      sshd/jellyfin/minecraft/factorio's host-wide exposure is fixed,
      deployed, and reboot-verified (`f93ca49`, `deaf882`, `9134a47`,
      `0a774e5` — see `docs/DONE.md`). This item is for a broader pass
      beyond just those: audit homelab as a whole (not just
      IPv6-triggered findings) — every `networking.firewall.
      allowedTCPPorts`/`allowedUDPPorts`/`openFirewall` use, docker
      container hardening (capabilities, read-only rootfs, network
      exposure — minecraft.nix/factorio.nix already do this carefully,
      worth checking the rest got the same treatment), systemd
      hardening completeness across all of homelab's services (some
      services have detailed hardening comments, e.g. jellyfin/samba/
      nfs — confirm nothing was missed elsewhere), and whether anything
      else assumes "this box has no real public address" the way
      sshd/jellyfin did. Not started. Also fold in, surfaced while
      working the sshd/jellyfin fix:
      - `modules/profiles/PC.nix` sets `remotePlay.openFirewall = true`
        (Steam Remote Play) host-wide for thinkpad/torrent — same
        host-wide-rule pattern as the homelab findings above, though
        lower urgency since these are laptops that roam between
        networks rather than a fixed server always on one known
        network; worth auditing whether that roaming actually makes it
        *worse* (an unknown network's own IPv6/NAT posture is far less
        predictable than a home ISP's).
      - homelab currently has no intrusion detection at all (no
        CrowdSec/fail2ban, unlike vps) — fine today since access is
        gated entirely by tailscale's own device authorization (ACLs/
        key approval) rather than exposed ports, but worth an explicit
        decision on whether that trust boundary is sufficient long-term
        or whether basic protections belong at the homelab layer too.
      - `bootctl` warns on every boot that `/boot`'s mount point and its
        `loader/random-seed` file are world-accessible ("which is a
        security hole"), surfaced in the 2026-08-26 reboot's journal —
        minor, but a real finding worth folding into this pass rather
        than a one-off fix.

      **Widened 2026-08-26 to cover every host and every shared module
      in this repo**, on two axes: (1) hardening conformance to
      `docs/hardening.md` plus general review, and (2) needed/used —
      is every option/service/package/firewall hole/group/secret still
      justified, since dead config is attack surface with no owner.
      Multi-agent: Phase 0 threat model, Phase 1 eight parallel
      per-part audits (P1-P8), Phase 2 consolidation, Phase 3
      remediation waves, Phase 4 documentation harvest.

      **Status as of 2026-08-27**: Phases 0-2 done — 158 findings (3
      CRITICAL, 31 HIGH, 38 MEDIUM, 53 LOW, 35 INFO), consolidated into
      3 CRITICAL clusters, 10 HIGH clusters, 34 tail entries. Phase 3
      wave 1 complete; wave 2 complete as far as an agent can take it
      (2.1/2.3/2.4/2.5/2.7/2.8 done, 2.6 two-thirds done, 2.2/2.9
      blocked on/resolved by user decisions D9/D13/D14 — 2.9 done
      2026-08-27, smaller than scoped since D9 removed two of three
      port groups rather than narrowing them). Wave 3 is user-only by
      definition, not started. **Phase 4 (documentation harvest) is
      done**: `docs/hardening.md` gained a Standing rules section (ten
      rules from findings.md §4), `docs/threat-model.md` and
      `docs/accepted-risks.md` are new, `AGENTS.md` gained rows for
      both, `docs/procedures/remote-access.md` was corrected (the
      vps-deploy forced-command allowlist is not the real security
      boundary — root arrives via the polkit grant beside it).

      Work happened on `worktree-worktree-security-audit-plan`,
      build-verified on homelab/vps/torrent/thinkpad, **never
      switched**. Four changes are VM-tested, not just built: the
      zfs-emergency-prune sandbox, the vps ipset fail-open fix, both
      halves of item 2.8, and item 2.1's DOCKER-USER guard.
      `tests/zrepl-replication.nix`/`tests/zfs-space-guard.nix` grew
      permanent subtests; `tests/docker-publish-guard.nix` is new
      (nine subtests, drives real packets at a real container).

      Deferred out of wave 1, resolved since: UDP 10400/10401
      attributed to Steam Remote Play (closed when D9 dropped that
      option) — lesson: attribute a port to the option that opens it,
      not the port number, since the numbers themselves never appear
      as literals in this repo. The skipped-deploy half of `F-P7-09`
      closed 2026-08-27 (build/VM-verified, not deployed): all four
      hosts now watch `/nix/var/nix/profiles/system` staleness via
      `staleMarkerFiles`, catching a silently-skipped deploy the same
      way as a failed one.

      Container resource ceilings (`F-P4-07`): done 2026-08-27 for
      `--memory`/`--pids-limit` (build-verified, not deployed). D15
      answered "no container may exceed 50% of the host's memory" →
      `--memory=7g` on both factorio-main and minecraft-vanilla-plus
      (host has 15.54 GiB), `--pids-limit=512`/`1024` respectively —
      both far above measured peaks (19 and 123 pids; 1.06 GB and 4.90
      GB memory.peak on a 37-minute idle sample, treated as a floor not
      a peak). The 50% figure is an estimate the user gave explicitly,
      not a measurement; both containers sharing the same cap means a
      simultaneous worst case still exhausts the host, accepted since
      it still stops any single runaway. `--cpus` remains unset and
      undecided. `userns-remap` is still not set (F-P4-07) — needs its
      own VM test and a plan for existing bind-mount ownership before
      enabling.

      `push-deploy-vps` is the one piece of item 2.6 not done, deferred
      on purpose: `nixos-rebuild --target-host` shells out to
      ssh/nix-copy-closure, and `PrivateTmp`/`ProtectSystem=strict` can
      break the SSH control-master path and nix's fetcher cache — needs
      a VM test with a real remote target since a wrong guess means vps
      silently stops updating.

      Everything requiring the user (credential rotations, decisions
      D1-D14) is tracked at `docs/audits/2026-08-26/user-actions.md`.
      Read `docs/audits/2026-08-26/RESUME.md` first for pickup — it's
      written to be read cold.


## Progress


## Decisions (D)

### D1 -- is tailnet device authorization alone sufficient for homelab, or does it need its own intrusion detection (CrowdSec/fail2ban) like vps has?
Standing question carried over from the original trigger, still open as of 2026-08-27 -- Phase 0/P3 confirmed access is gated entirely by tailscale device auth today, but whether that's sufficient long-term is explicitly a user decision, not an audit finding.

## Gotchas (G)

### G1 -- three Phase-4 judgement calls were decided by the agent, not the user, because they're documentation-only and cheap to reverse
(1) How much reasoning goes inline in docs/hardening.md: rules stay short/imperative, file:line evidence stays in the audit and is linked, rather than doubling the doc on justification. (2) Where the threat model lives: docs/audits/2026-08-26/ is canonical (the eight part reports cite it by section and a copy would drift), docs/threat-model.md is a stable pointer with a supersession rule. (3) docs/accepted-risks.md could only be scaffolded: SS1 holds six risks genuinely not in question, SS2 lists D1-D14 as explicitly not-yet-accepted pending those decisions.


## Findings (F)
*(populated by security/docs-updater when invoked)*

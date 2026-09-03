---
slug: design-and-implement-intrusion-detection-for-homelab
created: 2026-09-03
status: todo
frozen: false
---

# Design and implement intrusion detection for homelab

## Original plan

- [ ] **2026-09-03: give homelab real intrusion detection, full
      implementation, per the user's explicit decision on D7
      (`2026-08-26/user-actions.md`).** Origin finding: **H8**
      (`docs/audits/2026-08-26/findings.md`) — homelab is reachable from
      the open internet on multiple paths (`wg0` opens
      8096/25565/19132/34197/34198, vps DNATs the game ports straight
      through, docker adds LAN-wide reach on top) with **no device
      authorization anywhere in that path** and **nothing on the host
      would notice**: no CrowdSec, no fail2ban, `logRefusedConnections`
      is false where vps sets it true.

      **The audit's own P3 judgement, recorded in H8 and worth reading
      before designing anything:** "conventional log-based IDS is a poor
      fit here" — sshd is tailnet-only (so its logs are low-value for
      catching the actual internet-facing paths), and the game servers'
      own logs are in formats CrowdSec has no parsers for. P3's
      recommendation at audit time was to spend the effort on
      `DOCKER-USER` lockdown, ACL narrowing, and keeping the game images
      current instead — but explicitly left the decision to the user
      rather than closing it as accepted. The user has now decided (D7,
      2026-09-03) that full IDS implementation is wanted anyway; this
      plan carries that decision forward as real design-and-build work,
      not just an accept/reject call.

      **Related work already done, worth knowing before scoping this:**
      the `DOCKER-USER` half of P3's alternative recommendation is
      already fixed — `myDockerPublishGuard` (wave 2 item 2.1, D13)
      filters the four game ports to `wg0`/`tailscale0` only, closing the
      LAN-reachability part of H8's blast radius. ACL narrowing (D6) is
      still open as its own decision. Neither substitutes for real
      detection on the paths that remain legitimately open (the tailnet
      and the public game-port path through vps) — this plan is
      additive to those, not redundant with them.

      **First design question to settle, not yet answered:** what
      mechanism fits given P3's log-format caveat? Candidates worth
      evaluating rather than assuming: a lightweight anomaly/connection
      monitor at the network layer (independent of log parsing) such as
      port-scan/connection-rate detection on `wg0`; game-server-specific
      log parsing (writing real CrowdSec parsers for the actual log
      formats in use, if CrowdSec is still the preferred tool);
      file-integrity monitoring (`aide`-class) as a complementary,
      log-format-independent signal; or systemd-level auth/journal
      anomaly detection scoped to the paths that actually matter here
      (not a blanket sshd-log tool, since sshd is tailnet-only and
      low-risk by comparison). Whatever is chosen needs `myHealthAlerts`
      wiring so a real detection actually reaches the user — the audit
      elsewhere found detectors that ran but alerted nowhere (C3's
      `F-P6-07`), which is the specific failure mode to design out here.

## State

Not started. Scoped from H8/D7 2026-09-03; no design work done yet beyond
recording the constraint (log-based IDS is a poor fit) and the candidates
worth evaluating. Next step is picking a mechanism, not writing code.


## Progress


## Decisions (D)


## Gotchas (G)


## Findings (F)
*(populated by security/docs-updater when invoked)*

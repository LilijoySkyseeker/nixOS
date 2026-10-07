# Threat model

The fleet's standing threat model — who we are defending against, what
crossing each trust boundary actually buys them, and the severity rubric
every finding is rated against.

**The current model is
[`audits/2026-08-26/00-threat-model.md`](audits/2026-08-26/00-threat-model.md).**

It lives inside the dated audit directory it was written for, and stays
there rather than being copied out: the eight part reports and every
finding cite it by section, and a second copy would drift from the one
they cite. This file is the stable path — link *here* from prose and
from `AGENTS.md`, so a future audit can supersede the model by editing
one line below instead of chasing every reference.

## What is in it

| Section | What you go there for |
|---|---|
| §1 | What we are protecting, ranked. Asset #1 is the data on `zdata`. |
| §2 | Exposure map — including §2.1, why "we are behind CGNAT" stopped being true, and §2.2 on interface scoping as *the* control. |
| §3 | Principals: who and what can act. |
| §4 | The six trust boundaries and what crossing each one buys. §4.7 is the one that surprises people: the configuration itself is public. |
| §5 | The nine adversaries (A1–A9). Findings cite these in their "reachability" line. |
| §6 | **The severity rubric.** Read this before rating anything, so ratings stay comparable across sessions. |
| §7 | Six recurring failure modes to probe for. Several of `hardening.md`'s standing rules exist because of these. |
| §8 | Open questions the model could not answer itself. |
| §9 | Non-goals — what this model deliberately does not defend against. |

## Added since the current model

The model predates these. Rate findings against them by analogy until a
later audit folds them in.

| Since | Principal | Reaches | Bounded by |
|---|---|---|---|
| 2026-10-06 | **`agent`** (torrent): an AI agent running with no permission prompts, so treat it as prompt-injectable | the internet; `~agent`; `Vault/Research` via bindfs; the nix daemon (`allowed-users`) | the Unix user itself, the `agent-egress` chain (no LAN or tailnet, IPv6 loopback only), the `claude-remote-control` unit's sandbox, and sshd `DenyUsers`. See `hardening.md`, "The `agent` user"; design record in `~/Projects/agenticsandbox/` |

## Removed since the current model

Since 2026-10-06 `vps` serves no public HTTP(S) (no Caddy, Anubis or
public Jellyfin; Jellyfin is tailnet-only) and runs no CrowdSec. Its
public surface is the DNAT'd game ports and WireGuard, so §2's exposure
map overstates it.

## Using it

- **Before exposing anything new**, check §2 and §4: decide which
  boundary the change sits on and whether it moves one.
- **Before rating a finding**, read §6. A severity that does not come
  from the rubric is not comparable to the 158 that do.
- **Before accepting a risk**, write it into
  [`accepted-risks.md`](accepted-risks.md) with the boundary it sits on
  — not in a commit message, and not only in an audit report.

## Superseding it

A later audit writes its own `00-threat-model.md` in its own dated
directory. When one does, change the link above to point at the new one
and list the old one here as superseded. Do not delete the old copy: the
findings that cite it are still the record of what was true then.

| Model | Status |
|---|---|
| [`audits/2026-08-26/00-threat-model.md`](audits/2026-08-26/00-threat-model.md) | **current** |

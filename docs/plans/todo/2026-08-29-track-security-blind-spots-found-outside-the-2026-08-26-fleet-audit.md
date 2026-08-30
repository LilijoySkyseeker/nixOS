---
slug: track-security-blind-spots-found-outside-the-2026-08-26-fleet-audit
created: 2026-08-29
status: todo
frozen: false
---

# Track security blind spots found outside the 2026-08-26 fleet audit

## Original plan

User asked for help finding "what I don't know I don't know" about Linux/
NixOS security for this fleet. Since the 2026-08-26 audit
(`docs/audits/2026-08-26/`) already covers 158 configuration-level findings
with a formal threat model, hardening rules, and an accepted-risks register,
the useful pass was to look *outside* that audit's own aperture — categories
none of P0–P8 touch at all, filtered against what's actually relevant to a
single-admin personal homelab (per `docs/threat-model.md` §9's own
non-goals), not APT-grade theater.

A research pass (grep across all 8 audit parts + `docs/hardening.md` for
~25 topic keywords, then targeted web research on whatever came back
absent) produced 9 items, none of which are re-statements of the audit's
own open decisions (D1–D14) or accepted risks (AR-1..7). Two cited CVEs
(CrowdSec, Caddy) were independently verified against real advisories and
against this fleet's actual pinned versions before being written up here.
Full write-up: `~/security-blindspots-2026-08-29.md` (also published as an
Artifact in that session — not repo-tracked, kept here as the durable copy).

This plan exists to make sure each of the 9 items gets an actual
fixed/accepted/moot resolution instead of sitting in a one-off report that
nobody revisits.

## State

**2026-08-29, just created.** All 9 findings are open — none evaluated or
resolved yet. Next step is the user triaging each one (fix it, accept it as
a documented risk in `docs/accepted-risks.md`, or dismiss as moot).

## Progress
- [ ] F1
- [ ] F2
- [ ] F3
- [ ] F4
- [ ] F5
- [ ] F6
- [ ] F7
- [ ] F8
- [ ] F9

## Decisions (D)
None yet — each finding below resolves independently via `plan-resolve`;
no fleet-wide decision is blocking triage.

## Gotchas (G)
### G1 -- don't cite a CVE against a component without checking the fleet's actual pinned version
The first draft of F1 below named CrowdSec/Caddy CVEs as live exposure on
vps. Checking `nix eval .#nixosConfigurations.vps.config.services.{crowdsec,caddy}.package.version`
showed both were already on patched versions (1.7.8, 2.11.4) — nixpkgs-
unstable's update cadence had already carried the fix. The real gap was
the *absence of a monitoring process* that would have caught it either
way, not the two specific CVEs. Always check the pin before writing up a
version-specific vulnerability as current exposure.

## Findings (F)

### F1 -- No process monitors installed packages for newly disclosed CVEs
Every audit finding in P0–P8 is about configuration, not "is the software
itself currently vulnerable." Nothing in this fleet answers that question
proactively today — the vps CrowdSec/Caddy check above happened to be fine,
but only because of update timing, not because anything would have told us
if it weren't. **Mechanism:** [`vulnix`](https://github.com/nix-community/vulnix)
against `system.build.toplevel` for homelab/vps, run periodically (a cron/
systemd timer, or folded into `health-alerts.nix`'s existing Discord
alerting). **Priority: HIGH.**

### F2 -- Kernel sysctl hardening is entirely unused despite internet-facing services
`kernel.kptr_restrict`, `kernel.dmesg_restrict`, `kernel.unprivileged_bpf_disabled`,
`kernel.yama.ptrace_scope` etc. never appear anywhere in the config, even
on homelab/vps which run services under `NoNewPrivileges` already —
decent unit-level sandboxing that still leaves the kernel itself readable/
probeable from a compromised service. **Mechanism:** `boot.kernel.sysctl`,
the same option family already used for the Tailscale forwarding overrides.
NixOS's own `nixos/modules/profiles/hardened.nix` bundles most of this plus
`security.protectKernelImage`/`security.lockKernelModules`, but importing it
wholesale has known networking footguns per current NixOS Discourse reports
— cherry-pick sysctls individually instead of importing the whole profile.
**Priority: HIGH.**

### F3 -- Nothing sandboxes desktop apps (browser/Steam/Discord) from the SSH/age keys already found sitting in plain files
Connects directly to existing audit findings F-P8-04 and F-P5-01, which
found the fleet-root SSH private key and the age identity as plain,
readable files in `lilijoy`'s home. Nothing in P4/P5 asked what *runs* as
that user on the daily drivers. A malicious browser extension or a
compromised game client doesn't need root or a kernel exploit — it just
needs to be `lilijoy`. **Mechanism:** `bubblewrap` (what Flatpak's sandbox
is built on) for ad-hoc namespacing, or Flatpak itself for packaged apps.
Firejail considered and rejected as the mechanism — its setuid binary and
looser defaults make it weaker for anything secrets-adjacent. **Priority:
HIGH.**

### F4 -- DNS is plaintext fleet-wide (from F-P3-17, F-P5-16)
The 2026-08-26 audit already found this — all DNS is plaintext,
unvalidated, sent to Google/Cloudflare on every host — but no remediation
was ever chosen, so it sat as a finding with no follow-up. Two NixOS-native
paths: `services.resolved.dnsovertls = "true"` (simplest, needs a
DoT-capable resolver) or `services.dnscrypt-proxy2` (broader protocol
support, more moving parts). **Priority: MEDIUM** — the one item on this
list with a one-line fix already known.

### F5 -- journald/audit trail has no tamper-evidence off the box it watches
`server.nix` enables `security.auditd`/`security.audit` with an execve
rule, correctly persisted through impermanence — but the log only exists
locally. If homelab's root is ever compromised, the audit trail is exactly
what an attacker can edit or truncate first. **Mechanism:**
`systemd-journal-remote`/`journal-upload` to ship entries to a second host
over TLS as they're written. Note: `docs/accepted-risks.md` AR-2 already
treats homelab+vps as one blast radius, so shipping homelab's journal *to*
vps may not actually buy the isolation this is meant to provide — needs a
deliberate target-host decision, not a default "just point it at vps."
**Priority: MEDIUM.**

### F6 -- Container escape beyond capability drops isn't addressed
`docs/hardening.md` rule 10 and finding F-P4-07 already cover capability
drops, seccomp defaults, and the known gap that container UID 0 is host
UID 0 without `userns-remap`. What's unaddressed is the *other* axis: a
kernel exploit doesn't care about capabilities at all. **Mechanism:**
`gVisor` (intercepts syscalls in userspace, so a container never talks to
the real kernel directly) or rootless Docker/Podman (no root-owned daemon
to escape into). **Priority: MEDIUM.**

### F7 -- The binary cache trust model was inherited by default, never decided
Every host implicitly trusts `cache.nixos.org`'s signing key via the
default `nix.settings.trusted-public-keys`. Not independently fixable —
it's Nix's substitution model — but worth having stated explicitly rather
than living nowhere in `hardening.md`'s trust-boundary language. The one
real lever: audit `nix.settings.trusted-users` on each host, since that
list can add *arbitrary* substituters at build time, a strictly bigger
grant than "trusts the default cache." **Priority: MEDIUM.**

### F8 -- AppArmor: known to exist, deliberately not pursued yet
`security.apparmor.enable` is real on NixOS, but as of 2026 few upstream
profiles are adapted for it, and the immutable, hash-addressed
`/nix/store` layout fights path-based MAC profiles by design. The systemd
sandboxing stack already in use (hardening.md rule 11) buys most of the
same containment without this fragility. Recorded here as a deliberate
non-action rather than an oversight — reassess if NixOS's own AppArmor
integration matures. **Priority: LOW / informational.**

### F9 -- USBGuard: the sharper version of this problem is already fixed
F-P8-08 (world-writable `/dev/hidraw*` from via/vial udev rules) and
F-P8-09 (the `input` group = system-wide keylogging) are the acute form of
"an untrusted USB device can do too much here," and both are already
fixed. USBGuard is the blunter, categorical version — block unknown USB
devices by default — and only matters against a physical drop-attack on
the laptops. Not an action item unless the thinkpad's physical exposure
changes (e.g. it starts traveling more). **Priority: LOW / informational.**

# P0 — findings from the threat-model pass

Findings that surfaced while writing
[`00-threat-model.md`](00-threat-model.md), recorded in the standard
schema so Phase 2 consolidates them alongside P1–P8 rather than losing
them in prose.

These are **cross-cutting by nature** — each one spans parts, which is
why the threat-model pass found them and no single part audit would
have. Where a part owns the follow-up work, it says so; those parts
should confirm or refute rather than re-derive from scratch.

> **P1–P8: this file is also your format reference.** Use this exact
> finding schema. One `###` block per finding, id `F-<part>-NN`.

---

## Schema

```
### F-<part>-NN — <short title>
- **File:** `path:line` (or several)
- **Severity:** CRITICAL | HIGH | MEDIUM | LOW | INFO
- **Confidence:** CONFIRMED | PLAUSIBLE
- **Axis:** hardening | needed-used | documentation
- **Reachability:** <adversary id from threat model §5> — <the path>
- **Rule:** violates `docs/hardening.md` "<which>" | new-rule candidate | n/a
- **Finding:** what is actually true, and why it matters here.
- **Proposed fix:** concrete, or "decision required" with the options.
- **Fix risk:** what applying it could break, and what must be tested.
```

---

### F-P0-01 — `origin/master` is an unsigned, unattended root credential for the whole fleet

- **File:** `modules/nixos/auto-update.nix:41-60`,
  `modules/flake/deploy-guards.nix:37-53`,
  `hosts/homelab/configuration.nix:281,312`,
  `hosts/torrent/configuration.nix:15`,
  `hosts/thinkpad/configuration.nix:16`
- **Severity:** HIGH
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A6 — anyone with push access to the GitHub repo,
  which includes both laptops' SSH keys (and therefore A7 and A8 by
  the chain in threat model §4.3), plus any PAT or CI credential with
  write scope, plus GitHub itself.
- **Rule:** new-rule candidate — `docs/hardening.md` says nothing about
  the deploy path's authenticity today.
- **Finding:** homelab (`myAutoUpdate`) and both laptops
  (`myPullDeploy`) fetch `origin/master` as root on a timer, build, and
  `nixos-rebuild switch`. homelab's successful switch then triggers
  `push-deploy-vps.service`, activating on vps too. One commit
  therefore becomes root on all four real hosts within a cycle. The
  guards in `deploy-guards.nix` — clean tree, on master, min-interval,
  protected-unit — are *safety* guards against disruption; not one is
  an authenticity check, and no signature verification exists anywhere
  in the path. By impact this is fleet-total and the rubric would call
  it CRITICAL; it is rated HIGH because reaching it requires A6, and
  because unattended patching is a deliberate design choice with real
  security value of its own. The finding is the absence of a *recorded
  decision*, not the presence of a bug.
- **Proposed fix:** decision required. Options: (a) accept, and write
  it into `docs/hardening.md` as an explicit accepted risk with its
  reasoning and the compensating controls (single admin, private repo,
  2FA); (b) verify signatures in `fetch_and_merge_master` — `git
  verify-commit` against an allowed-signers file, failing closed; (c)
  hybrid — signatures required on the hosts that matter most, accepted
  elsewhere. Note (b) meaningfully raises the cost of losing a laptop.
- **Fix risk:** (b) fails closed by design, so a signing mistake stops
  all unattended updates fleet-wide until fixed — needs the health
  alerting to actually page on it, and wants a VM test of the failure
  path, not just the success path.
- **Owner:** P7 for the mechanism; user decision on which option.

### F-P0-02 — the homelab→vps "boundary" is a deploy boundary, not a trust boundary, and the docs say otherwise

- **File:** `hosts/vps/configuration.nix:13-98` (esp. `:34-37`,
  `:62-68`), `docs/procedures/remote-access.md`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** documentation
- **Reachability:** n/a — nothing is exploitable here that is not
  already granted by design. The risk is a human over-trusting the
  written claim and siting a real decision on it.
- **Rule:** new-rule candidate — see failure mode §7.5.
- **Finding:** `docs/procedures/remote-access.md` describes the
  `vps-deploy` ForceCommand allowlist as "the actual security
  boundary". It bounds interactive shells and accidental misuse, both
  worthwhile. It does not bound root: `nix-store --serve --write` is
  dispatched unconditionally with no store-path constraint, and
  `switch-to-configuration switch` then runs as root against any path
  matching `nixos-system-vps-*` — a constraint on the *name*, not the
  contents. Whoever holds the key can activate an arbitrary closure as
  root, which is exactly what a deployer must be able to do. Any
  homelab compromise is an immediate vps compromise.
- **Proposed fix:** reword `remote-access.md` to say what the allowlist
  does bound (no shell, no non-deploy commands) and state plainly that
  homelab is trusted with root on vps. Optionally record the stronger
  alternative — signed closures — as a considered-and-declined option.
- **Fix risk:** none; documentation only.
- **Owner:** P2 to confirm the dispatcher reading; Phase 4 for the doc.

### F-P0-03 — root builds from a user-writable git repo on both laptops

- **File:** `hosts/torrent/configuration.nix:17,25`,
  `hosts/thinkpad/configuration.nix:18,26`,
  `modules/flake/deploy-guards.nix:24`
- **Severity:** HIGH
- **Confidence:** PLAUSIBLE — the configuration is confirmed; the
  privilege escalation is inferred and must be demonstrated.
- **Axis:** hardening
- **Reachability:** A7 — anything already running as `lilijoy`: a
  browser exploit, a malicious dependency, a bad agent tool call.
  Threat model §5 rates A7 the most likely initial foothold.
- **Rule:** new-rule candidate.
- **Finding:** `myPullDeploy` on both laptops sets `flakeDir =
  "/home/lilijoy/dotfiles"` and `sshKeyPath =
  "/home/lilijoy/.ssh/id_ed25519"`, so a root systemd service runs git
  operations against a directory the unprivileged user can write, using
  that user's key. A git repository is not inert data — `.git/config`
  can specify hooks, `core.fsmonitor`, `core.pager` and other commands
  git itself executes, and the `origin` remote can simply be
  repointed. `deploy-guards.nix:24` adds `safe.directory` to suppress
  git's "dubious ownership" refusal, which is git objecting to
  precisely this arrangement. If it holds, it chains: `lilijoy` → root
  on the laptop → the admin SSH key → F-P0-01 → the fleet.
- **Proposed fix:** depends on what P5/P7 demonstrate. Candidates: a
  root-owned checkout (`/etc/nixos`, as homelab already uses) with the
  user's clone kept separate; or a dedicated deploy key not owned by
  the interactive user; or dropping unattended pull-deploy on the
  laptops entirely, since they are interactive machines someone is
  present at anyway.
- **Fix risk:** moving `flakeDir` changes the day-to-day edit-and-test
  loop on the daily driver; whatever replaces it must not reintroduce
  a user-writable path, and the `sshKeyPath` workaround exists because
  root has no home-manager profile — that constraint has to be solved,
  not just moved.
- **Owner:** P7 (mechanism) and P5 (host impact), jointly.

### F-P0-04 — the tailnet ACL is flat, and it is the primary access control

- **File:** `docs/tailscale-acl.json`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the reference copy; PLAUSIBLE for live
  state — the file is *not* applied by Nix and may have drifted from
  the console.
- **Axis:** hardening
- **Reachability:** A5 — a stolen laptop, an over-broad auth key, an
  attacker-enrolled node.
- **Rule:** new-rule candidate.
- **Finding:** every grant is `"ip": ["*"]` between every tagged device
  and every other, including vps. Most services in this repo are
  exposed *only* on `tailscale0`, which is the right design — but it
  means the ACL is doing the work a firewall would otherwise do, with
  no per-service restriction anywhere. One compromised device reaches
  SSH on every host, NFS, SMB, jellyfin, the zrepl endpoints, and via
  homelab's `--advertise-routes=192.168.1.0/24` +
  `--advertise-exit-node` the entire home LAN and an internet egress
  path. On vps this is compounded by `trustedInterfaces = [
  "tailscale0" ]`, which bypasses the packet filter for that interface
  wholesale rather than opening named ports.
- **Proposed fix:** decision required — narrow to per-service grants
  (`tag:X → tag:homelab:2049` etc.), or accept and document why
  all-or-nothing is the right trade for a single-admin tailnet. Either
  way, resolve the drift risk: the file is a reference copy of console
  state that nothing enforces.
- **Fix risk:** narrowing the ACL breaks access in ways that are
  awkward to debug and are not caught by any build or VM test, since
  none of it is Nix-managed. Stage it, and keep console access.
- **Owner:** P8, plus open question §8.1.

### F-P0-05 — the ACL's `ssh` block is inert only because of a setting in another file

- **File:** `docs/tailscale-acl.json` (the `"ssh"` block),
  `modules/profiles/default.nix:81-93`
- **Severity:** LOW (latent; would be HIGH if activated)
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** none today. A5 the moment `--ssh` is enabled
  anywhere.
- **Rule:** new-rule candidate.
- **Finding:** `--ssh` is deliberately not enabled on any host, and
  `default.nix:81-93` documents why at length: Tailscale SSH
  intercepts *all* SSH to a matched host and bypasses real sshd
  including `authorized_keys` ForceCommand restrictions — it already
  broke vps-deploy's allowlist once, confirmed live. But the ACL still
  carries `ssh` rules, including `"action": "accept"` for
  device-to-device with `"users": [..., "root"]`. Those rules do
  nothing now, and would immediately grant device-to-device root SSH
  bypassing `PermitRootLogin = "forced-commands-only"` on thinkpad and
  torrent if anyone ever flipped `--ssh` on. A safety property that
  depends on a setting in a different file, with the dangerous
  configuration already written and waiting, is a footgun rather than
  a control.
- **Proposed fix:** either delete the `ssh` block from the ACL (and
  from the console) since nothing uses it, or leave it with a comment
  in the ACL itself stating it is inert-by-dependency and naming
  `modules/profiles/default.nix` as the thing keeping it that way. The
  first is safer; the file already carries a good comment on the vps
  exclusion, so extending that reasoning is natural.
- **Fix risk:** none, if `--ssh` genuinely stays off — which P8 should
  confirm holds on every host, not just where the comment lives.
- **Owner:** P8.

### F-P0-06 — `useRoutingFeatures = "both"` fleet-wide, against the repo's own rule

- **File:** `modules/profiles/default.nix:79`,
  `hosts/vps/configuration.nix:463`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the config; PLAUSIBLE for impact.
- **Axis:** hardening / needed-used
- **Reachability:** A5, A4 — a device that can reach a laptop's
  tailscale interface and use it to route onward.
- **Rule:** **violates an existing `docs/hardening.md` rule** —
  "Tailscale forwarding sysctls", which says to narrow to `"client"`
  via `lib.mkForce` on hosts that are not an exit node or subnet
  router.
- **Finding:** the shared profile sets `useRoutingFeatures = "both"`
  for every host. Only vps overrides it to `"client"`. homelab
  legitimately needs `"both"` — it advertises a subnet route and is an
  exit node. thinkpad and torrent are neither, so both carry
  tailscale's forced `net.ipv{4,6}.conf.all.forwarding` overrides with
  nothing using them: IP forwarding enabled on two machines that never
  route, one of which roams onto untrusted networks. This is the
  needed/used axis and the hardening axis at the same time — the grant
  has no consumer, and the repo already has a written rule against it
  that was applied to exactly one host.
- **Proposed fix:** invert the default. Set `"client"` in
  `modules/profiles/default.nix` and `lib.mkForce "both"` on homelab
  where it is actually used; that also lets vps's override go away.
  Fail-safe rather than fail-open.
- **Fix risk:** getting it backwards silently breaks homelab's exit
  node and its `192.168.1.0/24` subnet route, which is a
  connectivity-visible but not build-visible failure — verify with
  `tailscale status` after, and check the sysctl priority interaction
  the existing hardening rule warns about.
- **Owner:** P1 (the default) with P5 (confirming neither laptop
  routes) and P3 (confirming homelab still must).

### F-P0-07 — first-contact git fetch is TOFU

- **File:** `modules/flake/deploy-guards.nix:43`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A2/A6 — requires an active MITM at the exact
  moment of a freshly-provisioned host's first fetch.
- **Rule:** n/a
- **Finding:** `fetch_and_merge_master` uses
  `StrictHostKeyChecking=accept-new`, so the first fetch on a host
  whose root has no populated `known_hosts` accepts whatever key it is
  offered. Given F-P0-01, the repo host key is on the path to fleet
  root. The comment explains the reason honestly (root on a PC host
  has no SSH identity of its own), and the practical window is narrow.
- **Proposed fix:** pin GitHub's host key declaratively in
  `programs.ssh.knownHosts` in the shared profile, then let this fail
  closed. Cheap, and removes the window entirely.
- **Fix risk:** a stale pinned key breaks all unattended updates until
  corrected — GitHub rotates rarely but has done so.
- **Owner:** P7, with P1 if the pin lands in the shared profile.

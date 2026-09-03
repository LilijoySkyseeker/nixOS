---
slug: security-review-of-docker-userns-remap
created: 2026-09-03
status: done
frozen: true
---

# Security review of docker userns-remap

## Original plan

The `docker-userns-remap` work
(`2026-09-03-vm-verify-docker-userns-remap-for-the-game-server-containers.md`,
now frozen in `docs/plans/done/`) was closed and committed (`97baeaf`)
without the required `security` subagent pass -- the workflow skill's
own step 6 was skipped, caught by the user afterward. That plan is
frozen and cannot be edited (`done/` plans get zero further edits,
ever, per the plan skill's own rule) -- this new plan is where the
security pass's findings, and any fixes for them, actually land. This
plan was created *before* the security agent's result came back, on
explicit instruction, specifically so there is nowhere to write
findings except here.

## State

**2026-09-03, DONE.** Security agent (`af69ccbd0ac1a1a30`) found 3
CONFIRMED findings (1 MEDIUM, 2 LOW), no CRITICAL/HIGH. All three fixed
and re-verified against a real VM test, not just read back from the
module. See Findings below for the agent's original text; summary of
the fixes:

- **F1 (MEDIUM)** — `dockremap`'s subuid/subgid range (`100000:65536`)
  was byte-identical to the start of NixOS's own built-in
  `autoSubUidGidRange` pool, invisible to the auto-allocator's own
  collision check — the first `isNormalUser` account ever added to a
  host running `myDockerUserns` (not homelab today, but a real landmine
  for the future) would silently collide with it. Fixed:
  `subIdStart`'s default moved to `10000000`, documented in the option
  itself with the exact math (clear of the auto-pool for >150
  auto-allocated accounts on one host).
- **F2 (LOW)** — the migration unit ran as full root with an
  unrestricted `CapabilityBoundingSet`, wider than the operation needs
  and inconsistent with this repo's own pattern for other
  root-necessary units (`health-alerts.nix`'s `CAP_SYS_RAWIO`-only
  smartctl unit, vps's `CAP_NET_ADMIN`-only unit). Fixed: scoped to
  `CAP_CHOWN`, `CAP_FOWNER`, `CAP_DAC_OVERRIDE`, `CAP_DAC_READ_SEARCH`
  — the last two needed because `factorio.nix`/`minecraft.nix`'s
  directories are mode `0700` owned by `845`/`1000`, not this unit's
  own uid, so traversal alone needs a DAC bypass. VM-tested: still
  passes (proves the set is sufficient, not just plausible).
- **F3 (LOW)** — the migration unit was wired `wantedBy`, so `Wants=`
  doesn't propagate failure: a failed migration would silently let
  `docker.service` (and both game containers) start anyway, against
  unmigrated data. The security agent explicitly flagged this as a
  trade-off needing the user's sign-off, not an assumed fix — asked,
  user chose fail-closed. Fixed: `requiredBy` instead of `wantedBy`
  (`Requires=`, propagates failure). **Empirically proven, not just
  configured**: new VM node `brokenMigration` forces a real migration
  failure (`script = lib.mkForce "exit 1"`) and asserts
  `docker.service`'s `ActiveState` is not `"active"` — new subtest
  passes, confirming the fail-closed wiring actually holds under a
  genuine failure, not merely that the option is set.

`tests/docker-userns-remap.nix` now has 9 subtests (was 8), all green:
`nix build .#checks.x86_64-linux.docker-userns-remap -L` exit 0. Full
`verify-ladder` also clean (nixfmt, statix, deadnix, `nix flake check`,
all five `nixosConfigurations` build). Not deployed anywhere — same
still-open, separate user decision as the frozen plan this one follows
up on.

## Progress
- [x] Security agent completes its pass
- [x] Findings triaged and fixed here (F1, F2, F3), re-verified with the
  VM test after each
- [x] F3's fail-closed trade-off put to the user rather than assumed
  (per the agent's own note); user chose fail-closed
- [x] `verify-ladder` clean end to end
- [x] `plan-lint` and `plan-move ... done`

## Decisions (D)

### D1 -- F3's failure-mode trade-off: should a failed ownership migration block docker.service (fail closed) or let it start anyway (fail open, current wantedBy behavior)?
The security agent explicitly flagged this as a trade-off needing the
user's sign-off, not an assumed fix -- fail-closed makes a migration
failure a visible outage (game servers down) instead of a silent
wrong-ownership state, but changes availability semantics.


**ANSWERED 2026-09-03:** User chose fail-closed via AskUserQuestion, 2026-09-03: requiredBy (Requires=) instead of wantedBy (Wants=), so a failed migration blocks docker.service entirely rather than letting it start against unmigrated data. Implemented and empirically VM-verified (brokenMigration node forces a real failure, asserts docker.service does not reach ActiveState=active).

## Gotchas (G)

## Findings (F)
### F1 — dockremap's fixed subuid/subgid range (100000:65536) collides with NixOS's own default auto-allocation start for the first isNormalUser account, with zero cross-check between the two allocation paths

- **File:** `modules/nixos/docker-userns-remap.nix:14-30` (subIdStart/subIdCount options, default 100000/65536), `:82-97` (users.users.dockremap.subUidRanges/subGidRanges config)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening (also needed-used: an unreserved, shared numeric resource)
- **Reachability:** Not reachable today -- homelab has no isNormalUser account (confirmed: the only isNormalUser = true in the tree is modules/profiles/PC.nix:347's lilijoy, and modules/flake/hosts.nix shows homelab imports nixosModules."profile-default"/"profile-server", never "profile-pc"). But it is a self-inflicted landmine for the first future maintainer who adds any local login/admin account to homelab (or any host that also enables myDockerUserns) without an explicit subUidRanges. Read directly off the pinned nixpkgs source (rev e4bae1bd10c9c57b2cf517953ab70060a828ee6f, matches this repo's flake.lock):
  - nixos/modules/config/users-groups.nix:500-502 sets autoSubUidGidRange = mkDefault true for any isNormalUser account that doesn't already declare its own subUidRanges/subGidRanges.
  - nixos/modules/config/update-users-groups.pl:334-350's allocSubUid starts its pool at exactly (min=100000, delta=65536) -- the identical numbers this module hard-codes for dockremap.
  - The collision-tracking set (%subUidsUsed, populated only via allocSubUid calls, update-users-groups.pl:330-350) never sees explicitly-declared ranges: the loop pushing @{$u->{subUidRanges}} (:358-361) writes straight to @subUids with no registration in %subUidsUsed. A manually-declared range like dockremap's is invisible to the auto-allocator's own collision check.
  - The only warning path (:370-377) fires when a previously auto-allocated id changes between activations -- not when a fresh auto-allocation collides with a static declaration. So the first isNormalUser account ever added gets 100000:65536 -- byte-identical to dockremap -- silently, with no warning printed anywhere.
  - Consequence if it ever triggers: two different principals (the human account's own rootless container/podman use, and dockremap's Docker userns-remap) map to the exact same host uid range. A process running under that admin's own future user-namespaced tooling could produce files at the same host uids (100845, 101000, etc.) myDockerUserns's migration already produced for factorio-main/minecraft-vanilla-plus's bind-mount data -- the isolation userns-remap exists to provide between principals is defeated for exactly the range this repo relies on.
- **Rule:** n/a (no literal docs/hardening.md bullet covers subuid/subgid allocation) -- new-rule candidate: "any fixed subuid/subgid range declared in this repo must either sit above NixOS's own auto-allocation ceiling, or the host must assert no isNormalUser account exists without an explicit non-overlapping subUidRanges."
- **Fix risk:** Changing subIdStart to a non-colliding value is itself a disruptive change to an already-disruptive rollout (same full dockerd restart plus image re-pull already flagged in the frozen plan's G4) -- needs to be tested for a value clear of the auto-pool's range (100000 through roughly 100000 + 29000*65536), or guarded with an assertions entry that fails eval if any isNormalUser lacks an explicit subUidRanges while myDockerUserns.enable is true. An assertion needs testing against thinkpad/torrent (the two hosts that do have isNormalUser accounts today) to confirm it doesn't spuriously trip there once/if myDockerUserns is ever imported into profile-pc.


**FIXED 2026-09-03:** subIdStart default moved from 100000 to 10000000, clear of NixOS's own autoSubUidGidRange pool for any realistic account count. VM-verified: tests/docker-userns-remap.nix's subuid-render subtest updated and still passes.

### F2 — migration unit runs as full root with an unrestricted CapabilityBoundingSet, wider than the operation needs, inconsistent with this repo's own established pattern for root-necessary units

- **File:** `modules/nixos/docker-userns-remap.nix` (systemd.services.docker-userns-remap-migrate.serviceConfig)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** No adversary path today -- the script's chown --from/touch arguments are entirely static, built from Nix-evaluated config, not runtime/attacker-controlled input. This is a blast-radius gap, not a live exploit: if this unit's script logic were ever extended to touch anything derived from outside input, or a supply-chain issue landed in coreutils, the unit would retain every root capability (CAP_SYS_ADMIN, CAP_NET_ADMIN, CAP_SYS_MODULE, etc.) rather than only CAP_CHOWN/CAP_FOWNER (and likely CAP_DAC_OVERRIDE/CAP_DAC_READ_SEARCH, since it must traverse into and modify a tree it does not currently own, 845/1000, before the chown lands).
- **Rule:** n/a literally -- docs/hardening.md's "Custom systemd.services sandboxing" bullet lists the exact stack this unit already applies in full (NoNewPrivileges, ProtectSystem=strict + ReadWritePaths, ProtectHome, ProtectKernelModules, ProtectKernelTunables, ProtectKernelLogs, ProtectControlGroups, RestrictNamespaces, PrivateTmp) and does not mention CapabilityBoundingSet in that list. New-rule candidate: this repo already restricts CapabilityBoundingSet on other root-necessary, narrow-purpose units doing exactly this class of operation (modules/nixos/health-alerts.nix:310-311, CAP_SYS_RAWIO only, for smartctl; hosts/vps/configuration.nix:542-543, CAP_NET_ADMIN only) -- the same pattern applies cleanly here and wasn't.
- **Fix risk:** Needs the exact minimal capability set worked out and VM-tested (CAP_CHOWN, CAP_FOWNER, plausibly CAP_DAC_OVERRIDE) -- an under-scoped set fails as a plain "Operation not permitted" on the chown, which the existing VM test (tests/docker-userns-remap.nix) would actually catch since it exercises the real migration codepath, but should be re-run explicitly after any such change rather than assumed safe from the module reading correct.


**FIXED 2026-09-03:** CapabilityBoundingSet scoped to CAP_CHOWN, CAP_FOWNER, CAP_DAC_OVERRIDE, CAP_DAC_READ_SEARCH, matching this repo's pattern for other root-necessary units (health-alerts.nix, vps). VM-verified: the full 8-subtest suite (now 9) still passes with the scoped set, proving it's sufficient for the real 0700-owned directory traversal, not just plausible.

### F3 — a failed migration does not block docker.service from starting (wantedBy, not requires/bindsTo)

- **File:** `modules/nixos/docker-userns-remap.nix` (systemd.services.docker-userns-remap-migrate.wantedBy = [ "docker.service" ]; before = [ "docker.service" ];)
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening / needed-used (robustness, not privilege)
- **Reachability:** Not an adversary path -- an availability/correctness gap. NixOS's own script = wrapper always injects set -e (nixos/lib/systemd-lib.nix:552-557, confirmed against the pinned rev), so a failing chown/touch partway through the migration loop aborts the whole unit rather than silently continuing to the next entry -- that part is correct. But Wants= (what wantedBy produces) does not propagate failure per systemd.unit(5), only Before= enforces ordering -- so if the migration unit fails, docker.service still starts immediately after it per the ordering constraint, regardless of the failure. The container then comes up under an active userns-remap against bind-mount data still at its pre-migration ownership: not a privilege leak (the remap boundary itself holds), but a silent, unblocked "permission denied" state for the game server with nothing stopping docker.service from proceeding.
- **Rule:** n/a; new-rule candidate.
- **Fix risk:** Switching to requires/bindsTo would make docker.service (and both game containers) refuse to start at all on a migration failure -- arguably the correct fail-closed behavior for a security-relevant remap, but it changes availability semantics (a transient chown failure now takes the game servers down instead of leaving them silently broken) and should be a decision the user signs off on, not an assumed fix. Needs a VM-test case that forces a migration failure and confirms docker.service is actually blocked before relying on it.


**FIXED 2026-09-03:** Switched wantedBy to requiredBy (Requires=, propagates failure) per D1's user decision (fail-closed). Empirically VM-verified with a new brokenMigration node that forces a real migration failure and asserts docker.service's ActiveState never reaches active -- proves the fail-closed wiring holds under genuine failure, not just that the option is set.

## Checked and clean

Reviewed the full diff of commit 97baeaf: modules/nixos/docker-userns-remap.nix, tests/docker-userns-remap.nix, modules/services/factorio.nix, modules/services/minecraft.nix, hosts/homelab/configuration.nix, modules/flake/checks.nix, modules/flake/hosts.nix, plus the doc-only changes to docs/hardening.md and docs/audits/2026-08-26/RESUME.md, against docs/hardening.md, docs/procedures/secrets.md, and the pinned nixpkgs source (flake.lock rev e4bae1bd10c9c57b2cf517953ab70060a828ee6f, fetched via nix flake prefetch and read directly, not from memory). Specifically checked and found correct:

- **chown -R symlink-following risk:** confirmed against the pinned coreutils' own --help output that -P ("do not traverse any symbolic links") is the default recursive-traversal mode -- a malicious symlink planted inside /srv/factorio/main or /srv/minecraft/vanilla-plus by a compromised container (writable pre-migration, at host uid 845/1000) pointing outside the tree would have its own link ownership changed (lchown) but its target would not be touched. No path-traversal/privilege-escalation via the migration script.
- **ReadWritePaths scoping:** limited to exactly cfg.migrations' declared paths (/srv/factorio/main, /srv/minecraft/vanilla-plus in the real homelab wiring) -- not /srv broadly, and this is the minimum needed for a chown -R to complete, not an over-grant.
- **StateDirectory marker placement:** confirmed outside the migrated tree (/var/lib/docker-userns-remap-migrate/, not inside /srv/...), consistent with the stated reason (factorio's own entrypoint does its own whole-volume chown -R factorio:factorio at every start and would choke on a file outside its mapped uid range) and covered by its own VM subtest.
- **Idempotency / --from scoping:** chown --from=uid:gid only touches files still at the pre-migration owner, matching the module's own doc comment and exercised twice in the VM test (first real run, then a forced second run asserting no change).
- **Daemon-wide blast radius:** confirmed only factorio-main and minecraft-vanilla-plus run under virtualisation.oci-containers.containers anywhere in this repo's homelab wiring (modules/services/factorio.nix, modules/services/minecraft.nix are the only files defining virtualisation.oci-containers.containers.*) -- enabling the daemon-wide userns-remap setting does not silently affect any other container homelab runs, because there isn't one.
- **No collision with this repo's other declared uid/subuid ranges:** grepped for subUidRanges/subGidRanges fleet-wide -- dockremap is the only declaration; the other isSystemUser accounts touched by this diff's neighbors (octodns, health-alerts, samba) don't declare subordinate ranges at all.
- **Secrets handling:** the module and its two call sites (factorio.nix, minecraft.nix) reference no sops.secrets.*, decrypt nothing, and stage no plaintext -- the migration's uid/gid values (845, 1000) are public image-baked constants, not credentials. No secrets-policy interaction to review.
- **No new firewall/network exposure:** this diff touches no networking.firewall.*, no -p publish, no ports = [...] -- the existing published-port scoping in factorio.nix/minecraft.nix (unchanged by this commit) still governs game-server reachability, unaffected by the userns-remap work.
- **Deployment state matches the frozen plan's own claim:** hosts/homelab/configuration.nix sets myDockerUserns.enable = true for build-verification only; nothing in this diff performs or triggers an actual nixos-rebuild switch.

Not independently re-run: the VM test itself (tests/docker-userns-remap.nix) was read but not re-executed -- took the frozen plan's "8 subtests green" claim on trust rather than re-verifying it, since this review is read-only and the test's own logic (reviewed above) matches what it claims to assert.

_security finished 2026-09-03T20:42:32Z -- see Findings above._

# Accepted risks

Things this fleet is **audited and knowingly not fixing**, with the
reason. The point is that a future pass — human or agent — can tell
"decided against" apart from "never noticed", and does not re-litigate a
settled trade-off from scratch.

**What belongs here.** A risk that was found, understood, and left in
place on purpose. Each entry names what the exposure actually is, why it
is accepted, what would change the answer, and where the evidence lives.

**What does not.** Work that is merely *deferred* (that is a plan file via `plan-new`),
a decision nobody has made yet (that is
[`audits/2026-08-26/user-actions.md`](audits/2026-08-26/user-actions.md)
§4), or a rule everyone should follow (that is
[`hardening.md`](hardening.md)).

**Scaffolded 2026-08-27**, during the 2026-08-26 audit's Phase 4. §1 is
complete as far as it can be. **§2 is not acceptance** — it is the list
of risks that cannot move into §1 until decisions D1–D14 are answered,
recorded here so the shape of the finished document is visible.

---

## 1. Accepted

### AR-1 — The configuration repository is public

**Sits on:** [threat model](threat-model.md) §4.7 ·
**Evidence:** `findings.md` C1, `F-P8-02`

Every `.nix` file, every firewall rule, every service topology and every
revision of `secrets/secrets.yaml` is permanently downloadable by
anyone, and always will be for what is already pushed. There is no
discovery step for an attacker: what answers on a port is known in
advance from the config.

**Why accepted:** it is the point of publishing dotfiles, and for
already-pushed history it is not reversible anyway — deleting or
re-encrypting changes nothing about copies already taken.

**What this costs, and where the cost is paid instead:** the *value* of
every secret ever committed, not the recipient list. That is
[`hardening.md`](hardening.md) rules 1 and 2 — rotate at the provider,
and give each host only what it consumes.

**What would change the answer:** deciding the repo does not need to be
public (raised as check 5 under `F-P7-17`). That would bound future
exposure only; it retracts nothing already published.

### AR-2 — homelab holds root on vps, by design

**Sits on:** [threat model](threat-model.md) §4.2 ·
**Evidence:** `findings.md` H5, `F-P0-02`, `F-P2-10`, `F-P8-13`

homelab push-deploys vps through the `vps-deploy` account. The forced
command bounds shells and accidents; the polkit grant behind it covers
`StartTransientUnit`, which is "run anything as root". The dispatcher
itself was audited and is sound — the privilege is granted deliberately,
not leaked.

**Why accepted:** an automated deploy path that activates a system
configuration *is* root on the target. There is no version of this
feature that is not.

**Consequence to hold onto:** homelab and vps are one blast radius, not
two. Do not write a control that assumes otherwise.
`docs/procedures/remote-access.md` used to, and was corrected in this
phase.

**What would change the answer:** the reverse direction is *not*
accepted and was fixed — vps could reach root on homelab through an
arithmetic injection in `deploy-guards.nix` (`F-P7-03`, fixed in
`b51e328`).

### AR-3 — zrepl's daemon and its SSH transport both run as root

**Sits on:** [threat model](threat-model.md) §4.5 ·
**Evidence:** [`backups.md`](backups.md); `hardening.md` "Dedicated
service users"

ZFS admin ioctls need root, and `ssh+stdinserver` needs the *SSH* user
to be root too, because the stdinserver socket sits in a 0700 runtime
directory with no chmod applied.

**Why accepted:** documented, long-standing, and bounded by a real
control — a forced command in `authorized_keys` pinning the key to
exactly `zrepl stdinserver <identity>`, with the identity fixed
server-side rather than asserted by the client. Pull direction was
chosen deliberately so a compromised *source* cannot drive the backup
host.

**What would change the answer:** nothing short of upstream zrepl
supporting an unprivileged transport. Already the standing example in
`hardening.md`'s dedicated-service-user rule.

### AR-4 — Two interactive shell paths execute code the flake lock does not cover

**Sits on:** [threat model](threat-model.md) §4.7 ·
**Evidence:** `findings-tail.md` §2, `F-P8-17`

`__fish_command_not_found_handler` runs `comma $argv[1]`, so every typo
becomes a network fetch and execution of a nixpkgs package of that name;
`ns` runs `nix shell 'nixpkgs/nixos-unstable#…' --impure`, deliberately
outside the lock.

**Why accepted:** both are deliberate ergonomic choices on an
interactive desktop, made with the trade-off understood. They are
recorded because "what executes code the lock does not cover" is a
question that needed an answer, and these are the whole answer.

**Scope limit:** interactive desktop only. Neither belongs on a host
that builds or deploys unattended — `F-P8-15` is the same class of
problem in `flake-update-test`, and it is *not* accepted.

### AR-5 — There is no CI, and that is the safer posture

**Sits on:** [threat model](threat-model.md) §4.1 ·
**Evidence:** `findings-tail.md` L-05, `F-P7-17`

Confirmed by a full-history scan across every branch: no workflow file
has ever existed. So the two worst PR-shaped paths do not exist here —
nothing triggers on `pull_request` from a fork, and no CI holds a
credential.

**Why accepted:** this is a negative result being *preserved on
purpose*, not an absence nobody got round to. `master` is unattended
fleet root; the moment any workflow is added it becomes an
unauthenticated inbound path toward it, and `pull_request_target` would
be catastrophic.

**What would change the answer:** adding CI is a decision with a
security review attached, not a chore. If it ever happens, the workflow
must not hold a credential and must not run on fork PRs.

**Not covered by this acceptance:** whether `master` is protected at all
(D3). No CI means branch protection is the *only* remaining control, so
AR-5 makes D3 more urgent, not less.

### AR-6 — ~~The NFS shares are `nosuid,nodev` but not `noexec`~~

**Superseded 2026-09-03 — no longer accepted, fixed instead.** The user
decided D12 toward the fix, not acceptance: `noexec` is now in
`modules/nixos/nfs-homelab-mounts.nix`'s shared `mountOpts`, closing the
last execution path from a homelab-controlled filesystem onto both
laptops. Build-verified on `thinkpad`/`torrent`. See
`2026-09-03-add-noexec-to-the-homelab-nfs-share-mounts.md`. Original
acceptance text kept below for history.

**Sits on:** [threat model](threat-model.md) §4.5 ·
**Evidence:** `F-P6-05`; applied in `516ef31`

Both laptop mounts of `/home/lilijoy/storage{,-bulk}` carry `nosuid` and
`nodev`. `noexec` was considered and declined.

**Why accepted (superseded, see above):** a media share will eventually
have something legitimate run off it, and a `noexec` that gets removed
under pressure is worse than one never set. A scan found nothing that is
a program there today, so the risk accepted is small and the reasoning
is about the future, not the present.

**What would change the answer:** ~~D12. If the answer is "nothing will
ever be run from those shares", `noexec` is one word and closes the last
execution path from a homelab-controlled filesystem onto both
laptops.~~ **Answered — see superseded note above.**

### AR-7 — The game servers auto-update their mods, and the mod set decides the game version

**Sits on:** [threat model](threat-model.md) §4.7, adversary A6 ·
**Evidence:** `findings.md` H3, `F-P4-03`, `F-P4-13` · **Decides D14**

Sixteen third-party Modrinth projects are resolved **by slug at every
container start** — every reboot, and every switch touching the unit —
at the `alpha` release channel, with
`MODRINTH_DOWNLOAD_DEPENDENCIES = "required"` pulling further transitive
artifacts nobody has listed. Both Factorio servers do the same through
`UPDATE_MODS_ON_START`. There is no version constraint and no integrity
check on any of it.

**Why accepted:** the servers exist to be played on and current. A
pinned mod set is only as good as the discipline that updates it, and a
stale mod set is the failure that actually happens. `alpha` is
load-bearing rather than lazy: mod releases lag game releases, so
restricting to `release` would hold the server on an old Minecraft
version for as long as any single mod had only a pre-release build out.
This is a deliberate availability-over-supply-chain trade, made with the
exposure understood.

**What was tightened while accepting it (2026-08-27):** the game version
no longer *leads* the mod set. `VERSION = "LATEST"` is gone, replaced by
`VERSION_FROM_MODRINTH_PROJECTS = "true"`, so the server tracks the
newest Minecraft version **every** project already supports. It fails
closed — an unresolvable set aborts startup rather than falling back to
a version the mods do not support. That removes the "game moved, mods
broke" class of outage without changing the trust decision. The variable
was also moved off the legacy `MODRINTH_ALLOWED_VERSION_TYPE` name,
which the version resolver does not read — under the old name the mod
downloader would have used `alpha` while the version resolver silently
used `release`.

**What is being accepted, stated plainly:** any one of sixteen upstreams
is a sufficient entry point into a process that handles untrusted
internet traffic through vps's DNAT and holds a writable bind mount. And
because the repo is public, an attacker can read the exact mod list,
derive the parsing surface, and match it against published advisories
before sending a packet — this is why `F-P4-03` is HIGH rather than
MEDIUM.

**What bounds it today:** `--cap-drop=ALL` with a minimal add-back list,
`--security-opt=no-new-privileges:true`, `--read-only` on minecraft, a
`nosuid,nodev` tmpfs, and docker's default seccomp profile. The
capability dimension is genuinely well handled; the resource dimension
is not, and is tracked in `2026-08-26-do-a-full-security-audit-hardening-pass-on-homelab.md` (F-P4-07).

**What would change the answer:** a compromise anywhere in the chain, or
the host coming to hold anything of value beyond game state. Three
tightenings remain available without giving up auto-update — mark
non-critical projects optional with a `?` suffix so they are excluded
from version calculation, pin individual projects by version where a mod
matters more than its freshness, and apply the container resource
ceilings.

---

### AR-8 — The recovery ISO serves the whole filesystem, unauthenticated

**Sits on:** [threat model](threat-model.md) §8, open question 6 ·
**Evidence:** `findings.md` H6, `F-P4-01`, `F-P5-10` · **Decides D8**

copyparty's rendered config on the isoimage has an empty `[accounts]`
block with `A: *` on volume `/` — copyparty 1.20.20 expands `A` to
`rgwmda.`: anonymous read, write, move, delete, and admin over the
**entire filesystem**, on a host-wide port 3923, with the module's own
sandbox nullified by `BindPaths=["/var/lib/copyparty", "/"]`. Only Unix
DAC limits it. The ISO separately bakes in `vars.publicSshKeys` as root's
`authorizedKeys` — these are SSH *public* keys, already plaintext
elsewhere in this public repo, so this is not a credential leak; it is
how the admin SSHes into the booted rescue environment as root. The
distinct, LOW-rated issue here (`F-P5-10`/`L-03`) is the built ISO
*artefact* sitting unverified in a user-writable `~/Downloads` with no
checksum — since the flake is public and pinned, a swapped or
attacker-built ISO with a matching filename would go undetected. That is
an integrity/tampering concern, not a confidentiality one, and is tracked
separately (a `.sha256` written alongside the build, verified before
boot) rather than folded into this acceptance.

**Why accepted:** confirmed by the user 2026-09-03 — the ISO is not
meant to be secure, it is meant to make recovery of these hosts, or a
third party's system it's booted on, as easy as possible. Unimpeded
read/write access to a broken box's entire filesystem, with no
credential to look up or type, is the point, not an oversight. This
also covers using the media to help recover machines outside this
fleet, where no pre-shared credential could exist in the first place.

**What is being accepted, stated plainly:** anyone who boots this ISO on
any network — not just the machine it's meant to rescue — gets
unauthenticated full filesystem read/write/delete on the booted host. The
ISO's physical and network handling (don't leave it plugged into an
untrusted network, don't leave the built image sitting in a user-writable
directory longer than needed) is the actual control, not anything in
`copyparty-iso.nix`.

**What would change the answer:** if the ISO's role changed from
"disaster recovery, plugged in deliberately" to something routinely
network-attached or handed to someone else unsupervised, this trade
would need revisiting — that scenario is out of scope for what this
image is for today.

---

## 2. Not yet acceptable — blocked on a decision

**These are not accepted.** Each is a risk whose acceptance is a real
option, but which nobody has chosen yet. They live in
[`audits/2026-08-26/user-actions.md`](audits/2026-08-26/user-actions.md)
§4 as decisions D1–D14; when one is decided *toward acceptance*, it
moves up into §1 with its reasoning, and when it is decided toward a fix
it leaves this file entirely.

| # | If accepted, what is being accepted | Bears on |
|---|---|---|
| ~~D1~~ | **Answered — not accepted, and fixed.** All ten credentials from `F-P8-02` were rotated (rotation-runbook.md, closed 2026-09-01); the old exposed values no longer authenticate to anything. | C1, `F-P8-02` |
| D2 | That `origin/master` is unsigned and unattended fleet root | H1 |
| ~~D3~~ | **Answered 2026-08-27.** `master` had no protection and no rulesets at all; a ruleset now blocks force pushes and deletions with no bypass actors. Signed commits deliberately not enabled yet — that is D2. | H1, AR-5 |
| D4 | That no backup copy is out of reach of a single root | C3 |
| D5 | That neither laptop has FDE, and thinkpad hibernates RAM to unencrypted swap | H7 |
| D6 | That any tailnet device reaches nearly everything | ACL cluster |
| ~~D7~~ | **Answered 2026-09-03 — not accepted, implementing.** Tracked as `2026-09-03-design-and-implement-intrusion-detection-for-homelab.md`. | H8 |
| ~~D8~~ | **Answered 2026-09-03 — accepted, see AR-8.** Intended: not meant to be secure, meant to make recovery (of these hosts, or a third party's) as easy as possible. | H6 |
| ~~D9~~ | **Answered 2026-08-27 — nothing accepted, all three fixed.** KDE Connect scoped to `tailscale0`; Steam remote play and avahi/mDNS removed outright. | `F-P1-04`, `F-P5-06` |
| ~~D10~~ | **Answered 2026-08-27 — nothing accepted.** The ports were Steam Remote Play's (`programs.steam.remotePlay.openFirewall`), and closed along with D9. | wave 2 §2.9 |
| D11 | That `flake-update-test` auto-merges upstream updates to fleet root on build success alone | `F-P7-10` |
| ~~D12~~ | **Answered 2026-09-03 — not accepted, and fixed.** `noexec` added to `nfs-homelab-mounts.nix`, closing the last execution path from a homelab-controlled filesystem onto both laptops. AR-6 marked superseded. | `F-P6-05` |
| ~~D13~~ | **Answered 2026-08-27 — not accepted, and fixed.** The user never reaches the game servers from the LAN, so `myDockerPublishGuard` now allows only wg0 and tailscale0 (wave 2 item 2.1, VM-tested). | `F-P4-02`, `F-P3-04` |
| ~~D14~~ | **Answered 2026-08-27 — accepted, see AR-7.** Auto-update is kept deliberately; the game version now follows the mod set instead of leading it. | `F-P4-03`, `F-P4-13` |

~~Two of these have a written home waiting for them: **D2** must land in
this file as an explicit accepted risk if accepted (`findings.md` §5),
and **D8** needs a written justification either way — "plausibly
deliberate for recovery media" is not one, and threat model §8.6 asked
for it directly.~~ **D8 done, 2026-09-03** — see AR-8 above. **D2** is
still open; note its accepted-risk slot (if accepted) is not AR-7 —
that's D14's — it would be the next free number.

# Accepted risks

Things this fleet is **audited and knowingly not fixing**, with the
reason. The point is that a future pass — human or agent — can tell
"decided against" apart from "never noticed", and does not re-litigate a
settled trade-off from scratch.

**What belongs here.** A risk that was found, understood, and left in
place on purpose. Each entry names what the exposure actually is, why it
is accepted, what would change the answer, and where the evidence lives.

**What does not.** Work that is merely *deferred* (that is a handoff note in `docs/plans/`),
a decision nobody has made yet (§2 below), or a rule everyone should
follow (that is [`hardening.md`](hardening.md)).

**Evidence ids** (`C1`, `H5`, `F-P8-02`, …) point into the 2026-08-26
audit, removed from the tree on 2026-10-25:
`git show 0aa27a5:docs/audits/2026-08-26/findings.md`.

**Not accepted, ever:** a finding that's hard to fix only because agents
run as `lilijoy`. That is a same-uid problem the agents' own Unix user
(`modules/nixos/agent-user.nix`) exists to remove. Leave such a finding
**open** (in the PR description or a handoff note) with a dated note
naming the fix.
Don't record it here, and don't offer "accept" as the recommended option.
(User, 2026-10-05.)

---

## 1. Accepted

### AR-1 — The configuration repository is public

**Sits on:** [threat model](threat-model.md) B7 ·
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

**Sits on:** [threat model](threat-model.md) B2 ·
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
arithmetic injection in the old `deploy-guards.nix` (`F-P7-03`, fixed in
`b51e328`). What vps now feeds homelab's push-deploy is its two
revisions, which only reach git as 40-character hex shas (`is_revision`
in `modules/flake/deploy-revision.nix`), and its kernel links, which
are only compared as strings. Neither ever chooses what homelab builds.

### AR-3 — zrepl's daemon and its SSH transport both run as root

**Sits on:** [threat model](threat-model.md) B5 ·
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

### AR-4 — An interactive shell path executes code the flake lock does not cover

**Sits on:** [threat model](threat-model.md) B7 ·
**Evidence:** `findings-tail.md` §2, `F-P8-17`

On the desktops, bash's `command_not_found_handle` runs `comma "$@"` (as
does the fallback fish shell's `__fish_command_not_found_handler`), so
every typo becomes a network fetch and execution of a nixpkgs package of
that name.

**Why accepted:** it is a deliberate ergonomic choice on an
interactive desktop, made with the trade-off understood. It is
recorded because "what executes code the lock does not cover" is a
question that needed an answer, and this is the whole answer.

**Scope limit:** interactive desktop only (`tooling-desktop.nix`). It
doesn't belong on a host that builds or deploys unattended — `F-P8-15` is the same class of
problem in `flake-update-test`, and it is *not* accepted.

### AR-5 — There is no CI, and that is the safer posture

**Sits on:** [threat model](threat-model.md) B1 ·
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
AR-5 makes D3 more urgent, not less. 2026-10-06: the agent user's bot
account gets write access to this repo, so `master` protection (PR + 1
review) is now a step of
`2026-10-06-build-the-agent-s-place-a-separate-agent-user-on-torrent-reachable.md`
(Task 6), done by the user in GitHub's settings.

Stale since 2026-08-28: `.github/workflows/plan-gate.yml` exists, so "no
workflow file has ever existed" no longer holds. It runs on `pull_request`
and holds no credential, so the posture the acceptance protects is intact.
2026-10-06: `plan-gate.yml` removed with the plan-file system; the repo has
no workflow file again.

### AR-7 — The game servers auto-update their mods, and the mod set decides the game version

**Sits on:** [threat model](threat-model.md) B6, and B1 for the supply chain ·
**Evidence:** `findings.md` H3, `F-P4-03`, `F-P4-13` · **Decides D14**

Sixteen third-party Modrinth projects are resolved **by slug at every
container start** — every reboot, and every switch touching the unit —
at the `alpha` release channel, with
`MODRINTH_DOWNLOAD_DEPENDENCIES = "required"` pulling further transitive
artifacts nobody has listed. Both Factorio servers do the same through
`UPDATE_MODS_ON_START`. The Hytale server (2026-10-14) goes further: it
replaces its own server JAR, assets and `start.sh` from Hytale's update
service, applied when no one is online. Only the first-install seed JAR
is hash-pinned. Clients refuse a server whose protocol version differs,
so a held-back server is unplayable. There is no version constraint and no integrity
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

### AR-9 — homelab runs immich 2.x, which is EOL and marked insecure

**Sits on:** [threat model](threat-model.md) B4 ·
**Evidence:** CVE-2026-59258, CVE-2026-82272 ·
**Decided:** 2026-09-24, by the user, during the routine flake update
(2026-09-24-routine-flake-update-2026-09-24-and-the-journald-extraconfig-removal.md#D1)

nixpkgs-stable 26.05.10478 began marking `immich-2.7.5` insecure: the 2.x
series is end-of-life upstream and will receive no further fixes, and two
CVEs are named against it. 3.x ships in 26.11, which homelab — pinned to
nixpkgs-stable — is not on. Left alone this blocks homelab's evaluation
entirely, so the update could not land without an answer either way.

`modules/services/immich.nix` therefore sets
`nixpkgs.config.permittedInsecurePackages = [ "immich-2.7.5" ]`.

**Why accepted:** the alternative fix is a major-version jump with a real
database migration on a live photo library, which needs its own verified
backup, a VM test and an observed switch — not a bolt-on to a lockfile
bump. The service is tailnet-only (`host = "0.0.0.0"` bound broad but
restricted at the firewall, per
2026-09-03-add-immich-tailscale-only-to-homelab.md#G3), so it is not
reachable from the public internet; the exposure is to anything already
on the tailnet, which is the standing D6 cluster.

**Scope of the exemption:** deliberately narrow, but be precise about
*how*. It is declared in the immich module rather than in a host file or
the fleet-wide `modules/flake/pkgs.nix`, so only a host importing that
module carries it at all — verified: homelab has it, the other four hosts
have no such attribute. Within homelab it is still an ordinary host-level
`nixpkgs.config`, i.e. it would permit that exact package anywhere in
homelab's closure; it is not scoped *to the immich derivation*. It names
the version exactly, so a future `immich-2.7.6` re-breaks the build on
purpose rather than silently inheriting the exemption.

**One gap in that tripwire, stated plainly:** immich ships as two
derivations, and only `immich-2.7.5` carries `knownVulnerabilities`.
`immich-machine-learning-2.7.5` has its own `meta` without them, so it is
not what the exemption names and not what a future bump would trip on —
and it is the component that parses untrusted uploads. The version-exact
guard therefore covers the server package only. This does not change the
acceptance (the whole service is tailnet-only either way), but a reader
should not infer more coverage than the one entry provides.

**What would change the answer:** an exploit for either CVE that does not
require tailnet access, or any move to expose immich beyond the tailnet.

**What retires this entry:** the 3.x migration, tracked as item 1 of
2026-09-24-migrate-homelab-s-immich-from-the-eol-2-x-to-3-x.md (which also
carries an unrelated journald cleanup gated on the same stable move). Note this
does *not* retire itself when stable rolls to 26.11 — at that point the
version string simply stops matching anything and goes quietly dead,
while the 2.x→3.x database migration would run unsupervised on the next
switch. The channel move is the deadline for doing this properly, not the
fix.

---

## 2. Not yet acceptable — blocked on a decision

**These are not accepted.** Each is a risk whose acceptance is a real
option that nobody has chosen yet. Decided toward acceptance, it moves
up into §1 as the next free AR number; decided toward a fix, it leaves
this file. The answered decisions (D1, D3, D7–D14) are in git history.

| # | If accepted, what is being accepted | Bears on |
|---|---|---|
| D2 | That `master` is unsigned, unattended root on every host | B1 |
| D4 | That no backup copy is out of reach of root on homelab: its B2 key can change the bucket's lifecycle rules, and torrent's and thinkpad's homes have no offsite copy | B5 |
| D5 | That torrent has no full-disk encryption (thinkpad has LUKS2 with TPM2 + PIN and Secure Boot) | §1 asset 5 |
| D6 | That any tailnet device reaches nearly everything | B4 |

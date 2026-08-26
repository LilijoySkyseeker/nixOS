# Threat model

Phase 0 of the 2026-08-26 fleet-wide security audit (see `TODO.md`).
Written first, and deliberately before any findings, so that all eight
Phase 1 audits rate severity against the same adversaries instead of
each inventing a scale.

**Who this is for.** Primarily the P1–P8 audit agents: §6 is the
severity rubric they must apply, and §7 is the list of recurring
failure modes they should actively probe for. Secondarily it is meant
to outlive the audit — every future "should I expose this service?"
decision is really a question about §3 and §4.

**One fact that colours everything below: this repository is public
on GitHub.** The configuration, its full history, and the encrypted
secrets file are all world-readable. §4.7 works through what that does
and does not change; the short version is that no finding may be
discounted on the grounds that an attacker would not know about it.

**Status of the claims here.** Everything in §2–§4 was read out of the
config in this repo on 2026-08-26 and is cited by `file:line`. Where
something is inferred rather than read, it says so. Where the config
and the prose docs disagree, that disagreement is recorded as an open
question in §8 rather than silently resolved — a doc that describes an
intended boundary the config does not actually implement is itself a
finding.

---

## 1. What we are protecting

In rough order of how bad losing it would be:

1. **The backup pools.** `zbackup` on homelab holds the only
   consolidated copy of every host's data, plus the offsite restic →
   Backblaze copy derived from it. An adversary who can *destroy*
   backups turns every other incident into a permanent loss. Note that
   this asset is uniquely vulnerable to an *authorized* actor: a
   replication peer with a legitimate handle can delete snapshots
   without ever needing a vulnerability.
2. **Root on any host**, because §4 shows root on one host generally
   converts into root on others.
3. **The secrets in `secrets/secrets.yaml`** and the age/host keys that
   decrypt them — tailscale auth keys, the wireguard private key and
   PSK, the vps-deploy private key, the zrepl keys, the Discord
   webhook, the restic/Backblaze credentials.
4. **`origin/master` on GitHub**, which §4.1 shows is effectively a
   root credential for the whole fleet.
5. **Personal data at rest** — `/storage`, `/storage-bulk`, home
   directories, and whatever the jellyfin library reveals about the
   household by its mere contents.
6. **Availability** of the services people actually use (jellyfin, the
   game servers, the shares). Real, but the lowest of these: an outage
   is recoverable in a way the first four are not.

---

## 2. Exposure map

Where each host actually sits, and what can reach it. This is the part
most likely to be misremembered, and misremembering it is exactly what
caused the finding that triggered this audit.

| Host | Public v4 | Public v6 | Listens publicly | Notes |
|---|---|---|---|---|
| `vps` | yes (DigitalOcean, `ens3`) | yes (apex + jellyfin AAAA, native) | 80, 443 tcp; 51820 udp; 25565 tcp + 19132/34197/34198 udp DNAT'd onward | the intended edge |
| `homelab` | no (ISP CGNAT) | **yes — ISP RA-delegated on the LAN NIC** | nothing, after the 2026-08-26 fixes | the trap: see §2.1 |
| `torrent` | no | **yes — confirmed live 2026-08-26** (RA-delegated GUA + v6 default route) | sshd, rpcbind/111, LLMNR/5355, mDNS/5353, KDE Connect 1716 all bound on `[::]`/`*` | daily driver; §2.1 applies to this host too, not just homelab |
| `thinkpad` | no | assume yes | same profile-inherited set as torrent | **roams onto untrusted networks**, where the local v6 posture is unknowable in advance |
| `isoimage` | n/a | n/a | 3923 tcp, host-wide (`modules/services/copyparty-iso.nix:43`) | recovery media, whatever network it is booted onto |

### 2.1 The CGNAT illusion

> **Update, 2026-08-26, from P1's findings and confirmed live: this is
> not homelab-only.** `torrent` also holds a globally-routable
> RA-delegated IPv6 GUA with a v6 default route, right now, while the
> shared desktop profile opens 106 ports host-wide (Steam remote play,
> avahi, and KDE Connect's 1714-1764 TCP+UDP range). `kdeconnectd` is
> confirmed listening on `*:1716` on both v4 and v6. So the exact
> mistake described below — a host-wide rule justified by a belief
> about the network — exists on the daily driver as well, and the
> belief there ("it's just a desktop on the home LAN") is the same
> shape as the one that was wrong on homelab. Whether the ports are
> genuinely reachable from off-LAN depends on the firewall's real
> state, which could not be read without root; P5 owns settling it.

homelab has no public IPv4 — it is behind ISP CGNAT — and for years
that made every host-wide firewall rule on it *effectively*
LAN-scoped. That is no longer true and, per the comment at
`hosts/homelab/configuration.nix:357-366`, was confirmed on
2026-08-26: the LAN NIC carries a real, globally-routable,
ISP-RA-delegated IPv6 address. A rule written as
`networking.firewall.allowedTCPPorts` opens the port on that address,
to the entire internet, with no NAT in front of it.

This matters beyond the specific ports already fixed, in three ways
the audits must keep in mind:

- **It is silent.** Nothing warns you. The config looks identical to
  the config that was safe under IPv4-only, and every test from inside
  the LAN passes.
- **It is retroactive.** Every host-wide rule ever written on this box
  was written under an assumption that has since changed underneath
  it. Age is not evidence of safety here; if anything it is the
  opposite, since older rules predate the change.
- **It generalizes.** The specific mistake is homelab's, but the
  *class* — "a rule scoped to the host rather than to an interface,
  justified by a belief about the network" — is repo-wide. §7.1.

### 2.2 Interface scoping is the control, and it is inconsistent

The fix pattern established by `nfs.nix`, `samba.nix`, `jellyfin.nix`,
`minecraft.nix` and `factorio.nix` is: `openFirewall = false`, then
`networking.firewall.interfaces.<iface>.allowedTCPPorts` naming
`tailscale0` and/or `wg0` explicitly. Everything that has been audited
so far has moved to it. What has *not* been audited is whether
anything else still uses the host-wide form. Known remaining host-wide
openings, as of writing:

- `modules/profiles/PC.nix:289` — `services.avahi.openFirewall = true`
- `modules/profiles/PC.nix:320` — Steam `remotePlay.openFirewall`
- `modules/services/copyparty-iso.nix:43` — port 3923
- `hosts/vps/configuration.nix:744-750` — 80/443/51820, which are
  *deliberately* public and are the one legitimate use of the form

The first three are P1 and P4's problem. The point for the threat
model is that the presence of a host-wide rule is not by itself a
finding — the question is always "public on *which* address, and is
that intended?"

---

## 3. Principals

Not "users" in the Unix sense — the distinct identities that can cause
something to happen on this fleet.

| Principal | Credential | Reaches | Bounded by |
|---|---|---|---|
| **admin (you)** | 3 keys in `flake.vars.publicSshKeys` — thinkpad's, torrent's, a FIDO2 YubiKey | interactive root on homelab/vps/isoimage | nothing; this is the top of the tree |
| **`lilijoy`** | local login on thinkpad/torrent | desktop session, `wheel`, `docker` (`PC.nix:313`) | see §4.3 — weakly |
| **`vps-deploy`** | key in `sops.secrets.homelab_vps_deploy_key`, held on homelab | vps, via a ForceCommand dispatcher | the dispatcher allowlist, `hosts/vps/configuration.nix:13-98` — see §4.2 |
| **zrepl peers** | per-host keys | root SSH on the peer, pinned to one `stdinserver` identity | ForceCommand + `restrict`, `modules/nixos/zrepl.nix:1073-1088` |
| **a tailnet device** | tailscale node key + tag | see §4.4 — everything | the tailnet ACL, which is flat |
| **`origin/master`** | GitHub push access | root on every host, unattended | **nothing** — see §4.1 |
| **the internet** | — | vps:80/443/51820, the DNAT'd game ports, homelab's public IPv6 | caddy/anubis/crowdsec, the raw-table rate limiter, and interface scoping |

---

## 4. Trust boundaries, and what crossing one buys

The useful question is not "is X reachable" but "if X falls, what
falls with it". This section is the reason severity ratings in the
Phase 1 reports should often be *higher* than a single-host reading
suggests.

### 4.1 `origin/master` → root on the entire fleet

The most important fact in this document.

- homelab runs `myAutoUpdate` (`hosts/homelab/configuration.nix:281`):
  on a timer, as root, it fetches `origin/master`, `git merge
  --ff-only`, builds, and runs `nixos-rebuild switch`
  (`modules/nixos/auto-update.nix:41-60`).
- torrent and thinkpad run `myPullDeploy` on the same pattern
  (`hosts/torrent/configuration.nix:15`,
  `hosts/thinkpad/configuration.nix:16`).
- homelab's successful switch then triggers `push-deploy-vps.service`
  (`hosts/homelab/configuration.nix:312`), which builds vps's closure
  and activates it there.

So a single commit pushed to `origin/master` becomes root on
homelab, torrent, and thinkpad on the next timer, and root on vps
immediately after homelab's switch. The guards in
`modules/flake/deploy-guards.nix` are *safety* guards — don't switch
on a dirty tree, don't switch off master, don't switch too often,
don't interrupt a protected unit. **None of them is an authenticity
check.** There is no commit-signature verification anywhere in the
deploy path.

Consequences the audits should reason from:

- The fleet's root authority is a GitHub account. Its 2FA posture, its
  recovery email, and any PAT or CI credential with push access are
  all in scope for this audit even though none of them is in this
  repo.
- Compromise of *either* laptop's SSH key gives push access, hence
  fleet root — including via the laptop that is the one that roams
  (§4.3).
- `fetch_and_merge_master` uses `StrictHostKeyChecking=accept-new`
  (`modules/flake/deploy-guards.nix:43`). TOFU on first contact means
  the very first fetch on a fresh host is unauthenticated. Low
  practical risk, real in principle; P7 should say which.

This is not necessarily *wrong* — a single-admin fleet that
auto-updates from its own repo is a reasonable design, and the
alternative (no unattended patching) has its own security cost. But it
must be a decision, not an accident, and it should be written down as
one. Currently it is nowhere in `docs/hardening.md`.

### 4.2 homelab → root on vps

`vps-deploy` is heavily constrained on paper: a ForceCommand
dispatcher with `restrict`, an allowlist of eight command shapes, and
a regex pinning the Nix store path to
`nixos-system-vps-*`. `docs/procedures/remote-access.md` describes the
allowlist as "the actual security boundary".

Read it as a *deploy* boundary rather than a *trust* boundary. Two
branches make that clear:

- `nix-store --serve --write` is dispatched unconditionally
  (`hosts/vps/configuration.nix:34-37`), with no store-path
  constraint. That is what lets the client write closures into vps's
  store — necessarily so, since that is the deploy mechanism.
- `switch-to-configuration switch` then runs as root, on any path
  matching the name pattern
  (`hosts/vps/configuration.nix:62-68`). The regex constrains the
  *name* of the store path, not its contents.

So whoever holds the vps-deploy key can push an arbitrary closure
named `nixos-system-vps-…` and activate it as root. That is the
intended function — homelab is vps's deployer, and a deployer is by
definition trusted with root on its target. The threat-model
conclusion is simply: **there is no meaningful security boundary
between homelab and vps.** Treat any homelab compromise as an
immediate vps compromise. The dispatcher's real value is narrower and
still worthwhile: it prevents an interactive shell, and it constrains
accidents and non-deploy misuse.

P2 should audit the dispatcher as *hostile input handling* on that
understanding — `$SSH_ORIGINAL_COMMAND` is attacker-controlled string
data, the `case` patterns are wildcarded on both sides, and
`store_path` is extracted by `grep -oE` from that same string. The
question is not "can it be bypassed to get root" (root is already
granted by design) but "can it be induced to do something outside the
deploy flow entirely".

### 4.3 `lilijoy` → root on thinkpad/torrent

Three distinct paths, all worth confirming:

1. ~~**`docker` group**~~ — **REFUTED by P1, 2026-08-26, and confirmed
   live.** `PC.nix:313` does list `"docker"` in `extraGroups`, but
   `users.groups.docker` is never declared anywhere in the repo, so the
   group does not exist and the membership is inert: `getent group
   docker` returns nothing on torrent. This was my error in the first
   draft — I read the grant without checking the group existed. It is
   dead config (a real needed/used finding, §7.4) but not a privilege
   path. Two *actual* root-adjacent grants sit in its place, and both
   are worse because neither is obvious from reading `PC.nix`'s group
   list:
   - **`input`** (`PC.nix:312`, present for plover). `/dev/input/event*`
     are `root:input 0660` with no logind `uaccess` ACL, so group
     membership is the entire grant — it is a raw keylogger for A7,
     capturing the run0/polkit password, the lock screen, and any
     password manager's master password. Confirmed live: `getent group
     input` → `lilijoy`. P1 rates this HIGH and it is the single best
     finding of that part.
   - **`libvirtd`**, which never appears in `PC.nix`'s own list at all
     — it arrives *transitively* via `PC.nix:18` →
     `modules/nixos/virtual-machines.nix:11`. Confirmed live: `getent
     group libvirtd` → `lilijoy`. A grant you cannot see by reading the
     file that appears to define the user's groups is exactly the kind
     of thing an audit exists to find.
2. **`wheel`** (`modules/profiles/PC.nix:310`), with run0/polkit as the
   elevation path. Expected for a single-admin desktop; noted for
   completeness. Note its interaction with `input` above: a keylogger
   that captures the polkit prompt turns this expected grant into an
   A7 escalation.
3. **root builds from a user-owned checkout.** This one is not
   obvious. `myPullDeploy` on both laptops points `flakeDir` at
   `/home/lilijoy/dotfiles` and reads
   `sshKeyPath = /home/lilijoy/.ssh/id_ed25519`
   (`hosts/torrent/configuration.nix:17,25`;
   `hosts/thinkpad/configuration.nix:18,26`) — a root service
   operating on a directory the unprivileged user can write. The
   guard script even works around the symptom, adding `safe.directory`
   to silence git's "dubious ownership" refusal
   (`modules/flake/deploy-guards.nix:24`) — which is git telling us
   exactly this. A git repository is not inert data: `.git/config` can
   specify hooks, `core.fsmonitor`, and other commands that git itself
   executes. P7 (mechanism) and P5 (host impact) should jointly
   confirm whether `lilijoy` can get root here, and whether the
   `origin` remote in that checkout can simply be repointed.

Path 3 chains: `lilijoy` → root on the laptop → the SSH key and the
admin key in `flake.vars.publicSshKeys` → §4.1 → the fleet.

### 4.4 Any tailnet device → nearly everything

The tailnet is the primary access control for this fleet. Most
services are exposed *only* on `tailscale0`, and the LAN and the
public internet are then correctly treated as untrusted. That design
is sound. What it means, though, is that the tailnet ACL is doing the
work that a firewall would otherwise do — so the ACL's own
permissiveness is the boundary.

The reference copy at `docs/tailscale-acl.json` is flat: every grant
is `"ip": ["*"]` from every tagged device and every `autogroup:member`
to every other device, including vps. There is no per-service
restriction anywhere in it. So a single compromised or
attacker-enrolled tailnet device reaches: SSH on every host, NFS
(2049), SMB (445), jellyfin (8096), the zrepl endpoints, and — via
homelab's `--advertise-routes=192.168.1.0/24` and
`--advertise-exit-node` (`hosts/homelab/configuration.nix:409-412`) —
the entire home LAN and an internet egress path.

Two specific things for the audits:

- **`vps` is trivially reachable from the tailnet** via
  `trustedInterfaces = [ "tailscale0" ]`
  (`hosts/vps/configuration.nix:341`), which bypasses the firewall
  entirely for that interface rather than opening specific ports. The
  edge host's hardening is a public-internet story; from the tailnet
  it has essentially none.
- **The ACL's `ssh` block is currently inert**, and this is subtle.
  `--ssh` is deliberately not enabled on any host
  (`modules/profiles/default.nix:81-93`, which documents *why* at
  length: it intercepts all SSH and bypasses ForceCommand, and it
  broke vps-deploy's allowlist when it was on). But the ACL file still
  carries `ssh` rules, including an `"action": "accept"` for
  device-to-device with `"users": ["…", "root"]`. Those rules do
  nothing today. They would become live, granting device-to-device
  root SSH that bypasses `PermitRootLogin = "forced-commands-only"`
  on thinkpad and torrent, the moment anyone enables `--ssh`
  anywhere. That is a loaded footgun in a file whose safety depends on
  a setting in a different file. P8 owns it; note also that the ACL is
  *not* applied by Nix — it is a reference copy of console state and
  may already have drifted.

So: is tailnet device authorization a sufficient boundary on its own?
That is the standing open question from `TODO.md`, and §8 keeps it
open. What can be said now is that it is currently the *only*
boundary for most services, and it is all-or-nothing.

### 4.5 A compromised backup source → the backup pool

Handled well already, and worth recording so it does not get
regressed. homelab **pulls** from torrent and thinkpad rather than
having them push (`hosts/homelab/configuration.nix:187-192`),
specifically because zrepl's receiving endpoint exposes
`DestroySnapshots` to whoever is authenticated — under push, a
compromised source could delete its own backup history. Pulling keeps
retention authority on homelab.

The remaining boundary is the ForceCommand pinning each key to exactly
one `stdinserver` identity, fixed server-side rather than asserted by
the client (`modules/nixos/zrepl.nix:1073-1088`). P6 should verify the
`restrict` keyword is actually doing what the comment claims against
the pinned nixpkgs and OpenSSH version, and work out what a
compromised *homelab* can do to the sources in the pull direction —
the inverse question, which the existing comment does not answer.

### 4.6 The internet → vps

The one boundary that is genuinely adversarial by default, and the
best-defended: caddy terminates TLS with security headers, anubis
puts a proof-of-work challenge in front of jellyfin, crowdsec watches
sshd and caddy logs and bans via an ipset bouncer, and a raw-table
PREROUTING chain applies per-source hashlimits *before* conntrack and
NAT (`hosts/vps/configuration.nix:393-460`).

Two structural gaps are already visible and are P2's to size:

- **The DNAT'd game ports are a hole straight through to homelab.**
  Traffic to 25565/19132/34197/34198 is forwarded to `10.100.0.2`
  over wg0 and never reaches userspace on vps, so caddy, anubis and
  crowdsec's log-based detection cannot see it at all. The raw-table
  hashlimit and the reused crowdsec ipset are the *only* controls, and
  they are volumetric — they rate-limit, they do not authenticate.
  Behind them sit two game servers parsing untrusted input from the
  open internet. Those servers' own hardening (P4) is therefore
  load-bearing for vps's boundary, not just for homelab's.
- **The v4/v6 asymmetry is deliberate but partial.** The IPv6
  rate-limit chain covers 80/443 only; the game ports are IPv4-only
  today and so are intentionally not mirrored
  (`hosts/vps/configuration.nix:439-448`). If the pending "IPv6 for
  forwarded game ports" item in `TODO.md` ever lands, it must bring
  the v6 rate-limiting with it or it silently ships a bypass.

### 4.7 The configuration itself is public

**This repository is public on GitHub.** Everything described in §2, §3
and §4 — the port map, the service inventory, the deploy mechanism, the
exact ForceCommand allowlist, the usernames, the tailnet structure, the
domain, every version pin — is readable by anyone, in full, at leisure,
including by an attacker who has not yet touched a single host.

Three consequences, each of which changes how findings should be rated
rather than merely adding a caveat:

- **There is no obscurity anywhere in this model, and none may be
  claimed.** An attacker studying vps's deploy dispatcher for a parsing
  flaw reads exactly the same source we do, with no rate limit and no
  detection. Any control whose value rests on an adversary not knowing
  it exists is worth zero here. In practice this means: never discount
  a weak control on the grounds that finding it would be hard, and
  treat "an attacker would have to know X" as satisfied by default in
  every reachability assessment.
- **The encrypted secrets are public ciphertext, permanently.**
  `secrets/secrets.yaml` is downloadable by anyone, and so is every one
  of its 72 historical revisions. sops/age encryption is therefore the
  *only* thing protecting it — there is no network boundary, no access
  control, and no rate limit in front of an offline attack. Two things
  follow. Key hygiene carries the entire weight, so the recipient set
  in `.sops.yaml` and the age keys behind it matter more here than they
  would in a private repo. And **rotation is not retroactive**: an
  attacker who archives the ciphertext today and obtains any host age
  key at any point in the future decrypts every secret that file ever
  held, including ones rotated long before. A host key compromise is
  therefore a *historical* breach of every secret that host could read,
  not merely a present one — which raises the stakes on the impermanence
  and host-key-handling questions elsewhere in this audit.
- **Pull requests are an inbound path to `origin/master`**, which §4.1
  establishes is fleet root. Anyone can open a PR against a public
  repo. Whether that is a real path depends on things not visible in
  the config: whether branch protection is enabled, whether any
  workflow runs automatically on an untrusted PR, and whether any such
  workflow holds a credential. None of that lives in this repo, so it
  cannot be settled by reading it — see open question §8.8.

**Already checked, and clean.** Because public history is permanent and
un-revocable, the obvious first question is whether anything was ever
committed in plaintext. It was not:

- All 72 historical revisions of `secrets/secrets.yaml` carry
  `ENC[AES256_GCM...]` markers — every revision, back to 2024, was
  sops-encrypted at commit time. There is no pre-sops plaintext era in
  this file's history.
- No credential-shaped filename (`*.pem`, `*.key`, `id_rsa`,
  `id_ed25519`, `.env`, `htpasswd`, `*.kdbx`, and similar) was ever
  added anywhere in history — the only matches on a name scan of all
  202 files ever added are `secrets/secrets.yaml` itself and two docs
  *about* secrets.
- A content scan of all 5,109 blobs in history for OpenSSH/PGP private
  keys, `tskey-` tailscale auth keys, GitHub `gh[pousr]_` tokens, AWS
  `AKIA` keys, Slack `xox*` tokens, Discord webhook URLs, Cloudflare
  tokens, WireGuard private keys and generic long password/token
  assignments produced exactly one match: `modules/services/octodns.nix`
  line 142, which is the string `env/CLOUDFLARE_TOKEN` — octodns's own
  environment-variable indirection placeholder, not a value.

So the public-history exposure is a property to manage going forward,
not an incident to clean up. That is a meaningfully better starting
position than most public infrastructure repos, and it is worth
preserving deliberately: the cost of a single plaintext commit here is
permanent, since deleting it from the branch does not remove it from
clones, forks, or GitHub's own dangling-object views.

---

---

## 5. Adversaries

Concrete positions to reason from. "Plausible?" is a judgement about
this specific fleet, not a general statement.

| # | Adversary | Position | Plausible? |
|---|---|---|---|
| A1 | Internet background noise | scanners, credential stuffers, botnets hitting vps:443 and the game ports | **constant, happening now** |
| A2 | Targeted internet attacker | picks homelab's public IPv6 or a game-server RCE | low volume, high impact |
| A3 | Malicious game-server client | authenticated-ish, speaks the protocol, reaches homelab through vps's DNAT | plausible; public game servers attract this |
| A4 | LAN-local | a guest device, an IoT thing, a compromised phone on the home network | plausible, and mostly unmodelled today |
| A5 | Rogue tailnet device | a stolen laptop, an over-broad auth key, an attacker-enrolled node | low, and the single highest-leverage compromise (§4.4) |
| A6 | Supply chain | a malicious nixpkgs/flake input, or push access to `origin/master`; on a **public** repo this also includes anyone opening a PR (§4.7) | low probability, total impact (§4.1) |
| A7 | Local unprivileged user | anything running as `lilijoy` — a browser exploit, a malicious npm/cargo dep, a bad AI-agent tool call | **the most likely initial foothold** (§4.3) |
| A8 | Physical | stolen thinkpad; no FDE today (`worktree-fde-secureboot-plan` is unmerged) | plausible for the laptop specifically |
| A9 | Ransomware / destructive | anything that reaches the backup pool with delete authority (§4.5) | the worst case for asset #1 |

Two notes on how to use this list. First, A7 and A5 deserve
disproportionate weight: A7 because a desktop that browses the web and
runs AI agents is the realistic entry point, and A5 because the
tailnet is where a foothold turns into everything. Second, A1 is the
adversary the current design defends against best, which is a reason
to spend the audit's attention elsewhere.

---

## 6. Severity rubric

Every Phase 1 finding gets exactly one of these. Rate by **reachable
impact**, not by how alarming the misconfiguration looks in isolation
— a scary-looking setting that only A6 can reach is not critical, and
a boring one that A7 can reach may be.

- **CRITICAL** — unauthenticated remote code execution or root, from
  A1/A2/A3; or anything that yields fleet-wide root; or destruction of
  the backups. Fix immediately, out of band from the audit's own
  schedule.
- **HIGH** — root or full data access for an adversary who has already
  achieved a *plausible* first step (A5, A7, a stolen laptop). Also:
  any secret exposed to a principal that should not hold it. Fix in
  the first remediation wave.
- **MEDIUM** — meaningful privilege or reach beyond what a principal
  needs, requiring a chain or a non-default condition. Includes
  violations of an existing `docs/hardening.md` rule with no currently
  demonstrable exploit — the rule exists because the class is real.
- **LOW** — defence-in-depth gaps, missing sandboxing on a
  low-value unit, logging and observability holes, unsafe defaults
  that nothing currently depends on.
- **INFO** — dead or unused config, over-broad grants with no
  demonstrated reach, documentation that no longer matches the config.
  Still report these; the needed/used axis lives here, and §7.4 is why
  it matters.

Two required qualifiers on every finding, because they change what
gets fixed first far more than the label does:

- **Reachability** — name the adversary from §5 and the path. "A7 via
  the docker socket" is a finding; "an attacker could…" is not.
- **Confidence** — CONFIRMED (lines read, behaviour verified against
  the pinned nixpkgs) or PLAUSIBLE (inferred, needs checking). Never
  round PLAUSIBLE up to CONFIRMED to make a point land harder; a
  consolidation pass that cannot trust the labels is worthless.

---

## 7. Recurring failure modes

Patterns this repo has already produced at least once. Each audit
should actively grep for its part's instance of these rather than wait
to notice one.

### 7.1 Host-wide rules justified by a belief about the network
§2.1. The belief was true when written and silently stopped being
true. Ask of every rule: public on *which* address, today?

### 7.2 Config that renders but never takes effect
`PasswordAuthentication = false` was set in `extraConfig` on both
homelab and vps and was **silently inert for the entire life of the
config** — the NixOS module renders its own default *before*
`extraConfig`, and sshd_config is first-directive-wins
(`hosts/homelab/configuration.nix:368-375`). Password auth was
actually enabled that whole time. Both are fixed, but the *mechanism*
is generic: a structured option and a raw text escape hatch can
collide, and the escape hatch usually loses.

Note that both hosts still carry several more directives in
`extraConfig` (`PermitRootLogin`, `AllowTcpForwarding`,
`X11Forwarding`, `AuthenticationMethods`, `PermitTunnel`, the
`ClientAlive*` pair). Each is subject to the identical trap. P3 and P5
must verify against the pinned nixpkgs which of these the module
already emits a default for, and therefore which are actually in
force — not assume they are fine because they are written down.
The same question applies to any other module with an `extraConfig`.

### 7.3 Ordering and lifetime assumptions
The caddy/anubis boot race (`hosts/vps/configuration.nix:480-487`):
anubis's group is transient under `DynamicUser = true`, so a boot
where caddy started first silently lost the group membership and every
request 502'd. Same family: the `zbackup` pool that nothing imported
for ~23h (`hosts/homelab/configuration.nix:174-183`), and the
`crowdsec-firewall-bouncer` ipset that had to be pre-created because
the bouncer runs after the firewall. Security controls have this
failure mode too — ask whether each one is *guaranteed* to be up
before the thing it protects, or merely usually up first.

### 7.4 Grants that outlive their reason
The needed/used axis, stated as a threat: config accretes, the
original need disappears, and the grant stays. An unused
`openFirewall`, a group membership no longer required, a secret no
longer read, a service enabled "just in case". These are attack
surface that nobody is thinking about, which is worse than attack
surface somebody is. `docker` on `lilijoy` next to a working podman
setup (§4.3) is the working hypothesis for this pattern; there will be
others.

### 7.5 Documentation asserting a boundary the config does not implement
`docs/procedures/remote-access.md` calls the vps-deploy allowlist "the
actual security boundary", which §4.2 shows is true for shells and
false for root. The ACL's inert `ssh` block (§4.4) is the same shape.
Both are honest descriptions of intent that a reader would
over-trust. When an audit finds one, the finding is the *gap*, and the
fix is usually a doc change rather than a config change.

### 7.6 Hardening that was applied once, to the host that prompted it
sshd, jellyfin, minecraft and factorio were fixed on homelab in
response to the IPv6 discovery. The same *class* of question was not
then asked of thinkpad, torrent, or the shared profiles. Reactive
fixes are naturally scoped to where the symptom appeared; this whole
audit exists because that scoping is not good enough.

---

## 8. Open questions

Deliberately unresolved here. Each needs either an audit finding or an
explicit decision from the user; none should be quietly settled by an
agent.

1. **Is tailnet device authorization a sufficient boundary on its
   own?** (§4.4.) The standing `TODO.md` question about whether
   homelab needs intrusion detection is really this question. Bears on
   P3 and P8. Sub-question: should the ACL be narrowed from `"ip":
   ["*"]` to per-service grants, or does that just add friction
   without changing the realistic outcome of a device compromise?
2. **Is unattended auto-update from an unsigned `origin/master`
   accepted?** (§4.1.) If yes, write it down as an accepted risk with
   its reasoning. If not, the fix is commit-signature verification in
   the deploy guards. Either way it belongs in `docs/hardening.md`.
   User decision.
3. **Should the homelab→vps relationship keep pretending to be a
   boundary?** (§4.2.) It is not one. Options: accept and document, or
   genuinely constrain it (signed closures, a narrower activation
   path). Documenting is probably right; the current wording is not.
4. **Can `lilijoy` reach root via the pull-deploy checkout?** (§4.3.)
   Purely factual — P5 and P7 should settle it. If yes, it is HIGH,
   because A7 is the most likely foothold.
5. **What is the LAN's actual trust level?** (A4.) The config
   consistently treats the LAN as untrusted, which is right, but
   homelab advertises `192.168.1.0/24` into the tailnet, so the two
   are more joined than the firewall rules suggest. Nothing currently
   states an intended posture.
6. **Does the isoimage's unauthenticated `A = [ "*" ]` on `/` have a
   written justification?** (`copyparty-iso.nix:34-43`.) Plausibly
   correct for recovery media, where the point is unimpeded access to
   a broken box — but it is currently implicit, and recovery media
   gets booted on strange networks. P4.
8. **What protects `origin/master` on a public repo?** (§4.7, §4.1.)
   Branch protection, required reviews, and whether any GitHub Actions
   workflow runs on an untrusted PR or holds a credential. None of this
   is visible from the repo contents, so it needs checking in the
   GitHub settings directly. Given §4.1, this is the access control on
   fleet root. P7 should flag what it cannot see; the answer is the
   user's to supply.
9. **Does the age-key set need rotating on a schedule?** (§4.7.) Since
   the ciphertext is public and permanent, a key compromise is
   retroactive across all history. That argues for treating age keys as
   higher-value than they would be in a private repo, and possibly for
   re-keying secrets that predate any host reinstall. P8, plus a user
   decision on appetite.

10. **Physical loss of the thinkpad.** (A8.) No FDE today; the plan
   exists on an unmerged branch. Out of scope for remediation, but the
   threat model should not pretend the risk is absent, and it changes
   how §4.1 reads — the laptop holds a key that is fleet root.

---

## 9. Non-goals

Stated so no audit wastes effort on them, and so their absence is a
recorded decision rather than an oversight.

- **Nation-state or targeted-APT resistance.** Not the threat model
  for a personal homelab.
- **Multi-user separation.** These are single-admin personal machines.
  Root login where allowed is intentional
  (`docs/procedures/remote-access.md`), not a gap to close.
- **Tailscale's own infrastructure.** Treated as trusted. If the
  coordination server is hostile, §4.4 falls entirely, and there is no
  mitigation within this repo's reach.
- **DigitalOcean's hypervisor**, likewise, for vps.
- **Denial of service as a primary concern.** Rate limiting exists to
  keep the game servers usable and to blunt A1, not to survive a
  determined flood. Availability is asset #6 for a reason.
- **The secrets' plaintext contents.** Agents never decrypt
  `secrets/*` (`docs/procedures/secrets.md`). The audit covers the
  *plumbing* — recipients, file modes, ownership, which principal can
  read which path — not the values.

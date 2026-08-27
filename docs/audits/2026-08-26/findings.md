# Consolidated findings

Phase 2 of the 2026-08-26 fleet-wide security audit. Nine part reports
(P0–P8, ~13,700 lines, **158 findings**) consolidated here into ranked
clusters.

This file covers **CRITICAL, HIGH and MEDIUM**. The 86 LOW and INFO
findings — plus the complete needed/used rollup — are consolidated
separately in [`findings-tail.md`](findings-tail.md).

**How to read this.** Findings are grouped by *root cause*, not by
part, because the most important result of this audit is that a handful
of causes account for most of the severity. Each cluster cites every
contributing finding id so anything can be traced back. Severity is per
the threat model's [§6 rubric](00-threat-model.md), rated on reachable
impact and naming an adversary from §5.

**Three clusters were promoted above their parts' individual ratings.**
Where that happened it is stated explicitly with the reasoning, because
a promotion that hides its logic is just an assertion.

Input counts: 3 CRITICAL, 31 HIGH, 38 MEDIUM, 51 LOW, 35 INFO.

---

## 0. Act on these now

Not scheduled remediation. These are live and already-exposed.

### N1 — A live fleet private key is sitting in `/tmp` on torrent
`F-P7-02`, with `F-P5-12`

`/tmp/homelab_zrepl_key`, mode 0600, dated 2026-08-23. Fingerprint
verified to match `vars.zreplPullerKey`
(`modules/flake/vars.nix:14`) exactly — the live private half of
homelab's zrepl pull key, which holds forced-command root SSH on
torrent and thinkpad.

`/tmp` is not a separate mount on torrent, so it sits on
`zroot/local/root`, which `myZrepl` snapshots **every five minutes** and
replicates to `zbackup`, from which restic pushes to Backblaze. **40
snapshots** currently contain it. Deleting the file does not retract it.

**Do:** rotate the keypair, update `vars.zreplPullerKey` and the
`homelab_zrepl_key` secret, redeploy both source hosts so the old public
half stops being authorised, then decide what to do about the snapshot
copies. Manual, per `docs/procedures/secrets.md`.

### N2 — Ten live credentials are decryptable from public git history
`F-P8-02` — see cluster C1 below for the full analysis

Rotate the *values* at each provider: Backblaze, Cloudflare, tailscale,
both WireGuard keypairs and the PSK, the Discord webhook, and the
vps-deploy and zrepl keypairs. Re-keying `.sops.yaml` alone accomplishes
nothing — the old ciphertext is already public and permanent.

### N3 — A world-readable age identity on the daily driver
`F-P8-03`, `F-P5-02`

`/home/lilijoy/.config/sops/age/keys.txt` is mode **0644**, parent dirs
0755, dated June 2025. Verified live. Given C1 it very likely decrypts
the entire secrets file, including all 72 public revisions. `chmod 600`
is immediate and free; whether it has already been read is
unknowable, which is why N2 is not optional.

---

## 1. CRITICAL

### C1 — The secrets architecture is one flat, permanent, public failure domain
**CRITICAL** · CONFIRMED · systemic
`F-P8-01` `F-P8-02` `F-P6-01` `F-P3-01` `F-P2-01` `F-P1-02` `F-P0-08`
`F-P8-05` `F-P8-03` `F-P5-02` `F-P7-08` `F-P8-11` `F-P8-16` `F-P8-14`

**Five of eight parts arrived here independently.** That convergence is
itself the finding: this is not a local mistake but the shape of the
whole secrets design.

The mechanism has four layers, each individually defensible and
catastrophic in combination:

1. **One rule, every recipient.** `.sops.yaml` has a single
   `creation_rules` entry naming all seven age recipients, so every host
   decrypts all 31 secrets. vps needs 7 and can read 31. Root on the one
   internet-facing box is root on the fleet's entire secret store.
2. **The ciphertext is public and permanent** (§4.7). All 72 revisions
   of `secrets/secrets.yaml` are world-downloadable, forever, with no
   rate limit in front of an offline attack.
3. **Therefore rotation is not retroactive.** An age key obtained at any
   point in the future decrypts everything the file ever held.
4. **The keys are not well kept.** homelab's age key *is* its SSH host
   key and exists in plaintext in four places including inside the
   offsite Backblaze repo (`F-P3-01`); an age identity sits at mode 0644
   on the daily driver (`F-P8-03`); `bootstrap-host.sh` generates host
   keys into `mktemp -d` → `/tmp`, i.e. onto the dataset snapshotted
   every five minutes and replicated offsite, and its failure path
   *deliberately preserves* them (`F-P7-08`); and **five of the seven
   current recipients cannot be attributed to any live host key**
   (`F-P8-05`).

**This is not theoretical — it has already happened.** `F-P8-02`
establishes by ciphertext comparison alone (no decryption) that
`secrets.yaml` has had **14 distinct recipients across 72 revisions,
only 7 current**. The 2026-08-25 vps reinstall churned three host keys
through `.sops.yaml` in one day, each state committed and pushed
publicly. Each of those three retired keys was a recipient of a public
revision containing the **byte-identical, currently-live** ciphertext
for at least: `homelab_vps_deploy_key` (root on vps),
`homelab_zrepl_key` (root SSH to both laptops),
`homelab_backblaze_restic_password` (the offsite backups),
`cloudflare_octodns_token` (DNS, hence certificate issuance), both
WireGuard private keys, the PSK, two tailscale auth keys, and the
Discord webhook.

The reinstall rotated the recipient three times and rotated **one value
out of thirty-one**. The droplet was bricked and destroyed, which is
precisely the circumstance where a host key's disposal is least certain.

**Remediation, in order:**
1. Rotate the *values* at each provider (N2). Nothing else helps
   retroactively.
2. Restructure `.sops.yaml` into per-path `creation_rules` so each host
   holds only what it consumes. This is the only change that bounds
   future exposure.
3. Attribute or retire the five unattributable recipients.
4. `chmod 600` the age identity; stop generating keys on snapshotted
   filesystems; move `bootstrap-host.sh`'s workdir to a tmpfs and make
   the failure path scrub rather than preserve.
5. Drop the nine declared-but-unconsumed secrets (`F-P8-11`) — dead
   credentials in permanent ciphertext are pure liability.

All of this is manual per `docs/procedures/secrets.md`.

### C2 — The desktop user is already fleet root, with no escalation required
**CRITICAL** — *promoted from HIGH* · CONFIRMED · systemic
`F-P5-01` `F-P8-04` `F-P7-01` `F-P0-03` `F-P5-03` `F-P1-01` `F-P8-09`
`F-P1-05` `F-P5-11` `F-P1-07`

**Why promoted:** every contributing finding was rated HIGH on its own.
But the rubric makes anything yielding fleet-wide root CRITICAL, the
threat model rates A7 (code running as `lilijoy` — a browser exploit, a
malicious dependency, a bad agent tool call) the *most likely* initial
foothold in the fleet, and the paths below require no exploit at all.
Most-likely adversary plus total impact plus zero difficulty is not a
HIGH.

Four independent paths, each sufficient alone:

- **No escalation needed whatsoever.** `~/.ssh/id_ed25519` on torrent is
  **byte-identical** to the third entry in `flake.vars.publicSshKeys` —
  root's authorized key on homelab, vps and isoimage — *and* it pushes
  to `origin/master`, which cluster H1 shows is unattended fleet root.
  It has **no passphrase**, proven by `pull-deploy.service` completing a
  non-interactive `git fetch` on 2026-08-25. Reading one file is the
  entire attack (`F-P5-01`, `F-P8-04`). `SSH_AUTH_SOCK` points at an
  unexpanded literal `/home/<user>/.bitwarden-ssh-agent.sock`, so the
  agent was never in the path and on-disk keys are what actually get
  used (`F-P1-07`).
- **Root via the pull-deploy checkout**, confirmed with four mechanisms
  (`F-P7-01`, `F-P5-03`, closing `F-P0-03`). The simplest needs no trick:
  `git merge --ff-only` is a **silent no-op exiting 0** when HEAD is
  ahead, so committing locally on `master` gets root to build and boot
  it. `core.hooksPath` is *already* set in the live `.git/config` to a
  user-writable directory. `operation = "boot"` is not a mitigation —
  `switch-to-configuration-ng` installs the bootloader for
  `Action::Boot`. And `deploy-guards.nix:24`'s `safe.directory` line
  removes the only protection git was offering, proved both directions.
- **Keylogging.** `lilijoy` is in `input`; `/dev/input/event*` are
  `root:input 0660` with no logind `uaccess` ACL, so membership is the
  entire grant. It captures the run0/polkit password, the lock screen,
  and any password manager's master password (`F-P1-01`, `F-P8-09`).
  `hardware.uinput.enable` is the narrower primitive plover actually
  needs.
- **`libvirtd`**, passwordless and root-equivalent, which never appears
  in `PC.nix`'s group list at all — it arrives transitively via
  `PC.nix:18` → `virtual-machines.nix:11` (`F-P1-05`).

Note the earlier threat-model claim that `docker` group membership was a
path is **refuted** — the group is never declared, so it is inert. That
was my error; it is dead config, not a privilege path (`F-P5-13`,
`F-P1-13`).

### C3 — No copy of the fleet's data is out of reach of a single root
**CRITICAL** — *promoted from HIGH* · CONFIRMED · systemic
`F-P3-03` `F-P6-02` `F-P6-04` `F-P6-07` `F-P6-12` `F-P3-08` `F-P6-15`

**Why promoted:** the rubric lists destruction of the backups as
CRITICAL, and the threat model rates the backup pools asset #1 — the
thing whose loss turns every other incident permanent.

Live `zdata`, the `zbackup` pool and the offsite Backblaze copy all
answer to the same uid 0 on the same machine. There is no `zfs allow`
delegation, no `readonly`, no Object Lock, no append-only credential,
and no offline medium anywhere in the fleet. `zbackup` is always
imported. Worse, the config *actively shortens* the escape window:
restic's `ExecStartPre` sets B2 `daysFromHidingToDeleting=1`, cutting
offsite version history to 24 hours, while `--keep-daily 2` prunes every
run. The offsite window is roughly two runs (~14 days).

The detector is on the machine it would have to detect
(`F-P6-07`), and `myHealthAlerts` runs on homelab too. Restore paths
remain unexercised (`F-P6-15`), so "we have backups" is formally
unverified.

Additionally, the pull direction hands homelab destroy-and-read
authority over both laptops with no server-side keep rules
(`F-P6-04`): `Sender.DestroySnapshots` evaluates none, and
`config.SourceJob` has no `Pruning` field, so a compromised homelab
destroys every snapshot on both laptops including the unregenerable
`@blank`.

**Highest-value single change:** an append-only Backblaze application
key plus Object Lock. `zfs hold` on `@blank` is a cheap, genuine local
immutability win (zrepl only releases `zrepl_*`-tagged holds).

---

## 2. HIGH

### H1 — `origin/master` is unattended fleet root, and it auto-merges
**HIGH** · CONFIRMED · systemic
`F-P0-01` `F-P7-07` `F-P7-11` `F-P7-09` `F-P7-17` `F-P0-07` `F-P3-05`
`F-P7-04`

homelab's `myAutoUpdate` and both laptops' `myPullDeploy` fetch
`origin/master` as root on a timer and switch; homelab's success then
triggers push-deploy to vps. One commit is root on all four hosts within
a cycle. The `deploy-guards.nix` checks are *safety* guards — clean
tree, right branch, min interval, protected units — and **not one is an
authenticity check**. No signature verification exists anywhere.

Aggravating factors found in Phase 1:
- **`flake-update-test` auto-merges upstream input updates to
  `origin/master` on build success alone** (`F-P7-07`). Build success is
  not a security property.
- The laptops' unattended deploys authenticate with the *interactive
  user's* push-capable GitHub key (`F-P7-11`) — the same key as C2.
- **Every guard fails open as success** (`F-P7-09`): skips are
  indistinguishable from deploys and nothing notices. Combined with
  `myHealthAlerts` not being enabled on either laptop at all, **nothing
  in the fleet would report a failed or skipped deploy.**
- homelab **re-TOFUs GitHub and vps on every boot** (`F-P7-04`,
  `F-P3-05`, `F-P0-07`) because `/root` is not persisted and
  `programs.ssh.knownHosts` pins the laptops but not `github.com` or
  `vps` — over plaintext DNS with DNSSEC and DoT off.

Good news, verified: **there is no CI and never has been** (`F-P7-17`) —
a full-history scan across all branches found zero workflow files, so no
`pull_request` trigger and no CI-held credential exist. Branch
protection is console state only the user can check.

### H2 — `health-check` holds write access to every raw block device
**HIGH** · CONFIRMED · systemic · **one-line fix**
`F-P3-02` `F-P2-05` `F-P7-05`

Three parts found this independently on two hosts. The `health-check`
user permanently holds the `disk` group. `/dev/sd*` is `root:disk 0660`
— read **and write** on every raw block device, i.e. root-equivalent,
and a direct read of homelab's age key (C1). On vps it additionally
holds `CAP_SYS_RAWIO` with both consuming checks (`checkSmart`,
`checkZfs`) disabled.

The module comment claims "read access". The grant is on the *user*, not
the unit, so it applies to everything that user ever runs.

**Fix:** `serviceConfig.SupplementaryGroups` instead of
`users.users.*.extraGroups`, scoped to the one unit that needs it. This
is the cheapest high-value fix in the entire audit.

### H3 — Docker publishes past the firewall, and the containers are unconfined
**HIGH** · CONFIRMED · systemic
`F-P4-02` `F-P4-05` `F-P4-03` `F-P3-04` `F-P4-07`

All four game ports are published as bare `-p` mappings. Docker DNATs
these in the `nat` table and delivers via `FORWARD`, never traversing
`nixos-fw` in `INPUT`, and homelab sets `filterForward = false`. **The
eight interface-scoped rules in `minecraft.nix` and `factorio.nix` —
which this audit's own plan called the reference standard — constrain
nothing.** Confirmed live: the `DOCKER` DNAT rules carry no `-i` match.

Bounded by live verification: there are **no IPv6 DNAT rules**, and
homelab has no public IPv4, so present exposure is **LAN-wide (A4), not
internet-wide**. But the only thing keeping four internet-adjacent game
servers off homelab's three routable IPv6 addresses is docker's IPv6
default, and nothing records that dependency —
`userland-proxy = false` sits unremarked in exactly the block someone
would add `"ipv6" = true` to (`F-P3-04`). That is §7.1 verbatim.

Compounding: a compromised game container reaches the LAN, the whole
tailnet and vps (`F-P4-05`), and both game servers **auto-install
unpinned third-party code on every start** — minecraft runs an untagged
`:latest` image and re-resolves 16 unpinned Modrinth mods with
`MODRINTH_ALLOWED_VERSION_TYPE = "alpha"`, into a JVM whose `/tmp`
tmpfs is deliberately `exec` (`F-P4-03`). `docs/hardening.md` has no
container rules at all (`F-P4-07`).

Per P2's handoff: **vps contributes no security control on this path.**
The raw-table hashlimit is volumetric, its thresholds are public and
sit one to two orders of magnitude above a real client, and for the
three UDP ports both it and the CrowdSec ipset are bypassable outright
by source spoofing (`F-P2-06`). The game servers' own hardening *is* the
boundary.

### H4 — Host-wide firewall openings on routable IPv6 addresses
**HIGH** · CONFIRMED · systemic
`F-P5-06` `F-P1-04` `F-P1-06` `F-P0-06` `F-P5-08` `F-P2-12`

The mistake that triggered this audit is **not homelab-only**. torrent
holds a routable IPv6 GUA with a v6 default route (confirmed live), and
`PC.nix` opens **106 ports host-wide** on both desktops: Steam remote
play, avahi, and KDE Connect's 1714–1764 TCP+UDP, which has no upstream
`openFirewall` toggle and is opened by hand. P5 proved without root that
the *running* filter accepts them via `ip46tables` with no `-i`, with
`kdeconnectd` bound `*:1716`. Port 22 is the only interface-qualified
rule on that host — proof the mechanism works and simply was not
applied.

Probed from vps: **currently filtered inbound by the ISP CPE** (sanity
check against Cloudflare v6:443 passed). So this is not live internet
exposure today — but the CPE is a *coincidence, not a control*:
unversioned, unmanaged, invisible to `nixos-rebuild`, and it changes
with a firmware update or router swap. **For thinkpad it provides
nothing at all** — a roaming laptop on a conference network has no such
filter, and the same 106 ports travel with it.

Also here: `useRoutingFeatures = "both"` fleet-wide against the repo's
own written rule, with only vps overriding it — IP forwarding enabled
on two machines that never route. Note the mechanical trap P1 found:
tailscale sets the sysctls at **`mkOverride 97`**, so a plain
`boot.kernel.sysctl` fix loses silently; only `mkForce` or changing the
option works.

### H5 — Two claimed trust boundaries do not exist, and one runs backwards
**HIGH** · CONFIRMED
`F-P7-03` `F-P0-02` `F-P2-10` `F-P8-13`

- **vps → root on homelab.** `check_min_switch_interval` in
  `deploy-guards.nix:61` does bash arithmetic on a value fed by
  `ssh vps stat -c %Y` — **arithmetic injection**, so a compromised vps
  executes code as root on homelab (`F-P7-03`). This *reverses* the one
  direction the threat model treated as a boundary and makes the
  relationship symmetric.
- **homelab → root on vps** is by design (`F-P0-02`, confirmed by
  `F-P2-10`). P2 established the dispatcher itself is sound — no
  injection, no `set -eu` gap, cannot yield a shell, `restrict`
  verified against OpenSSH 10.4p1. Root arrives instead via the run0
  shim under a polkit `manage-units` grant covering
  `StartTransientUnit`, i.e. "run anything as root" (`F-P8-13`).
  `docs/procedures/remote-access.md` calling the allowlist "the actual
  security boundary" is wrong, and "necessarily coarse" understates the
  polkit grant.

### H6 — The recovery ISO serves the whole filesystem to anyone
**HIGH** · CONFIRMED
`F-P4-01` `F-P5-10`

copyparty's rendered config has an **empty `[accounts]` block** with
`A: *` on volume `/`. Read from copyparty 1.20.20's source, `A` expands
to `rgwmda.` — anonymous read, write, move, delete, admin over the
entire filesystem, on a host-wide port 3923. The module's sandbox is
nullified by the `/` volume forcing `BindPaths=["/var/lib/copyparty",
"/"]`; only Unix DAC limits it. The ISO also bakes in the fleet admin
keys and is auto-built into a user-writable directory (`F-P5-10`).

Plausibly deliberate for recovery media — but it is booted on arbitrary
networks, and threat-model open question §8.6 asked for an explicit
written justification. There is none. Answer the question either way.

### H7 — No disk encryption, and unencrypted swap on hosts that decrypt secrets
**HIGH** (thinkpad) / MEDIUM (torrent) · CONFIRMED
`F-P5-04` `F-P5-05` `F-P3-06`

Neither laptop has FDE. thinkpad is portable, holds a fleet-root SSH key
(C2) and an age identity (C1), and **hibernates the whole of RAM into an
unencrypted 16 GiB swap partition**. homelab has an 8 GiB unencrypted
disk swap while decrypting live secrets, against the repo's own
`docs/hardening.md` rule preferring zram for exactly this reason
(`F-P3-06`) — a rule already applied to vps and not to homelab.

Against C1's retroactive property, physical loss of the thinkpad is not
"someone reads my files": it is the fleet's entire secret history.

### H8 — homelab is not gated by tailscale, and nothing would notice
**HIGH** · CONFIRMED
`F-P3-10` `F-P6-03`

Answers the standing `TODO.md` question with a **no**. `wg0` opens
8096/25565/19132/34197/34198 and vps DNATs the game ports straight from
the open internet, so A1/A3 reach code on homelab with **no device
authorization anywhere in the path**; docker adds LAN-wide reach on top.
Nothing on the host would see it: no CrowdSec, no fail2ban, and
`logRefusedConnections` is false where vps sets it true.

Also here: a compromised source host can plausibly steer homelab's
`zfs recv` through stream properties (`F-P6-03`, PLAUSIBLE) — `mkRecv`
sets only `placeholder.encryption`, zrepl passes no `-x`/`-o`/`-u`, and
`send_properties` is decided solely by the sender. Cheap fix:
`recv.properties.override`.

P3's judgement, which I endorse: conventional log-based IDS is a poor
fit here (sshd is tailnet-only; the game servers log in formats CrowdSec
has no parsers for). The effort is better spent on a `DOCKER-USER`
lockdown, ACL narrowing, and keeping the game images current. **The
decision remains the user's.**

### H9 — A published login password, live status unknown on thinkpad
**HIGH** (thinkpad) / INFO (torrent) · PLAUSIBLE · `F-P1-03`

`modules/profiles/PC.nix:306` sets `initialPassword = "123456"` on
`lilijoy`. On a public repo this is not a weak password, it is a
*published* one — §4.7 removes any discoverability argument.

P5 settled torrent: `passwd -S lilijoy` shows last change 2025-10-25,
after the 2024-12-07 install, so it is **not live there**. thinkpad is
confirmed offline (`tailscale ping` times out) and could not be
checked. If it is unchanged there, A7 registers its own polkit agent,
supplies the password it read on GitHub, and is root — then fleet root
via C2.

**This is the one outstanding verification the audit owes.** One
command when thinkpad is next up: `passwd -S lilijoy`. Regardless of
the answer, `initialPassword` should not carry a real-looking secret in
a public repo; `hashedPasswordFile` or an unset initial password with
console enrolment is the fix.

### H10 — A loaded footgun in the tailnet ACL, disarmed only by a setting elsewhere
**LOW today, HIGH the moment it is armed** · CONFIRMED
`F-P0-05` `F-P8-12`

`docs/tailscale-acl.json` carries an `ssh` block including
`"action": "accept"` for device-to-device with `"users": [..., "root"]`.
It does nothing today, because `--ssh` is not enabled anywhere —
verified three independent ways, including `tailscale status --json`
showing `sshHostKeys: null` for every peer, which also rules out an
imperative `tailscale set --ssh` the config would not reveal.

The problem is the dependency: a safety property held up by a setting
in a *different file*, with the dangerous configuration already written
and waiting. Enabling `--ssh` anywhere would immediately grant
device-to-device **root** SSH that bypasses real sshd's ForceCommand
handling — and two of the four tags in that rule are exactly the hosts
whose entire root-login policy is `forced-commands-only`. Tailscale SSH
already broke vps-deploy's allowlist once, confirmed live, which is why
`modules/profiles/default.nix:81-93` documents the prohibition at
length.

**Fix:** delete the `ssh` block from the ACL and the console. Nothing
uses it. If it is kept, it needs a comment naming
`modules/profiles/default.nix` as the thing keeping it inert.

---

## 3. MEDIUM

Grouped tersely; full detail in the part reports.

- **Tailnet ACL is flat and unenforced** — `F-P0-04` `F-P8-06`
  `F-P8-07` `F-P2-07` `F-P3-09`. Every grant is `"ip": ["*"]`. Blast
  radius is bounded by per-interface rules on three hosts but
  **unbounded on vps**, where `trustedInterfaces = ["tailscale0"]`
  leaves no packet filter at all — so the highest-value fix is in
  `hosts/vps/configuration.nix`, not the ACL. The ACL is a security
  control with no version control and no enforcement, and **drift is
  live**: an untagged Android phone (`Pixel 6a`) is a tailnet member
  covered by `autogroup:member` in all four grants and appears nowhere
  in the repo. homelab's subnet route + exit node turn any device
  compromise into the whole home LAN plus egress.
- **sshd misses much of the repo's own SSH baseline** — `F-P5-07`
  `F-P2-09` `F-P3-18` `F-P6-10`. Neither laptop uses `extraConfig` at
  all, so TCP forwarding is *enabled* on both. On homelab, seven of nine
  directives are in force and two (`PermitRootLogin`, `X11Forwarding`)
  are provably inert but happen to duplicate safe values. **Correction
  to the repo's own docs:** `docs/hardening.md` states
  `AllowTcpForwarding` defaults to `no`; it defaults to **`yes`**
  (verified against pinned OpenSSH 10.4p1). P5 re-checked the doc's
  other in-scope default claims — the tailscale `mkOverride 97` and
  `allowSFTP` claims are both correct.
- **The vps packet filter can fail open** — `F-P2-02`. `firewall-start`
  is `bash -e` and two unguarded `ipset create -exist` calls sit before
  the `INPUT` jump; a parameter drift in the bouncer's set takes the
  whole filter down and exposes sshd, which relies on the filter alone
  to stay off the public IP.
- **CrowdSec can be poisoned by anyone** — `F-P2-03` `F-P2-04`.
  `logRefusedConnections` + `maxretry = 1` + `checkReversePath =
  "loose"` means one spoofed SYN puts an arbitrary IP on the blocklist
  for up to 90 days. That ipset also fronts the DNAT'd game ports, so a
  remote attacker can blackhole Let's Encrypt's validators or individual
  players. fail2ban's unban deletes *all* CrowdSec decisions for an IP,
  including CrowdSec's own.
- **NFS authenticates nothing** — `F-P4-06` `F-P6-05`. `sec=sys`, so
  reaching `tailscale0:2049` *is* the authorization, with no second
  factor unlike samba and jellyfin. Client mounts carry no `nosuid`,
  `nodev` or `noexec`. Only two hosts mount it, so a per-service ACL
  grant is cheap and is the available lever.
- **Sandboxing gaps on root-running units** — `F-P2-08` `F-P6-06`
  `F-P7-06`. `crowdsec-allowlist-tailnet`, `zfs-emergency-prune` and
  `push-deploy-vps` all fall short of the repo's own rule;
  `push-deploy-vps` takes only `NoNewPrivileges` despite doing no local
  activation, so the carve-out is being used where it does not apply.
- **Credentials leaving sops into weaker places** — `F-P4-04` (factorio
  token and game password land in a container-visible volume),
  `F-P8-16` (old ciphertext persists in `/nix/store` on every host),
  `F-P8-14` (21 of 22 declarations set no `restartUnits`, so rotation
  does not reach running services).
- **Over-broad device and filesystem grants** — `F-P8-08` (`via`/`vial`
  udev rules make every `/dev/hidraw*` **0666**), `F-P3-07`
  (`A /storage` recursively *replaces* the ACL on the whole tree).
- **The AI agent's permission surface is unmanaged** — `F-P8-10`.
  Unversioned, with no deny policy, running as `lilijoy` on the daily
  driver — which C2 shows is fleet root. Directly in the highest-
  probability attack path and previously unaudited.
- **Nine declared secrets nobody consumes** — `F-P8-11`. Published in
  permanent ciphertext for no benefit.
- **The secret scan guards the wrong gate** — `F-P7-18`. `.githooks`
  *does* scan at `pre-commit` (PEM blocks, age keys, `AKIA`/`xox`/
  `ghp_`, `sops:` presence), which is the *recoverable* gate;
  `pre-push`, the irreversible one on a public repo, scans nothing. The
  hooks only install via the devshell `shellHook`, so a fresh clone has
  none, and the patterns miss most of this fleet's actual inventory —
  tailscale `tskey-`, Discord webhooks, WireGuard keys, B2/restic,
  Cloudflare, and every GitHub token form but `ghp_`. Given C1, keeping
  the currently-clean history clean is worth more here than in most
  repos: move the scan to `pre-push` over `$range`, widen the patterns,
  and consider `gitleaks`.

---

## 4. Systemic patterns → proposed `docs/hardening.md` rules

The audit's durable output. Each is a class of mistake found more than
once, phrased as the doc phrases its rules.

1. **Recipient rotation is not value rotation.** On a public repo the
   ciphertext is permanent, so retiring an age recipient protects
   nothing already committed. Rotating a *key* requires rotating the
   *values* at each provider. (C1, `F-P8-02`)
2. **Give each host only the secrets it consumes.** Use per-path
   `creation_rules`; a single blanket rule makes every host a
   full-fleet decryption oracle. (C1)
3. **Never generate key material on a snapshotted or replicated
   filesystem.** `mktemp -d` is not safe on a host whose root dataset
   snapshots every five minutes. Use a tmpfs, and scrub on failure
   rather than preserving. (`F-P7-08`)
4. **Docker-published ports bypass the NixOS firewall entirely.** A `-p`
   mapping DNATs in the `nat` table and never reaches `nixos-fw`. Bind
   to a specific address, or add a `DOCKER-USER` allowlist — an
   interface-scoped `networking.firewall` rule does nothing. (H3)
5. **Scope every firewall rule to an interface.** Host-wide is only for
   deliberately public ports. A rule justified by a belief about the
   network is a rule that will silently become wrong. (H4, §7.1)
6. **Put privilege on the unit, not the user.** Use
   `serviceConfig.SupplementaryGroups`, not
   `users.users.*.extraGroups` — a user-level grant applies to
   everything that user ever runs. (H2)
7. **Never point a root service at a user-writable path.** A git
   repository is executable configuration; `safe.directory` suppresses
   the warning that exists to tell you this. (C2)
8. **Keep one backup copy outside the authority of any single root.**
   Append-only credentials, Object Lock, or offline media — otherwise
   the backups share a failure domain with the thing they protect.
   (C3)
9. **Verify that `extraConfig` actually takes effect.** NixOS modules
   render their own defaults first and many config formats are
   first-directive-wins; check with the daemon's own dump (`sshd -T`)
   rather than assuming. (§7.2, `F-P3-18`)
10. **Correction:** `AllowTcpForwarding` defaults to **`yes`**, not
    `no`. The existing rule states this backwards.
11. **Container hardening has no rules at all yet** — capabilities,
    read-only rootfs, image pinning, and port publishing all need
    codifying. (`F-P4-07`)

---

## 5. Decisions required from the user

None of these should be made by an agent.

| # | Decision | Bears on |
|---|---|---|
| D1 | Rotate which credentials, and how far back? | C1 / N2 — the answer is probably "all ten in `F-P8-02`" |
| D2 | Accept unsigned unattended `origin/master`, or add signature verification? | H1; if accepting, it must be written into `docs/hardening.md` as an explicit accepted risk |
| D3 | Check GitHub branch protection — not visible from the repo | H1; with no CI, this is the only remaining control on fleet root |
| D4 | Buy immutability: append-only B2 key + Object Lock? | C3 — the single highest-value change for asset #1 |
| D5 | FDE on the laptops? The plan exists on an unmerged branch | H7 |
| D6 | Narrow the tailnet ACL, or accept all-or-nothing and document why? | §3 ACL cluster; either way, fix the vps `trustedInterfaces` half |
| D7 | Intrusion detection on homelab, or accept? | H8 — evidence says the boundary is not what was assumed |
| D8 | Is the recovery ISO's unauthenticated root-filesystem access intended? | H6 — needs a written justification either way |

---

## 6. Verified clean

Worth recording so it is not re-derived, and not regressed.

- **No plaintext secret was ever committed.** All 72 revisions of
  `secrets.yaml` are sops-encrypted with no pre-sops era; no
  credential-shaped filename appears among the 202 files ever added; a
  scan of all 5,109 history blobs found one match, which was octodns's
  `env/CLOUDFLARE_TOKEN` placeholder.
- **No CI has ever existed** — zero workflow files across all branches,
  so no `pull_request` path into fleet root and no CI-held credential.
- **No third-party substituter or trusted key on any host**;
  `require-sigs` and `sandbox` on everywhere; all 44 lock nodes pinned.
  `trusted-users` is `["root"]` everywhere except vps, by necessity.
- **`secrets.yaml` file modes and ownership are genuinely well done** —
  every over-broad grant is at the `.sops.yaml` layer, not the
  filesystem layer.
- **zrepl's forced-command identity pin holds.** Identity comes from
  which socket the daemon accepted on, never from the wire; `restrict`
  does what the comment claims in OpenSSH 10.4p1; the daemon-must-be-
  root half of the justification is correct (`mount` is undelegatable
  on Linux).
- **The vps deploy dispatcher is sound** — no injection, no `set -eu`
  gap, cannot yield a shell or a second key.
- **auditd + execve rule with `/var/log` correctly persisted** on both
  servers; homelab does **not** repeat vps's blanket `tailscale0` trust.
- **`--ssh` is genuinely disabled on every host**, confirmed three
  independent ways including `tailscale status --json` showing
  `sshHostKeys: null` for every peer.

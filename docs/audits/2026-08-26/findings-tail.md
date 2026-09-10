# Consolidated LOW / INFO findings — the tail

Phase 2 of the 2026-08-26 fleet-wide audit. Companion to the
CRITICAL/HIGH/MEDIUM consolidation, which is being done separately and
is **not** duplicated here.

---

## 1. Scope

This file covers **only** the LOW and INFO findings from
`P0-findings.md` and `P1`–`P8`. Every CRITICAL, HIGH and MEDIUM finding
is deliberately excluded; where one is load-bearing for a cluster it is
*referenced by id* and explicitly marked as belonging to the other
consolidation. **88 input findings** (53 rated LOW, 35 rated INFO — two
more LOW than the brief's count of 51, reconciled below) collapse into
**27 consolidated entries**: 12 systemic and 15 local, plus 7 promotion
candidates and a needed/used rollup of 60 rows. Every input id appears
at least once, and no id is the primary subject of more than one entry.

> **Count reconciliation.** Parsing `**Severity:**` across the nine
> files yields 53 LOW. The two beyond the brief's 51 are almost
> certainly **F-P0-06** — which `F-P1-06` re-rated to MEDIUM, so it now
> belongs to the MEDIUM consolidation and appears here only as a
> cross-reference — and one of the P0 LOWs a part report later
> superseded (`F-P0-02`→`F-P2-10`, `F-P0-05`→`F-P8-12`). Nothing is
> dropped either way: all three are cited below.

**Reading the labels.** `SYSTEMIC` means one class of mistake repeated
across hosts or parts; those carry a proposed `docs/hardening.md` rule
and matter more than their severity suggests. `LOCAL` means a single
defect in one place. Confidence is carried through from the
contributing findings, and where they disagree the entry says so rather
than rounding.

---

## 2. Systemic (LOW/INFO)

### SYS-01 — Config that renders but never takes effect (§7.2)

**Contributing:** F-P1-07, F-P1-13, F-P1-15 (partial), F-P3-12, F-P3-19,
F-P4-11, F-P4-13, F-P5-13, F-P7-12, F-P8-22(2).
**Confidence:** CONFIRMED throughout (F-P4-11's *window duration* is
PLAUSIBLE).

The failure mode the threat model names in §7.2 is the most common
defect in the tail — **ten independent instances across six parts**,
none of which any single part could see as a pattern. In each case the
config reads as policy and does nothing:

| Instance | File | What silently does not happen |
|---|---|---|
| `/srv` tmpfiles rule malformed (`0770 - root root -` puts `root` in the Age field) | `hosts/homelab/configuration.nix:80` | systemd rejects the line (`Invalid age 'root'`, exit 65); `/srv` is created implicitly at `0755`, so game-server data (RCON passwords, op lists) is world-readable to every local account (F-P3-12). **[Corrected 2026-08-28: the syntax was fixed to a working `0770 root:root` rule, which then broke jellyfin (uid 999, not root/group-root, has no traverse bit) — see `2026-08-28-fix-srv-permissions-stop-three-systems-fighting-ov.md`. Redesigned: `/srv` itself now stays at the distro default 0755 (it is a namespace, not a secret), confidentiality moved to the leaf directories (`/srv/factorio/main`, `/srv/minecraft/vanilla-plus` now 0700, co-located in `modules/services/{factorio,minecraft}.nix`), jellyfin's duplicate rules deleted so upstream's 0700 applies unweakened. Deployed and verified live. That plan's own F1: this closes only the *next* disclosure — the factorio credentials were already read out of world-traversable ZFS snapshots (`/nix/state/.zfs`, 0777) before the fix landed and remain disclosed until rotated at factorio.com.]** |
| `SSH_AUTH_SOCK = "/home/<user>/…"` — literal placeholder | `modules/profiles/PC.nix:165-166` | the Bitwarden SSH agent has **never** been in the path; every `ssh` falls through to the on-disk fleet-root key (F-P1-07, F-P8-22(2)) |
| `triggeredBy` used as a systemd attribute name | `modules/nixos/iso-autobuild.nix:69-74` | renders a phantom `pull-deploy.service.service`; the recovery ISO has never been rebuilt, and `/var/lib/iso-autobuild/result` is now a dangling symlink (F-P7-12) |
| `services.networkd-dispatcher` on a NetworkManager host | `hosts/homelab/configuration.nix:27-36` | can never fire (its only trigger is `org.freedesktop.network1`); the tailscale UDP-GRO tweak has never applied, and an unsandboxed root Python daemon idles forever (F-P3-19) |
| `docker` in `extraGroups` with `virtualisation.docker.enable = false` | `modules/profiles/PC.nix:313` | no group is created and no warning is emitted; a line that reads as a root-equivalent grant is inert (F-P1-13, F-P5-13) |
| `security.sudo.execWheelOnly` / package override under `enable = false`; `services.pulseaudio.support32Bit` under `enable = false` | `default.nix:60-65`, `PC.nix:293-294` | decoration that reads like policy (F-P1-15) |
| `factorio-new`'s floating `stable` tag | `modules/services/factorio.nix:149-159` | `pull` defaults to `"missing"` and `/var/lib/docker` is persisted, so the documented "picks up engine updates on restart" never happens (F-P4-13). **[Moot 2026-08-28: `factorio-new` was removed entirely (`7a047b7`, "declared unused") — the container, its volume, its persistence entry, its mod-mirroring preStart, and the DNAT/hashlimit/firewall rules for its port are all gone. The surviving server is just `factorio.<domain>` (`factorio-main`, tag `2.1.14`). No action needed; the finding no longer has a subject.]** |
| jellyfin's `KnownProxies` patch is `[ -f "$networkXml" ]`-guarded | `modules/services/jellyfin.nix:62-71` | on first boot the file does not exist, the patch no-ops, jellyfin then writes an empty `KnownProxies`, and the brute-force lockout is inert for one boot (F-P4-11) |

**Proposed rule.** *Verify effect, not presence. A NixOS option, a
`tmpfiles.d` line, a group membership or a systemd hook is only a
control once its rendered output has been read back — `sshd -T`,
`systemd-tmpfiles --dry-run`, `getent group`, the realised unit file.
This repo has produced ten instances of config that renders and does
nothing, two of which silently disabled a security control; treat "it is
written down" as evidence of intent only.*

---

### SYS-02 — sshd's baseline is inconsistent per host, and part of it is written where it cannot win

**Contributing:** F-P2-09, F-P3-18, F-P6-10, F-P3-15.
**Cross-reference (not absorbed):** **F-P5-07 is MEDIUM and belongs to
the other consolidation** — same subject on torrent/thinkpad, and where
the laptops' effective gap is rated.
**Confidence:** CONFIRMED throughout, verified against the realised
`sshd_config` / `sshd -T` in all three parts.

The parts disagree on *outcome*, and that disagreement is the finding:

- On **vps** (F-P2-09) and **homelab** (F-P3-18) the effective posture is
  correct. Exactly two `extraConfig` directives — `PermitRootLogin` and
  `X11Forwarding` — are inert, because the module emits its
  `settings`-derived block first and `sshd_config` is
  first-directive-wins. They happen to duplicate the module's values, so
  nothing is weaker than it looks. The hazard is prospective:
  `PermitRootLogin` is the one directive on vps deciding whether an
  interactive root shell exists, and it is sited in the one place that
  cannot change it — the identical shape of the `PasswordAuthentication`
  bug that triggered this audit, one directive over. Both files write it
  `PermitRootLogin = prohibit-password` with a stray `=` (parses fine; a
  tell that it was written in Nix syntax).
- On **torrent/thinkpad** (F-P6-10) the directives are simply *absent*:
  no `AuthenticationMethods publickey`, no `AllowAgentForwarding no`, no
  `AllowStreamLocalForwarding no`, no `PermitTunnel no`, no
  `ClientAlive*`, and the sftp subsystem shipped on hosts whose sshd
  exists solely to carry zrepl.
- **`docs/hardening.md` is wrong about an OpenSSH default.** It asserts
  "`AllowTcpForwarding` defaults to `no`". The pinned `sshd_config(5)`
  (OpenSSH 10.4p1) says `yes` **is** the default. Every host relying on
  that sentence has TCP forwarding on while believing it off. This is the
  highest-value line in the cluster and is a fleet-wide doc fix.
- **`allowSFTP = true` on homelab** (F-P3-15) violates the existing rule
  with no consumer found in the repo — zrepl uses `ssh+stdinserver`,
  push-deploy uses `nix-copy-closure`. Caveat that keeps it from being a
  clean cut: OpenSSH 9.0+ makes `scp` speak SFTP, so if the admin ever
  `scp`s to homelab this is load-bearing. A one-question decision.

**Proposed rule.** *Any sshd directive that has a
`services.openssh.settings.*` equivalent must be set there and never in
`extraConfig` — the module emits `settings` first and sshd_config is
first-directive-wins, so an `extraConfig` duplicate is silently inert.
Use `extraConfig` only for directives the module has no structured option
for, and prove the result with `sshd -T` against the realised config
rather than by reading the Nix. Apply the whole SSH baseline to every
host running sshd, including ones whose sshd exists for a single forced
command.*

---

### SYS-03 — Whole-interface trust grants instead of named ports (§7.1, §2.2)

**Contributing:** F-P1-11, F-P5-09, F-P2-12.
**Confidence:** CONFIRMED for every configuration; **PLAUSIBLE** for
exploitability (F-P5-09 says so explicitly) and for who can actually
reach vps's `ens4` (F-P2-12).

1. **`waydroid0` is a trusted interface on both laptops, and nothing in
   the repo asked for it.** `virtualisation.waydroid.enable`
   (`modules/profiles/PC.nix:102`) makes the upstream module append
   `waydroid0` to `networking.firewall.trustedInterfaces` (pinned
   `waydroid.nix:57`), which `firewall-iptables.nix:150` turns into a
   wholesale `nixos-fw-accept`. An Android app inside the container —
   precisely the untrusted context waydroid exists to host — reaches
   every wildcard-bound listener on the host: `sshd` on `0.0.0.0:22`,
   `rpcbind` on `0.0.0.0:111`, LLMNR on 5355, and anything a desktop app
   opens, bypassing the carefully interface-scoped rules at
   `hosts/torrent/configuration.nix:110`. `waydroid-container.service` is
   **active** on torrent; the bridge only materialises when a session
   starts, so the exposure is intermittent rather than constant. Nothing
   at `PC.nix:102` hints that a one-line `enable` disables the firewall
   for an interface.
2. **vps opens 80/443/51820 host-wide while its rate-limit chain is
   scoped `-i ens3`** (`hosts/vps/configuration.nix:744-751` vs
   `:409-410`, `:451-452`). Traffic arriving on the second private
   network `ens4` reaches caddy and WireGuard with no hashlimit and no
   CrowdSec ipset pre-drop. Nothing in the repo configures `ens4` —
   cloud-init does — so its addressing is invisible from the config,
   which is §7.1 exactly.

**Proposed rule.** *Never add an interface to
`networking.firewall.trustedInterfaces`; it bypasses the packet filter
wholesale rather than opening what is needed. Use
`networking.firewall.interfaces.<if>.allowed*Ports` instead, and audit
`trustedInterfaces`' **merged** value on every host after enabling any
upstream module — `virtualisation.waydroid` adds to it as a side effect
of `enable`. Scope every port opening to the interface it is meant for; a
host-wide `allowedTCPPorts` opens on addresses the config never
mentions.*

---

### SYS-04 — Allow/deny lists that do not enumerate every address a legitimate peer can present

**Contributing:** F-P4-14, F-P2-11.
**Confidence:** F-P4-14 CONFIRMED for the rendered config, PLAUSIBLE for
client behaviour; F-P2-11 CONFIRMED.

- **samba's `hosts allow=100.64.0.0/10` / `hosts deny=0.0.0.0/0` are
  IPv4-only in a dual-stack tailnet**
  (`modules/services/samba.nix:50-52`). `smbd` binds `[::]:445` and every
  tailnet node also holds an `fd7a:115c:a1e0::/48` address, so a peer
  arriving over IPv6 is *rejected*. It fails closed today — more
  restrictive than intended, not less — which also tells us the Android
  client is reaching homelab over IPv4 and will break silently if it ever
  prefers v6. The latent half is `hosts deny=0.0.0.0/0`, which does
  nothing and covers no IPv6: a future reader who relaxes `hosts allow`
  trusting the deny-all opens samba to every v6 source that can reach 445.
- **The WireGuard subnet `10.100.0.0/24` is in neither fail2ban's
  `ignoreip` nor CrowdSec's allowlist, and `wg0` is not trusted**
  (`hosts/vps/configuration.nix:341,345,631-648`). Any connection homelab
  makes to a closed port on the tunnel bans `10.100.0.2` on the first
  packet. Impact today is nil — vps opens nothing on wg0 and the DNAT'd
  game traffic returns through FORWARD, not INPUT — but it is the same
  self-ban class that already banned the admin's own IP live on
  2026-08-26 (`:610-617`), and it goes from nil to real the moment
  anything is opened on wg0.

**Proposed rule.** *Write every address literal in an allow/deny list for
both address families, or state in a comment which family the service is
deliberately restricted to. This fleet is dual-stack on the tailnet and
on the public edge; a v4-only literal fails closed today and fails open
the moment someone "simplifies" it. Exempt every cryptographically
authenticated peer subnet — the tailnet **and** `10.100.0.0/24` — from
every ban mechanism, since a self-ban is indistinguishable from an
outage.*

---

### SYS-05 — All DNS on the fleet is plaintext and unvalidated

**Contributing:** F-P1-10, F-P3-17, F-P5-16 (DNS half).
**Confidence:** CONFIRMED in all three parts — defaults read from the
pinned `resolved.nix:104-120`, merged values evaluated on vps, homelab
and torrent.

`networking.nameservers = [ "8.8.8.8" "1.1.1.1" ]` fleet-wide, plus
`insertNameservers` with the same pair on homelab, with
`services.resolved.enable = true` and neither `DNSOverTLS` nor `DNSSEC`
set — both default `false`. Every lookup not captured by a MagicDNS
routing domain leaves in cleartext, unauthenticated, spoofable by anyone
on the path: `github.com` on the deploy path, the Backblaze endpoint, the
Docker registry, LVFS, and ACME on vps. Pinning public resolvers usefully
avoids trusting a hostile network's DHCP, which is the right instinct —
but the queries then go out in plaintext UDP/53 to a well-known address
any network operator can transparently redirect or simply read. On
thinkpad this is a roaming property (A4 on café Wi-Fi); on homelab it is
the enabling half of the MEDIUM F-P3-05.

See **PROMO-01**: on its own this is defence-in-depth, but combined with
TOFU on the deploy path it is not.

**Proposed rule.** *Set `services.resolved.settings.Resolve.DNSOverTLS`
and `DNSSEC` in `modules/profiles/default.nix` — `"opportunistic"` and
`"allow-downgrade"` are the settings that do not break captive portals;
strict `true`/`true` only where the resolvers are pinned and the network
is known. Note the rename: the pinned tree marks
`services.resolved.dnssec` obsolete in favour of
`services.resolved.settings.Resolve.DNSSEC`. Neither setting is
build-visible — test on torrent before thinkpad.*

---

### SYS-06 — `rpcbind` and the NFSv3 helpers listen on every host that touches NFS, for mounts that are NFSv4-only

**Contributing:** F-P3-21, F-P5-17, F-P4-15 (bullet 3).
**Confidence:** CONFIRMED in all three, including live socket state on
torrent.

`services.rpcbind.enable` is `true` on homelab (pulled in by the NFS
server module, `nfsd.nix:145,163`) and on both laptops (pulled in by
`modules/nixos/nfs-homelab-mounts.nix:36-45`). It binds `0.0.0.0:111` and
`[::]:111`, TCP and UDP, and on homelab `rpc.mountd`/`statd`/`lockd` take
ephemeral ports. None of them is needed: homelab's export list is
NFSv4-shaped (`100.64.0.0/10`, `root_squash`) and both laptop mounts are
`fsType = "nfs4"`, which carries everything over 2049 with no portmapper.

They are unreachable off-host — 111 is in no `allowed*Ports` on any
interface — so this is surface area, not exposure. Two things keep it
worth recording: rpcbind is a classic UDP reflector with a long CVE
history, and per **SYS-03** the waydroid bridge reaches it on the laptops
regardless of the firewall.

**Proposed rule.** *Disable NFSv3 wherever only v4 is used —
`services.nfs.server.extraNfsdConfig = "vers3=n"` on the server and
`services.rpcbind.enable = lib.mkForce false` on v4-only clients — so
`rpcbind` and the v3 helpers stop binding at all. A listener that is only
saved by a firewall rule is still a listener, and this repo's inventory
is public.*

---

### SYS-07 — Root-running units this repo writes or overrides carry no sandboxing

**Contributing:** F-P6-09, F-P4-07, F-P4-10(3).
**Cross-reference:** F-P3-19's networkd-dispatcher is a fourth instance
(homed in SYS-01).
**Confidence:** CONFIRMED for every rendered unit; the container resource
limits are a CONFIRMED absence.

- **`zrepl.service`** (`modules/nixos/zrepl.nix:1067-1071`) is a
  long-running root daemon with the full ambient namespace: the rendered
  override contains `After`, `Wants`, `X-Restart-Triggers`, `Environment`,
  `Restart` and nothing else. No `NoNewPrivileges`, no `Protect*`, no
  `RestrictNamespaces`, no `PrivateTmp`. It genuinely needs `/dev/zfs` and
  root, so the full stack is unavailable — but a large useful subset is
  not. **F-P6-09 rates itself LOW only because of scope ambiguity about
  whether the rule covers repo-modified upstream units, and says
  explicitly that a reading that it does would make it MEDIUM.**
- **The three OCI containers** have no `--pids-limit`, no `--memory`, no
  `--cpus`, and no `userns-remap` (verified: daemon settings contain only
  `userland-proxy = false`), so container uid 0 is host uid 0 on the bind
  mounts and any container OOM is host OOM on the box holding `zbackup`.
  **[Partially closed 2026-08-27: `--memory=7g` and `--pids-limit` (512
  factorio / 1024 minecraft) are now set and deployed on both game
  containers, per D15 ("no container may exceed 50% of host memory").
  `--cpus` and `userns-remap` remain unset — the latter is item 4 in
  RESUME.md's agent-doable list, the former is undecided.]**
  The units are `docker run` wrappers with no sandboxing — inherent to
  `oci-containers` — which also means `factorio.nix:103-123`'s two
  secret-handling `preStart` scripts run as unsandboxed root. Credit where
  due: all three carry `--cap-drop=ALL` with justified add-backs,
  `no-new-privileges`, a `nosuid,nodev` tmpfs, and the default seccomp
  profile; minecraft adds `--read-only`. The gap is the resource and
  namespace dimension, not the capability one.
- **`octodns-sync` conforms to the letter of the rule and is the weaker of
  two examples in the same repo.** `samba-user-provision`
  (`samba.nix:105-134`) — a strictly less sensitive unit — additionally
  carries `ProtectClock`, `RestrictRealtime`, `RestrictSUIDSGID`,
  `LockPersonality`, `MemoryDenyWriteExecute`, `SystemCallArchitectures`.
  `PrivateDevices`, `ProtectProc`, `RestrictAddressFamilies` and
  `CapabilityBoundingSet = []` are all free for octodns.

**Proposed rule (two clauses).** *(a) The sandboxing baseline applies to
any unit this repo **writes or overrides**, including upstream units we
add a `systemd.services.<name>` block to — `zrepl.service` is the current
gap. Where a flag genuinely cannot be applied, record which one and why
in the unit's own block, so the exception is a decision rather than an
omission. (b) `docs/hardening.md` has no container rules at all. Add an
"OCI containers" section: publish to a specific address, never
`0.0.0.0`; pin images by digest, not tag; `--cap-drop=ALL` with justified
add-backs; `--read-only` or a written reason; `no-new-privileges`; and a
`--pids-limit` plus a `--memory` ceiling on anything parsing untrusted
input — the isolation lives in the container because the unit cannot
provide it.*

---

### SYS-08 — Latent footguns: the dangerous configuration is already written, kept inert only by a setting somewhere else

**Contributing:** F-P0-05, F-P8-12, F-P6-11, F-P7-15, F-P8-20, F-P1-13,
F-P6-13.
**Confidence:** CONFIRMED throughout, except F-P8-20's "no consumer
remains", which is PLAUSIBLE — the author could not prove that no closure
pulls `electron_39` without re-evaluating all five hosts against a
permit-free nixpkgs.

No part named this as a class, and it is the most useful cluster in the
tail. Six pieces of live, committed configuration do nothing today and
become dangerous on a one-token change made for an unrelated reason:

| Loaded gun | Trigger | Effect when it fires |
|---|---|---|
| `docs/tailscale-acl.json`'s `ssh` block — `"action": "accept"`, `src`/`dst` all four device tags, `"users": [… "root"]` | `--ssh` enabled on any host | device-to-device **root** SSH via Tailscale's proxy, bypassing `PermitRootLogin = "forced-commands-only"` on thinkpad and torrent and bypassing `authorized_keys` ForceCommand generally (F-P0-05, F-P8-12) |
| `myZrepl.defaultTransport` accepts `"tcp"` (`zrepl.nix:65-68,88-93`) | one enum value | the whole fleet's `zfs send` of every home directory in plaintext, authenticated only by a client-IP→identity map (F-P6-11) |
| `sshKeyPath`/`identityFile`/`webhookUrlFile` typed `types.path` (`pull-deploy.nix:79`, `push-deploy.nix:36`, `health-alerts.nix:18`) | removing two quote characters | Nix copies the **fleet-root private key** into `/nix/store`, world-readable, permanently, on every host that builds (F-P7-15) |
| `"docker"` in `extraGroups` (`PC.nix:313`) | `virtualisation.docker.enable = true` for any reason | root-equivalent on both laptops on the same commit, with no other change and no review prompt (F-P1-13) |
| `permittedInsecurePackages = [ "electron-39.8.10" ]` fleet-wide (`modules/flake/pkgs.nix:7-9`) | anything pulling `electron_39` again | an EOL Chromium admitted into any closure, servers included, with the build error that would have flagged it suppressed (F-P8-20) |
| zrepl's `sink` role (`zrepl.nix:878-946`) | setting the role | the only code path that writes a forced-command key accepting **incoming** replication — the exact topology `zrepl.nix:9-21` argues against at length (F-P6-11, F-P6-13) |

F-P8-12 verified `--ssh` is off three ways (evaluated `extraUpFlags` per
host; grep across the repo; live `tailscale status --json` reporting
`sshHostKeys: null` for every node) — so the property holds, and holds
only because of a setting in a different file.

**Proposed rule.** *Delete a loaded footgun rather than annotating it.
Where a dangerous configuration is inert only because of a setting
elsewhere — the ACL's `ssh` block, an unused zrepl transport, a group
whose backing service is disabled — remove it; an annotated footgun is
still loaded, and the annotation lives in a file nobody reads while
flipping the trigger. Where the option itself is the hazard, use the type
that makes the mistake a build error: `lib.types.externalPath`, never
`types.path`, for any option naming a file outside the store —
`types.path`'s check is `isStringLike`, so a real Nix path type-checks
and gets copied into the world-readable store.*

---

### SYS-09 — Hardening applied once, to the host that prompted it (§7.6)

**Contributing:** F-P2-19, F-P1-09, F-P1-12, F-P3-23, F-P3-24, F-P2-14.
**Cross-reference:** F-P6-10/F-P5-07 (sshd) is the same pattern, homed in
SYS-02; F-P0-06 / F-P1-06 / F-P5-08 (`useRoutingFeatures = "both"` fleet-wide,
overridden on exactly one host) is the same pattern and is **MEDIUM, in the
other consolidation** — F-P5-08 is P5's live confirmation that neither laptop
routes anything while both have `net.ipv{4,6}.conf.all.forwarding = 1`, and it
is cited here only so the id is traceable.
**Confidence:** CONFIRMED, except F-P1-12's *consequence* on vps, which is
PLAUSIBLE — the author could not read vps's `/etc/shadow`.

- **GRUB has no superuser on vps.** The shared profile sets
  `boot.loader.systemd-boot.editor = false` precisely so console access
  cannot become an edited kernel command line. vps `mkForce`s
  systemd-boot off and uses GRUB, where the equivalent is
  `boot.loader.grub.users` — unset, so anyone at the DigitalOcean console
  presses `e`, appends `init=/bin/sh`, and has root. Note the
  interaction: console-to-root on vps yields the host age key that
  decrypts the whole public ciphertext archive (F-P2-19).
- **auditd is server-only, and the desktops are the likely foothold.**
  `security.auditd` is `true` on homelab and vps, `false` on thinkpad and
  torrent — the hosts the threat model rates as the *most likely initial
  foothold* (A7), the hosts running a browser, four flatpak remotes and
  AI agents. Two smaller points about the servers' own rule: the single
  `-F arch=b64 -S execve` misses 32-bit `execve`, and there is no `-e 2`,
  so root can flush the ruleset without the configuration noticing
  (F-P1-09).
- **`profile-server` does not pin `users.mutableUsers`, and the two
  servers disagree** — `false` on homelab, `true` on vps. On the internet
  edge, the one host with a provider-supplied serial console, account and
  password state can be changed imperatively and is never reconciled by a
  deploy (F-P1-12).
- **`fwupd` and `smartd` were forced off on vps and left on homelab.**
  `services.fwupd.enable` in the shared profile drags
  `services.udisks2.enable = true` (pinned `fwupd.nix:200`) onto a
  headless server, plus a weekly outbound LVFS fetch (F-P3-23); `smartd`
  runs on homelab with `wall`/`x11`/`systembus-notify` sinks, all three of
  which discard everything on a headless box, duplicating the SMART poll
  `myHealthAlerts` already does and actually delivers (F-P3-24). vps
  recognised the pattern for `smartd` and not for `fwupd` (F-P2-14).

**Proposed rule.** *When a control is added in response to an incident,
put it in the shared profile that owns the host class — not in the host
file where the symptom appeared — or record per-host why it does not
apply. Reactive fixes are naturally scoped to where the symptom was, and
this repo has produced six asymmetries that way. When a host replaces a
mechanism the shared profile hardens (GRUB for systemd-boot), find and
set the replacement's equivalent control.*

---

### SYS-10 — Documentation asserting a boundary the config does not implement (§7.5)

**Contributing:** F-P0-02, F-P2-10, F-P8-13, F-P6-08, F-P4-08, F-P2-17,
F-P4-09, F-P8-23, F-P5-18, F-P6-14, F-P6-15.
**Confidence:** CONFIRMED throughout except F-P4-09 (PLAUSIBLE that
`--read-only` would now work) and F-P2-17 (PLAUSIBLE for the real cause
of the observed 502s).

**The homelab→vps boundary does not exist, and three separate grants say
so.** F-P0-02 identified it; **F-P2-10 confirms it with the mechanism
made explicit** — the dispatcher's privileged branches call
`/run/current-system/sw/bin/sudo`, which on a host with
`security.sudo.enable = false` is the run0 shim, which elevates through
`org.freedesktop.systemd1.manage-units`, which is exactly the polkit
action the repo grants `vps-deploy`. **F-P8-13 adds two more
root-equivalences** that neither the doc nor F-P0-02 lists:
`nix.settings.trusted-users = [ "vps-deploy" ]` (a Nix trusted user can
override `require-sigs` and `sandbox` per connection) and the polkit
`manage-units` grant itself. `remote-access.md` calls the ForceCommand
allowlist "the actual security boundary". It bounds shells and accidents
— **verified**, and worth keeping: `restrict` is in force, `/var/empty`
is mode 0555 and immutable so a second `authorized_keys` cannot be
installed, and there is no command injection and no `set -eu` gap. It
does not bound root. Six residual dispatcher observations to fold into
the doc rewrite: the store-path regex is bounded only incidentally (`/`
happens to be outside the character class); the most powerful branch
(`*"nix-store --serve --write"*`) is first, wildcarded on both sides, and
needs no store path; serve-write also exposes `BuildPaths`, a CPU/disk
exhaustion channel on a 1 vCPU droplet; `*"systemctl reboot"*` likewise
matches anywhere in the command string; branch order is otherwise
fail-safe; and `sudo` is the one runtime-resolved path in an otherwise
store-pinned script, so a deploy that changes the shim changes the
elevation semantics of the deploy installing it.

**A doc states a false technical constraint.** `docs/hardening.md` and
`docs/backups.md` both say zrepl's `ssh+stdinserver` *requires* the SSH
user to be root. Half true: the **daemon** must be root (`zfs-allow.8` —
`mount` cannot be delegated on Linux, and `destroy`, `snapshot`,
`receive`, `rollback` all require it), but the **SSH user** need not be.
`PreparePrivateSockpath` only requires the sockdir to be
non-world-accessible, so 0750 already passes; moving the stdinserver
sockets out from under `/run/zrepl` via
`global.serve.stdinserver.sockdir` would let both laptops set
`PermitRootLogin = "no"` (F-P6-08).

**Comments that are confidently, citably wrong.**
`hosts/vps/configuration.nix:391-395` says the SNAT rule preserves source
IPs; SNAT is what destroys them, and the consequence is real — all
internet players appear as `10.100.0.1` at the game servers, so no
per-source ban and no log attribution is possible anywhere in the stack
(F-P4-08). The caddy/anubis ordering comment blames a transient
`DynamicUser` group; against the pinned nixpkgs the module declares
`users.groups.anubis` statically, and the actual cause was almost
certainly the `RuntimeDirectory` socket not existing yet — the fix is
right, the model is wrong (F-P2-17). `factorio.nix:33-60` cites a live
crash as evidence for the `--read-only` exception, but that crash is
attributed to missing `DAC_OVERRIDE`, which `:56` now grants — the
conclusion is probably still right (`usermod` needs a writable `/etc`),
the argument for it is half stale, and it was never re-tested (F-P4-09).

**Smaller ones.** `tmux.nix`'s header claims fleet-wide use; only
`server.nix:56` imports it, so `lilijoy` gets the binary with no config —
and anyone "fixing" the comment by adding it to `PC.nix` would enable
`@continuum-restore 'on'`, which re-executes saved pane command lines
from a **user-writable** home (F-P8-23). The host called `torrent` runs no
torrent anything; the name is vestigial and load-bearing in six places,
and the useful fact is the opposite one — this is the interactive daily
driver and therefore *the* A7 surface (F-P5-18).
`tests/zrepl-replication.nix:100-102` says "production pins nothing
either", but production pins deliberately with a long comment; a reader
trusting the test could remove `programs.ssh.knownHosts` (F-P6-14). And
`docs/procedures/backup-restore.md` is honest that the restore paths have
never run — recorded because it reweights everything else: the fleet's
most valuable asset is a pool nobody has restored from, and nothing at
all exercises the Backblaze path (F-P6-15).

**Proposed rule.** *A comment or doc that states a security property must
name the mechanism that enforces it and be re-checked when that mechanism
changes. When an audit finds a doc describing a boundary the config does
not implement, the finding is the gap and the fix is usually the doc —
but write what the control **does** bound, not only what it does not, or
the next rewrite deletes a real property. Never cite a live failure as
evidence for a design decision without recording the date and re-testing
when the cited cause is fixed.*

---

### SYS-11 — Rotation does not reach the copies, and the copies outlive the credential

**Contributing:** F-P5-12, F-P8-16, F-P8-14.
**Cross-reference:** **F-P0-08 is MEDIUM and belongs to the other
consolidation**; it is the same principle applied to the public
ciphertext.
**Confidence:** CONFIRMED for all three configurations; F-P8-14's
per-service impact is PLAUSIBLE and is tabulated per-consumer in the
finding rather than claimed as a blanket.

1. **Into the backups.** Both laptops serve `zroot/local/home` and
   `zroot/local/root` to homelab's zrepl puller with no ZFS-native
   encryption, so `~/.ssh/id_ed25519` — the fleet-root key — lands on
   `zbackup` in plaintext with retention measured in months. Rotating the
   key removes it from the laptop, not from the snapshots. Bound worth
   recording: the offsite restic→Backblaze copy covers only
   `zroot/local/state` and `zdata/storage/storage`, **not** `zbackup`, so
   the laptop keys are not offsite (F-P5-12).
2. **Into the store.** `sops.defaultSopsFile` is a Nix *path literal*, so
   `secrets.yaml` is copied into `/nix/store` on every host, one path per
   revision, `0444`. Largely moot while the repo is public — which is
   *why* this is LOW — but it forecloses "make the repo private" as a fix
   for anything, since the store copies and every existing clone remain,
   and it becomes the live version of the problem the day the repo goes
   private (F-P8-16).
3. **Not into the running process.** 21 of 22 `sops.secrets` declarations
   set no `restartUnits`; only `homelab_samba_android_smb_password` does.
   The sharp edge is the wireguard trio, read once at `wg setconf`:
   rotate the key, rebuild, and the tunnel keeps running on the old
   material with nothing indicating a pending change.
   `docs/procedures/secrets.md` says consumers get the new value "at next
   rebuild/switch or next boot" — true of the *file*, easy to read as a
   claim about the *service* (F-P8-14). **[Closed for the wireguard trio
   and the factorio container secrets, 2026-08-28: `restartUnits` added
   (`61f55cb`, `3dd1aa4`) after this exact gap was hit live during
   rotation — both reported a clean activation while still using the old
   value, confirming the finding's prediction. `restartUnits` fires only
   on content change, so each already-rotated secret still needed one
   manual restart to pick up the fix; that is not a gap in the fix, it is
   the one-time cost of applying it after the fact. The other ~19
   declarations are unreviewed — this closes the two the audit actually
   named, not the general SYS-11 gap.]**

**Proposed rule.** *Set `restartUnits` on every secret whose consumer
caches it at start — the wireguard trio and the factorio container
secrets today — and leave it off only for per-invocation readers and for
the tailscale auth keys, where it is deliberate. Treat rotation as
reaching only future reads: a credential that has been replicated into
`zbackup`, copied into `/nix/store`, or published as ciphertext must be
**scoped and revoked at the relying party** (GitHub, the tailscale
console, `publicSshKeys`), because re-encrypting it does not retire the
copies.*

---

### SYS-12 — Unpinned upstreams fetched at build, update or start time by a root process

**Contributing:** F-P2-15, F-P8-15, F-P8-17, F-P1-16, F-P8-21.
**Cross-reference:** F-P4-13's floating Docker tag is the same class,
homed in SYS-01 because the interesting half is that it does *not* float.
**Confidence:** CONFIRMED for every mechanism; F-P8-15's exploitation
path and F-P8-21's trust judgements are explicitly PLAUSIBLE/judgement.

- **CrowdSec's detection ruleset is fetched at every service start** from
  `hub_branch = "master"` (`ExecStartPre` runs `cscli hub update` then
  installs three collections). The edge host's effective parsers and
  scenarios are whatever the hub served at boot, evaluated as `expr`
  inside the crowdsec process, and are not reproducible from this repo.
  Mitigating and real: `autoUpdateService` is off, and the pinned module
  sandboxes crowdsec thoroughly (`DynamicUser`, `CapabilityBoundingSet`
  reduced to `CAP_SYSLOG`, `ProtectSystem = "strict"`, a
  `SystemCallFilter`), so the blast radius is "bad or absent detection",
  not code execution as root. Worth knowing before anyone enrols: the
  effective `online_client` already has `sharing: true` and
  `pull.blocklists: true` with a null credentials path, so
  `cscli capi register` would start shipping alert metadata out and
  pulling a third party's entries into the same ipset the game ports
  consult (F-P2-15).
- **nixpkgs is referenced through the indirect flake registry.**
  `nixpkgs-stable.url = "nixpkgs/nixos-26.05"` and
  `nixpkgs-unstable.url = "nixpkgs/nixos-unstable"` — the only two inputs
  in `flake.nix` not written as explicit `github:` URLs. Locked, this is
  safe. The exposure is at *update* time: the shorthand resolves through
  the network-fetched registry inside homelab's `flake-update-test`,
  which runs `nix flake update` as root, on a timer, unattended, and
  merges the result to `origin/master` if it builds. The registry is an
  unauthenticated input to the fleet's root path, one indirection further
  out than F-P0-01 accounts for (F-P8-15).
- **Typos execute nixpkgs.** `__fish_command_not_found_handler` is
  `comma $argv[1]`, so every unrecognised command becomes a network fetch
  and execution of a nixpkgs package of that name; `ns` runs
  `nix shell 'nixpkgs/nixos-unstable#…' --impure`, deliberately outside
  the lock. Both are documented, deliberate ergonomic choices on an
  interactive desktop; they are listed because "what executes code the
  flake lock does not cover" is a question that needs an answer, and
  these are the two answers (F-P8-17).
- **The declarative flatpak list describes almost none of the machine.**
  Two applications declared, `uninstallUnmanaged = false`, ten-plus
  installed from four remotes including a `vish-repo` added system-wide
  and `flathub-beta` per-user — neither anywhere in the repo. Not a
  vulnerability; a statement that the config does not describe the
  machine, which matters because this whole audit is conducted by reading
  the config (F-P1-16).
- **Provenance inventory** (F-P8-21), recorded because the negatives are
  the valuable part: **nothing is unpinned** (all 44 lock nodes carry
  `rev` and `narHash`, no `path:` inputs, no `--impure` in the flake), and
  **the binary-cache posture is the strongest single property found in
  the tail** — every host resolves to
  `substituters: ["https://cache.nixos.org/"]`, one official
  `trusted-public-keys` entry, `trusted-substituters: []`,
  `require-sigs: true`, `sandbox: true`, with no cachix, attic or
  per-project `nixConfig` anywhere. Against that: five direct inputs are
  an individual's repository (`stylix`, `sops-nix`, `nvf`, `nix-flatpak`,
  `import-tree`) and two of those are load-bearing, since sops-nix runs
  at activation and decrypts every secret and import-tree discovers every
  module; three nixpkgs revisions enter transitively without a `follows`
  (`impermanence`'s is inert, but `plover-flake` actually *builds* from
  its own); NUR is in the tree via stylix; and `via` is a repackaged
  AppImage of an unfree binary whose upstream releases no source.

**Proposed rule.** *Reference every flake input by explicit URL
(`github:owner/repo/ref`), never by registry shorthand — the shorthand
resolves over the network at `nix flake update` time, inside a root timer
whose output becomes fleet root. Add `nix.settings.flake-registry = ""`
on the hosts that build unattended. No substituter other than
`cache.nixos.org` may be added without a recorded decision; that is
currently true by accident rather than by rule. Where an upstream must be
fetched at runtime and cannot be pinned (the CrowdSec hub), record it in
`docs/hardening.md` as an accepted risk and name the sandboxing that
bounds it.*

---

## 3. Local (LOW/INFO)

Most useful first.

### L-01 — caddy's admin API is reachable from anubis (F-P2-16)

**vps · CONFIRMED for the exposure, PLAUSIBLE for the chain.**
caddy's admin API listens on `127.0.0.1:2019` and cannot simply be
turned off because `services.caddy.enableReload = true` depends on it.
anubis — a Go HTTP service sitting *outermost* in the path of untrusted
internet traffic, by design — has
`RestrictAddressFamilies = [AF_UNIX AF_INET AF_INET6]` and no network
address restriction, so it can reach it. That API can replace caddy's
entire running configuration: arbitrary reverse-proxy targets, a
`file_server` rooted at `/var/lib/caddy` where the ACME account key and
certificates live, and MITM of jellyfin. Fix is `IPAddressDeny = "any"`
plus `IPAddressAllow = [ "10.100.0.2" ]` on the anubis unit (AF_UNIX is
unaffected by `IPAddress*`, so the socket keeps working) — BPF-based and
cgroup-wide, so it fails closed in ways easy to misdiagnose as an anubis
bug; needs a VM test with a real request through caddy, not a unit start.

**[Fixed 2026-09-01 (eighth session):** `hosts/vps/configuration.nix`
sets exactly that on `systemd.services.anubis-jellyfin.serviceConfig`.
Build-verified rendered unit shows `IPAddressDeny=any` /
`IPAddressAllow=10.100.0.2/32`. VM-tested rather than trusted on the
rendered directive alone (`tests/anubis-admin-egress.nix`,
`checks.anubis-admin-egress`): a probe shell migrated into the live
`anubis-jellyfin.service` cgroup cannot reach a real caddy admin API on
`127.0.0.1:2019`, the same cgroup **can** still reach the real backend
address, caddy still serves a real request through the unix socket end to
end, and clearing the restriction live (`systemctl set-property … 
IPAddressDeny= IPAddressAllow=`) makes the same probe succeed again —
proving the restriction, not something else, is what was blocking it.
**Not deployed** — build/VM-test only, per this session's scope.]**

### L-02 — the restic job mounts ZFS snapshots into the shared `/tmp` for up to a week (F-P3-13)

**homelab · CONFIRMED config, PLAUSIBLE exploitability.**
`backupPrepareCommand` does `mkdir -p /tmp/restic/$snap` then
`mount -t zfs` there, with `PrivateTmp = lib.mkForce false` (correctly —
a mount made in `ExecStartPre`'s namespace would not propagate
otherwise) and `TimeoutStartSec = "1w"` over roughly 2.9 TiB. Two
consequences: the whole persisted-state and media trees are enumerable
by any local account for days at a time, and `/tmp/restic` can be
pre-created by an unprivileged process before the timer fires — if
created as a symlink, root's `mkdir -p` and `mount` follow it, which is
"an unprivileged user chooses where root mounts a filesystem". The set
of processes that could do so looks empty today, but that is a property
of every *other* unit's config, not of this one. The fix is nearly free:
the unit **already has**
`RuntimeDirectory = "restic-backups-backblazeWeekly"`. Two robustness
nits to fix in the same change: `backupCleanupCommand` pipes *every*
snapshot on the system into `umount` (thousands, including everything
received into `zbackup`), and `backupPrepareCommand` picks the newest
snapshot with `tail -n 1` on a name sort, correct only while the
`zrepl_` timestamp prefix keeps sorting lexicographically.

**[Corrected 2026-09-01 (eighth session): the unit had `StateDirectory`,
not `RuntimeDirectory`, before this fix** — `StateDirectory` gives
`/var/lib/<name>` (persistent, already used for the `last-success`
marker) and was never going to help here; `RuntimeDirectory` gives
`/run/<name>`, created fresh and symlink-safe by systemd on every start,
which is what the fix actually needed. **Fixed** in
`hosts/homelab/configuration.nix`: added
`RuntimeDirectory = "restic-backups-backblazeWeekly"` with
`RuntimeDirectoryMode = "0700"` (closes the "enumerable by any local
account" half, not just the symlink-plant half), `backupPrepareCommand`
mounts under `$RUNTIME_DIRECTORY` and sorts by `-s creation` instead of
name, and `backupCleanupCommand` now unmounts only what is actually
mounted under `$RUNTIME_DIRECTORY` (read from `/proc/mounts`) instead of
piping every snapshot on the system into `umount`. Build-verified by
reading the rendered `…/bin/restic-backups-backblazeWeekly-pre-start` and
`-post-stop` scripts out of `nixos-rebuild build`'s `./result`, per this
audit's own "verify the fix, not the build" rule — not run live, since
exercising this needs a real multi-day restic run
(`2026-08-28-a-manual-deploy-kills-the-in-flight-weekly-restic-.md`
already deliberately defers that). **Not deployed.**]**

### L-03 — the recovery ISO is auto-built into a user-writable directory and bakes in the fleet admin keys (F-P5-10)

**torrent · CONFIRMED mechanism and artefact, PLAUSIBLE chain (needs a
human step).**
The ISO bakes in `flake.vars.publicSshKeys` as `isoimage`'s root
`authorizedKeys` and ships copyparty with unauthenticated `A = [ "*" ]`
on `/`, host-wide on 3923. It lands in `/home/lilijoy/Downloads`, is
never verified between build and boot, and its purpose is to be booted
as root on a broken machine. Because the flake is public and pinned, an
attacker can build a legitimate ISO from the same inputs and match the
filename pattern the cleanup `find` uses — there is no "they would not
know what to fake" here. The units themselves are **well built** (they
run as `lilijoy`, not root, with the full sandboxing stack, and the
module's comments explain honestly why a dedicated user was rejected);
this is about the artefact. Cheap and proportionate fix: have
`iso-copy-to-downloads` also write a `.sha256` from the store path
before the copy, and add a verify step to the Ventoy runbook. See
**PROMO-04**: the current artefact is dated 2026-08-16, ten days stale,
because of F-P7-12.

### L-04 — `~lilijoy/.ssh/authorized_keys` is honoured (F-P5-11)

**both laptops · CONFIRMED.**
`authorizedKeysInHomedir = true` puts `%h/.ssh/authorized_keys` in
`AuthorizedKeysFile`, inside a directory `lilijoy` owns. The
*declarative* key surface is minimal — `openssh.authorizedKeys.keys`
evaluates to `[]` and `/etc/ssh/authorized_keys.d/` on torrent contains
only `root` — and no home-directory key file exists there today. So A7
can create one and thereafter re-enter from any tailnet device,
surviving reboots, surviving `nixos-rebuild switch` (nothing manages the
file), and invisible to anyone reading the Nix config. Given `/` is
durable on these hosts (F-P5-04), it survives indefinitely. LOW because
A7 already has everything on the box — this is a persistence and
re-entry property, not new authority — and worth closing because it is
the cheapest kind of backdoor to plant and the hardest to notice. Costs
nothing: `authorizedKeysInHomedir = false`. Check thinkpad for the file
first; it is offline and unverified.

### L-05 — there is no CI, and the PR path into fleet root rests on settings only the user can see (F-P7-17)

**repo · CONFIRMED negative result; UNKNOWN branch protection.**
**The valuable half is the negative, so it is stated first:** there is no
CI in this repository and there never has been. `.github/` does not
exist; searching every file ever added on every branch in the full
history for `.github/`, `workflow`, `.gitlab-ci`, `.circleci`,
`azure-pipelines`, `Jenkinsfile`, `.woodpecker`, `.drone`, `.travis`,
`.builds/` and `garnix` returns zero matches, and the complete set of
root dotfiles ever added is `.envrc`, `.githooks/*`, `.gitignore`,
`.sops.yaml`. So the two worst PR-shaped paths **do not exist here**: no
workflow triggers on `pull_request` from a fork, and no CI holds a
credential. That posture should be preserved *deliberately* — the moment
any workflow is added it becomes an unauthenticated inbound path toward
a `master` that is fleet root, and `pull_request_target` would be
catastrophic. **F-P7-17's rating is explicitly conditional:** LOW as it
stands, HIGH if PRs can be merged without review. Five things the user
must check in the GitHub UI and record next to F-P0-01's decision:
(1) branch protection on `master`, including `enforce_admins`; (2) who
can merge; (3) auto-merge and Dependabot/Renovate automerge; (4) deploy
keys and write-scoped PATs, plus 2FA and recovery email; (5) whether the
repo needs to be public at all. One in-scope consequence: checking out a
PR locally is itself a hazard, because `core.hooksPath` points into the
worktree — mitigated by `require_clean_master` refusing to run off
`master`, so a checked-out PR branch is **not** auto-deployed.

### L-06 — `zfs-emergency-prune` is an unguarded "destroy all history" primitive (F-P6-12)

**both laptops · CONFIRMED.**
One `systemctl start` destroys every snapshot on
`zroot/local/{home,root}`. The module is honest about what it does and
the VM test covers it well; three residual sharp edges: it destroys
snapshots that have **not** been replicated, so a laptop offline for a
month loses that month — and thinkpad is exactly that host; on a dataset
with no `@blank` it destroys *everything*, which is documented and
VM-tested behaviour but is plausibly torrent's current state since its
impermanence migration is still open; and there is no `--dry-run`, no
confirmation and no journal record of the pre-state, so recovery from a
mistaken invocation depends entirely on `zbackup` being current. Add a
dry-run mode and log the snapshot list and count before destroying.

### L-07 — the tailscale auth key transits a world-readable `/proc` command line at enrollment (F-P1-08)

**PC hosts · CONFIRMED for the mechanism and for the absence of
`hidepid`.**
The secret file itself is correct (`0400`, uid 0, `/run/secrets`), but
the upstream `tailscaled-autoconnect` unit does
`tailscale up --auth-key "$(cat …)"`, putting the key in `argv`, and
`/proc` is mounted without `hidepid`. The window is genuinely small —
the script only reaches that branch when the backend state is
`NeedsLogin`/`NeedsMachineAuth`/`Stopped`, so a rebuild on an enrolled
host exits immediately. The realistic case is a fresh install or a
post-`logout` re-enroll on a machine that already has a persistent A7
implant, and the payoff is an A5 credential — the single
highest-leverage compromise in the model. Upstream's shape, so the
options are narrow: `hidepid=2` (wants a VM test — it has bitten logind
integration before), drop `authKeyFile` on the PC hosts and lose
declarative bootstrap, or accept and record that the window is
first-boot only.

### L-08 — `setuid` and `exec` are not disabled on the data or backup pools (F-P3-14)

**homelab · CONFIRMED.**
All three pools correctly set `devices = "off"`, which is what stops
device nodes inside a received root filesystem being usable. Neither
`setuid = "off"` nor `exec = "off"` is set anywhere, and
`/storage`/`/storage-bulk` resolve to `options = [ "defaults" ]` — no
`nosuid`, `nodev`, `noexec` — because they use `mountpoint = "legacy"`.
Not exploitable alone (an SMB or NFS client cannot create a setuid-*root*
binary without already being root; exports use `root_squash` and Samba
sets `invalid users = root`), but `zbackup` receives whole root
filesystems from both laptops, and a restore is exactly the moment
someone mounts one by hand under time pressure. Checked clean alongside
and worth recording so it is not re-litigated: zrepl transmits **no** ZFS
properties, so received datasets inherit `mountpoint=none`,
`canmount=off` and `devices=off` from `zbackup/backup/<host>` rather than
carrying the source's mountpoints across.

### L-09 — octodns holds a certificate-issuance credential and the zone declares no CAA (F-P4-10)

**homelab · CONFIRMED config, PLAUSIBLE impact — the Cloudflare token's
actual scope is inside sops and was not read.**
A Cloudflare DNS-edit token for `skyseekerlabs.net` is not merely a DNS
credential: it satisfies ACME DNS-01, and by repointing the apex A/AAAA
it satisfies HTTP-01 too — so whoever holds it can obtain a
publicly-trusted certificate for the apex and for `jellyfin.` from
essentially any CA and MITM the one internet-facing service that takes
user passwords. Nothing in the repo characterises it that way. **No CAA
record is declared, and this is not a "just add it in the console"
situation:** `octodns-sync --doit` runs hourly and makes Cloudflare match
the declared zone, so a hand-added CAA is deleted on the next tick. The
same argument applies to `v=spf1 -all` and DMARC `p=reject` on a domain
that sends no mail. Reachability is genuinely low — `octodns` is
`isSystemUser` with a `nologin` shell, no SSH keys, no group memberships
beyond its own, and one unit — so the finding is about what it holds,
not how easy it is to get. Get a CAA record wrong and certificate
*renewal* breaks silently weeks later; check caddy's configured issuer
first and include any fallback.

### L-10 — cloud-init keeps a root-code-execution channel from DigitalOcean open on every boot (F-P2-18)

**vps · CONFIRMED that the boothook executes; PLAUSIBLE for the
part-handler mechanism.**
Most of this configuration deserves credit and is unusually tight:
`datasource_list = [ "ConfigDrive" ]` uses the hypervisor-attached local
device rather than the `169.254.169.254` HTTP metadata service,
`cloud_init_modules` is cut to `[ "seed_random" ]`,
`cloud_config_modules` and `cloud_final_modules` are emptied outright,
and `preserve_hostname = true` stops DO renaming the host. What that
does not disable is vendor-data *boothooks*, handled by cloud-init's
part-handlers during the init stage independently of those module lists
— and the config explicitly carves `/var/lib/cloud` out of the root
tmpfs as its own exec-capable filesystem so they can run, because
without it the droplet never came up. The carve-out is well narrowed
(one path, `nosuid`, `nodev`, root-owned `0755`, 64 MB). The gap is only
that the *why* is documented and the *acceptance* is not: a reader of
`:224-233` learns that the exec tmpfs was needed for boot, not that it
constitutes a standing root channel from the provider. §9 treats the
hypervisor as trusted, which is why this is INFO; one paragraph in
`docs/hardening.md` closes it. The lever if it ever needs closing is
`vendor_data: { enabled: false }`, which per the existing comment breaks
DO's network arming.

### L-11 — `sync = "disabled"` on `zroot` and `zbackup` (F-P3-16)

**homelab · CONFIRMED.**
Not adversarial — power loss, kernel panic, or the USB link dropping.
ZFS stays internally consistent, but up to one transaction group (~5 s)
of *acknowledged* writes is lost on an unclean shutdown and applications
that fsync'd were lied to. Reasonable on `zdata` for a media library. On
`zroot` it means `/nix/state` — every persisted `/var/lib`, the tailscale
node state, the restic `last-success` marker — can silently roll back a
few seconds. On **`zbackup`** it applies to asset #1: a received snapshot
that ZFS acknowledged may not be there after a crash. Self-healing in
the common case, since zrepl's cursor would re-send, but it makes "the
backup completed" a weaker statement than it reads. Measure before
changing: with no SLOG on a USB-attached mirror the cost may be exactly
why it was set, and if so that is a fine answer — record it in
`docs/backups.md` next to the "two copies" wording.

### L-12 — `/boot` is mounted world-readable, and systemd-boot says so on every boot (F-P3-11)

**homelab · CONFIRMED.**
The ESP is declared with no `mountOptions`, so disko's default
`[ "defaults" ]` applies and lands verbatim in
`fileSystems."/boot".options`; vfat with defaults is
`fmask=0022,dmask=0022`, so everything under `/boot` is `0755`. This is
the exact `bootctl` warning in the 2026-08-26 reboot journal — the mount
backing `loader/random-seed` is world accessible, "which is a security
hole". Concretely: a local reader learns the systemd-boot random seed,
which is mixed into the kernel entropy pool at early boot. Genuinely
small, printed at you every boot, one line to fix
(`mountOptions = [ "umask=0077" ]`). **Needs-check:** the same disko
default plausibly applies to torrent's and thinkpad's ESPs; no part
audited that.

### L-13 — caddy appends to client-supplied `X-Forwarded-For` (F-P2-20)

**vps · PLAUSIBLE.**
The important half is right: `header_up X-Real-Ip {remote_host}`
*replaces*, so anubis always sees the true peer address regardless of
what the client sent. But `reverse_proxy` manages `X-Forwarded-For` by
appending the peer to any chain the client supplied, so a request
carrying `X-Forwarded-For: 1.2.3.4` is forwarded as
`1.2.3.4, <real client>`. CrowdSec is unaffected — it reads caddy's own
JSON access log, which records the true `request.remote_ip`; anubis is
unaffected — it is told to use `X-Real-Ip`. The exposure is to anything
further downstream that takes the leftmost entry, which means jellyfin's
own logging and known-proxy handling on homelab. One line:
`header_up X-Forwarded-For {remote_host}`.

### L-14 — the backup's correctness is asserted rather than tested (F-P6-14, F-P6-15)

**CONFIRMED.**
`tests/zrepl-replication.nix` is better than most: it asserts the forced
command is present with the right identity, that `restrict` is present,
and that the key cannot get a shell (bounded with `timeout` and `-n`,
which is the right way to test a command that blocks on stdin). What it
does not cover: the **identity pin is never negatively tested** — there
is one identity, so "cannot claim to be a different host", the
load-bearing claim at `zrepl.nix:1073-1076` and threat model §4.5, is
asserted by the comment and not by the test (the pin does hold; nothing
would catch a regression); the **`local` transport is untested** and it
is the path homelab uses for its own data, i.e. the majority of the
fleet's bytes, including the `1x15m(keep=all)` bucket `docs/backups.md`
says was tuned on it; and there is **no hostile-source case**. Alongside
that, **no restore has ever been performed** — full dataset restore and
disaster-recovery-from-scratch have never run, and nothing at all
exercises the Backblaze path, which is the copy F-P6-02 calls the last
line of defence. If only one drill happens, make it a single-file
`restic-backblazeWeekly restore` from the offsite repo; restore
alongside (`-restored`), never over.

---

### L-15 — what health-alerts hands to Discord is a standing, undocumented outbound data flow (F-P7-14)

**homelab and vps · CONFIRMED.**
The credential handling is **good** and should be kept: the webhook URL
is passed via `curl -K <file>` rather than argv (the module documents
exactly why), the file is a sops secret owned by `health-check` on both
hosts, and `jq --arg` correctly JSON-escapes every interpolated body, so
none of the message construction is injectable. What leaves the fleet
per alert is the finding: the hostname; `zpool status -x` output (pool
names, vdev device paths, error counters, resilver state); the device
paths of any SMART-failing drive; ZFS dataset paths and snapshot ages
from `backupStaleness`, which on homelab spells out the full backup
topology including both laptops' dataset names; marker-file paths; and
`systemctl --failed --no-legend --plain`, which is unit names **and
their descriptions** — e.g. "Build locally and push+activate vps on
vps-deploy@vps", naming the deploy user and the target. No secret
values, no journal text. So: no credential leak, but a periodic,
indefinitely retained, plaintext-at-rest inventory of the fleet's hosts,
storage layout and service topology inside a third-party consumer chat
service. For a personal homelab that is probably an acceptable trade —
it is currently an undocumented one. Cheap mitigation if the doc line is
judged insufficient: send unit *names* only
(`systemctl --failed --no-legend --plain | awk '{print $1}'`), dropping
the descriptions, which are the most revealing part.

---

## 4. Promotion candidates

Combinations materially worse than their parts. **Nothing is re-rated
here** — each is flagged with reasoning for the user's decision.

### PROMO-01 — plaintext DNS + TOFU on first fetch + unsigned unattended deploy

**Parts:** F-P0-07 (LOW), F-P1-10 / F-P3-17 / F-P5-16 (LOW).
**In the chain but yours:** F-P3-05 (MEDIUM), F-P7-04 (HIGH), F-P0-01
(HIGH).

`fetch_and_merge_master` uses `StrictHostKeyChecking=accept-new`, and
`github.com` is resolved through cleartext, unvalidated DNS.
Individually each is a narrow window. Together they are a complete
A2/A4 path: an on-path attacker who can forge one DNS answer at the
moment a host with an empty root `known_hosts` fetches becomes
`origin/master` for that host — which per F-P0-01 is root on it, and via
the deploy chain root on the fleet. **The reason to promote rather than
note:** F-P3-05 and F-P7-04 establish that homelab's `/root` is not
persisted, so this is not a once-per-lifetime first-boot window — it is
**every boot**, on the host that then activates vps. That converts
F-P0-07's "narrow by construction" into "recurring", and makes the DNS
findings the enabling half of a HIGH rather than a defence-in-depth nit.
**Suggested handling:** fix them as one change (a declarative
`programs.ssh.knownHosts` pin for GitHub in the shared profile, plus
`DNSOverTLS`), and rate the *combination* with F-P7-04 rather than
carrying the DNS findings separately at LOW.

### PROMO-02 — waydroid's trusted interface + a plantable `authorized_keys` + rpcbind on `0.0.0.0`

**Parts:** F-P1-11 / F-P5-09 (LOW), F-P5-11 (LOW), F-P5-17 (INFO).

Each part is defence-in-depth. Composed, they are an end-to-end
persistence path with a plausible entry point: an "install this APK"
attack lands in the Android container, which the firewall trusts
wholesale, which reaches `sshd` on `0.0.0.0:22` — and F-P5-11 says
`~lilijoy/.ssh/authorized_keys` is honoured, Nix-invisible, and durable
across reboots and switches. So a container escape or a credential
obtained inside waydroid converts into a permanent, tailnet-reachable
shell as `lilijoy` (hence `wheel`, hence `libvirtd`) that no
`nixos-rebuild` removes and no Nix file records. rpcbind is the third
listener the same grant exposes. **Suggested handling:** treat
`authorizedKeysInHomedir = false` and
`trustedInterfaces = lib.mkForce [ "lo" ]` as one change, and rate that
change against the composed path, not against either part.

### PROMO-03 — `/srv` never got its 0770 + containers run as host root on the bind mounts + restic exposes the snapshot trees

**Parts:** F-P3-12 (LOW), F-P4-07 (LOW), F-P3-13 (LOW).

The intended traversal barrier on `/srv` has never existed, so
`/srv/minecraft/vanilla-plus`, `/srv/factorio/{main,new}` and
`/srv/jellyfin/*` sit at `0755` — and game-server data directories
routinely hold RCON passwords, whitelists and op lists. The containers
have no `userns-remap`, so container uid 0 is host uid 0 on exactly
those bind mounts. And for up to a week at a time the restic job mounts
the whole persisted-state and media trees under a world-traversable
`/tmp`. The composed statement is concrete: **any local account on
homelab can read the game servers' credentials, and for part of every
week, most of the fleet's data.** The mitigating fact each part relies on
— "there is no unsandboxed non-root process on this host today" — is a
property of other units' configs, not of these, and homelab runs
`jellyfin`, `octodns`, `health-check`, `android-smb` and `nobody`.
**Suggested handling:** fix F-P3-12 first (one line, five value fields),
then re-check the per-service directory modes, which are the real
control.

**[Corrected 2026-08-28: the first leg is fixed, not as originally
suggested.** `factorio-new` no longer exists (`7a047b7`) — only
`/srv/factorio/main`, `/srv/minecraft/vanilla-plus` and `/srv/jellyfin/*`
remain. The one-line fix suggested here (`0770` on `/srv`) was tried and
reverted live because it denies every one of `/srv`'s three non-root,
non-root-group service users the traverse bit they need — see
`2026-08-28-fix-srv-permissions-stop-three-systems-fighting-ov.md`. The
actual fix moved confidentiality to the leaves instead: `/srv` stays at
the distro default 0755, the two game-server directories are now 0700,
and jellyfin's own duplicate tmpfiles rules were deleted so upstream's
0700 applies. **`userns-remap` is still open; the restic mount leg is
fixed** — see L-02's 2026-09-01 closure note: it no longer mounts under
`/tmp` at all (moved to a 0700 `RuntimeDirectory`), so this promotion's
third leg is closed and only the second (`userns-remap`) remains.
~~**Read that plan's F1 before treating any of this as closed**: the
factorio credentials were already disclosed through world-traversable ZFS
snapshots before the leaf-mode fix landed, and a permission change cannot
retract a snapshot already taken — only rotation at factorio.com does
that, and it is still pending (rotation runbook item 9's neighbor,
F-P4-04).]**~~ **Retracted 2026-09-01**: rotation runbook item 12 (not
9 — corrected reference) did this rotation 2026-08-28, at factorio.com
and in sops. The disclosed value is dead; nothing pending here.

### PROMO-04 — the only outward alerting channel is unreliable in exactly the way that hides a silent failure

**Parts:** F-P7-13 (LOW), F-P2-21 (INFO), F-P7-10 (LOW), F-P7-12 (LOW),
F-P5-10 (LOW).

`notify()` writes the cooldown stamp *before* the `curl` that posts, so a
failed delivery is lost **and** suppressed for six hours as though it had
succeeded — and `curl`'s non-zero exit under the inherited `set -e`
aborts the rest of the run, killing the `failed systemd units` and
`stuck nixos-rebuild switch` checks, which are last in the script. On
vps, `/var/lib/health-alerts` is not persisted, so de-duplication resets
every boot. Meanwhile this audit found **three confirmed silent failures
that nothing alerted on**: `flake-update-test` has never completed (zero
automated `flake.lock` commits in 1371), the ISO autobuild has never
fired, and the recovery ISO is ten days stale with a dangling `result`
symlink. **Why this is a promotion and not three nits:** several
higher-severity findings' compensating control is "we would notice". The
evidence is that we do not, and the alerting path is built so that the
first failure hides the rest. **Suggested handling:** rate the alerting
path as a control in its own right, and fix stamp-on-success plus
non-aborting delivery before relying on it anywhere else. (Cosmetic but
in the same file: the Discord payload emits literal `\n` sequences, so
every alert renders as one run-on line — the module's entire value is
that a human reads it.)

### PROMO-05 — `types.path` on three secret-path options + store copies persist + public repo

**Parts:** F-P7-15 (LOW, latent), F-P8-16 (LOW).
**In the chain but yours:** F-P0-08 (MEDIUM).

In the pinned tree `types.path`'s check is `isStringLike`, which accepts
a genuine Nix path. Writing `sshKeyPath = /home/lilijoy/.ssh/id_ed25519;`
— removing two quote characters — type-checks, and Nix copies the
**fleet-root private key** into `/nix/store`, world-readable, on every
host that builds the config. F-P8-16 establishes that those store copies
persist across generations until GC, and §4.7 establishes there is no
obscurity to fall back on. So the *probability* is low and latent (hence
LOW), but the *cost of the accident* is unrecoverable disclosure of the
credential that owns the fleet, with no way to withdraw it. The same
applies to the vps deploy key and the Discord webhook. **Suggested
handling:** treat the one-line change to `lib.types.externalPath` as
prevention of a HIGH, not as a LOW cleanup — nixpkgs ships the right type
and documents this exact hazard in a comment on the line (*"Do not allow
a true path, which could be copied to the store later on"*). Confirm
`externalPath` exists on homelab's stable pin too.

### PROMO-06 — zrepl's dead `sink`/`tcp` code + "a commit is fleet root"

**Parts:** F-P6-11 (LOW), F-P6-13 (INFO).
**In the chain but yours:** F-P0-01 (HIGH).

Both findings discount themselves on the grounds that enabling the code
"requires a commit". Per F-P0-01 a commit **is** root on all four hosts
within a cycle, and A6 is the adversary that produces one — so "requires
a commit" is not a barrier, it is the threat model's own path. That
reframes roughly 40% of a 1094-line root-running module: `sink` is the
only code path that writes a forced-command key accepting *incoming*
replication, i.e. live code implementing the topology `zrepl.nix:9-21`
argues against at length, and `defaultTransport = "tcp"` is one enum
value from plaintext `zfs send` of every home directory authenticated by
source IP. **Suggested handling:** the deletion recommended in F-P6-13 is
not tidying — it removes two one-line paths from a rejected design out of
the reach of the adversary that can write one line.

### PROMO-07 — stable MAC on a roaming laptop + a public repo describing that laptop

**Parts:** F-P5-16 (LOW).

Recorded because the argument is made *inside* a LOW finding and will be
lost in the pile. `wifi.macAddress` and `ethernet.macAddress` are both
`"preserve"` (scan randomisation is on, which is the easy half), so once
thinkpad associates it presents a stable, globally unique, long-lived
identifier to every network it joins. Normally recognising a laptop
across venues tells an attacker little, because they still do not know
what it runs. Here it is the whole problem: thinkpad's exposed-port list,
user account, disk layout and the fact that it holds a fleet-root key are
all a public lookup away, so a stable MAC is the single missing link
between "some laptop in a café" and "the machine that owns the fleet".
`"stable"` (per-SSID) fixes it without breaking captive portals or home
DHCP reservations.

---

## 5. Needed/used rollup

Everything the nine reports found to be dead, unused, vestigial or
**broken**. `Status` distinguishes them: **§5.1 BROKEN** = does not do
what it says, and the fix is usually to repair rather than remove;
**§5.2 unused** = works, has no consumer. `Remove?` is about deleting the
config, not about whether to act.

### 5.1 Broken — does not do what it says

| Item | File:line | What it was for | Evidence it is broken | Safe to remove? |
|---|---|---|---|---|
| `/srv` tmpfiles rule | `hosts/homelab/configuration.nix:80` | make `/srv` `0770` so game-server data is not casually traversable | pinned `systemd-260.2` rejects the line: `Invalid age 'root'`, exit 65 (reproduced); `/srv` is created implicitly at `0755` (F-P3-12) | ~~**no — fix**: `"d /srv 0770 root root - -"`, then re-check child modes~~ **superseded 2026-08-28: that exact fix was applied, then reverted live because it broke jellyfin's traverse access. Redesigned — see the `/srv` entry in §2's SYS-01 table for the current shape and `2026-08-28-fix-srv-permissions-stop-three-systems-fighting-ov.md` for the full record.** |
| `SSH_AUTH_SOCK` placeholder | `modules/profiles/PC.nix:165-166` | route `ssh` through the Bitwarden agent instead of on-disk keys | literal `<user>` never substituted; live `env` on torrent shows the placeholder verbatim while the real socket is at `/home/lilijoy/` (F-P1-07, F-P8-22) | **no — fix with the deploy-key story**, not alone: a locked agent breaks unattended `myPullDeploy` |
| `myIsoAutobuild.triggeredBy` | `modules/nixos/iso-autobuild.nix:69-74` | rebuild the recovery ISO after a successful `pull-deploy` | `lib.genAttrs` uses the value as an attribute name, so NixOS renders `pull-deploy.service.service`; confirmed live, and the real unit has no `OnSuccess` (F-P7-12) | **no — fix** (`lib.removeSuffix ".service"` + an assertion on names containing `.`); wire after F-P7-09 or every skipped run triggers a multi-GB build |
| `/var/lib/iso-autobuild/result` | same | the built ISO's store path | dangling symlink to a garbage-collected path; a manual `iso-copy-to-downloads` exits 0 with "No iso has been built yet" (F-P7-12) | consequence of the above |
| the recovery ISO in `~/Downloads` | `/home/lilijoy/Downloads/nixos-recovery-*.iso` | bootable rescue media | dated **2026-08-16**, ten days stale, predating several master commits (F-P5-10) | consequence of the above |
| `openssh` missing from `auto-update.nix`'s `path` | `modules/nixos/auto-update.nix:34-39,135-139` | let `auto-switch`/`flake-update-test` run `git fetch` over SSH | rendered `PATH` has no `openssh`; git resolves `ssh` via `PATH` (verified: neither git 2.54 nor 2.55 hardcodes it). `pull-deploy.nix` and `push-deploy.nix` both list it; this one does not. **Zero `chore: automated flake.lock update` commits in 1371** (F-P7-10) | **no — add** `openssh`; it is also a prerequisite for F-P0-01 option (b) |
| `flake-update-test` sandbox | same | run `nix flake update` as root | `ProtectSystem = "strict"` with `ReadWritePaths = ["/etc/nixos"]` makes `/root` read-only; `nix flake update` needs `~/.cache/nix/fetcher-cache-*.sqlite` — the exact problem `iso-autobuild.nix:108-114` solves for itself and this does not (F-P7-10) | **no — add** `/root/.cache/nix` |
| `services.networkd-dispatcher` | `hosts/homelab/configuration.nix:27-36` | apply a tailscale UDP-GRO ethtool tweak on `enp3s0` | its only trigger is a `org.freedesktop.network1` signal; homelab runs NetworkManager and `systemd.network.enable` is `false`, so nothing ever owns that bus name. The tweak has never applied; an unsandboxed root Python daemon idles forever (F-P3-19) | **yes — replace** with a NetworkManager `dispatcherScripts` entry or a `network-online.target` oneshot, then drop the service |
| health-alerts stamps before sending | `modules/nixos/health-alerts.nix:122-134` | de-duplicate repeated alerts | `echo "$now" > "$stamp"` precedes the `curl`; a failed POST is lost *and* suppressed for 6 h, and `curl`'s exit under the inherited `set -e` aborts the rest of the run (F-P7-13) | **no — fix**: stamp on success, tolerate delivery failure, add `--max-time 10` |
| health-alerts Discord payload | `modules/nixos/health-alerts.nix:132` | a formatted code block in Discord | Nix indented strings do not process `\n` and `jq --arg` escapes the backslash; the emitted JSON renders as one run-on line containing literal `\n` (F-P7-13) | **no — fix** |
| `/var/lib/health-alerts` not persisted | `hosts/vps/configuration.nix:248-270` | keep cooldown stamps across reboot | absent from the persist list on a tmpfs-root host, so every boot re-alerts for anything still broken. Not `DynamicUser`, so a plain directory entry works (F-P2-21) | **no — add** to the persist list |
| jellyfin `KnownProxies` patch | `modules/services/jellyfin.nix:62-71` | make the per-IP brute-force lockout work behind the tunnel | the `[ -f "$networkXml" ]` guard no-ops on first boot; jellyfin then creates the file with an empty `KnownProxies` and the lockout is inert until restart. The comment's "self-heals" claim covers the clearing case, not the creation case (F-P4-11) | **no — fix**; logging loudly on the skip is free and probably sufficient |
| `factorio-new`'s floating `stable` tag | `modules/services/factorio.nix:149-159` | "pick up engine updates automatically on restart" | `pull` defaults to `"missing"` (visible as `--pull missing` in the realised argv) and `/var/lib/docker` is persisted, so the image never refreshes (F-P4-13) | ~~**no — decide**: `pull = "newer"` and accept the trade, or correct the comment.~~ **moot 2026-08-28: `factorio-new` removed entirely (`7a047b7`).** Also digest-pin `factorio-main`, whose `2.1.14` is a mutable tag — **this half is still open** |
| samba `hosts allow` is IPv4-only | `modules/services/samba.nix:50-52` | restrict SMB to the tailnet | rendered `hosts allow=100.64.0.0/10`; `smbd` binds `[::]:445` and every tailnet node has an `fd7a:115c:a1e0::/48` address, so v6 peers are rejected. Fails closed today (F-P4-14) | **no — fix**: add the v6 prefix |
| samba `hosts deny=0.0.0.0/0` | `modules/services/samba.nix:50-52` | "defense in depth" | does nothing (the allow list already excludes everything else) and covers no IPv6; a future reader relaxing `hosts allow` while trusting it opens 445 to every v6 source (F-P4-14) | **yes** (or add `::/0`) |
| duplicate `safe.directory` appended on every run | `modules/flake/deploy-guards.nix:24` | suppress git's dubious-ownership refusal | `git config --global --add`, same value, never checked; unbounded growth on torrent and thinkpad where `/root` persists, self-limiting on homelab where it does not (F-P7-16) | ~~**no — guard with `--get-all`**, or remove entirely as part of F-P7-01~~ **superseded (`929efa3`, third session): removed entirely rather than guarded.** The whole `git config --global --add` approach was replaced by a `git() { command git -c safe.directory="$PWD" "$@"; }` wrapper (found necessary for an unrelated reason — root's `~/.config/git/config` is a home-manager store symlink, so the old code's global-config write broke on a read-only store). The new form writes nothing, so there is nothing left to grow. Deployed and verified live on homelab and vps. |
| `.githooks/pre-push` pathspec filter | `.githooks/pre-push:23,37` | build only when build-relevant paths change | filters on `profiles/` and `services/`, which do not exist at top level (they are `modules/profiles/`, `modules/services/`), and **misses `files/`**, which *is* build-relevant (`PC.nix:242` reads `files/gruvbox-dark-rainbow.png`) — so a `files/` change can land unbuilt (F-P7-16) | **no — fix**: add `files/`, drop the two dead pathspecs |
| sshd `PermitRootLogin` / `X11Forwarding` in `extraConfig` | `hosts/vps/configuration.nix:321-331`, `hosts/homelab/configuration.nix:376-386` | the SSH hardening baseline | inert — the module emits both first and sshd_config is first-directive-wins; verified with `sshd -T` against mutated copies (F-P2-09, F-P3-18) | **no — move to `settings.*`**: byte-identical output, a no-op to behaviour and a real change to safety |
| `tmux.nix` header | `modules/home-manager/tmux.nix:6-8` | claims "shared by every host (root on servers, lilijoy on PCs)" | only `server.nix:56` imports it; `PC.nix:152-157` does not, so `lilijoy` gets the binary with no configuration (F-P8-23) | **no — decide**; review `@continuum-restore 'on'` before adding it to `PC.nix` (it re-executes saved command lines from a user-writable home) |
| `vps_caddy_env`'s value stored unencrypted | `secrets/secrets.yaml` | placeholder for a DNS-01 token | the value is the literal empty string, which sops leaves unencrypted — readable without any key (F-P8-18) | see §5.2 |

### 5.2 Unused — works, has no consumer

| Item | File:line | What it was for | Evidence it is unused | Safe to remove? |
|---|---|---|---|---|
| `sops.secrets.vps_caddy_env` | `hosts/vps/configuration.nix:477` | a DNS-01 provider token, per its `# TODO` | `services.caddy.environmentFile` evaluates to `null`; nothing references the path; the Caddyfile uses no DNS-01 challenge. sops decrypts it into `/run/secrets` on every boot for no reader (F-P2-13, F-P8-18) | **yes** — but the `secrets.yaml` half is a **user-only** edit |
| `"docker"` in `extraGroups` | `modules/profiles/PC.nix:313` | container socket access for `lilijoy` | `virtualisation.docker.enable = false`, so nothing declares `users.groups.docker`; the generated `users-groups.json` has no such group; live `getent group docker` exits 2, `id` shows no docker, and no `docker.sock` exists (F-P1-13, F-P5-13) | **yes** — and see SYS-08: it becomes live root-equivalent the day docker is enabled |
| duplicate `"input"` in `extraGroups` | `modules/profiles/PC.nix:312` (+ `modules/nixos/wooting.nix:9`) | keyboard/device access | listed twice in the merged value; removing it from `PC.nix` alone is insufficient (F-P1-15, F-P5-13) | yes |
| `boot.binfmt.emulatedSystems = ["aarch64-linux"]` | `modules/profiles/default.nix:115-117` | cross-arch execution | the only `aarch64` hit in the repo; `systems.nix` is `["x86_64-linux"]`; no host targets aarch64 and nothing cross-compiles. Registered live on torrent. Flags are `P`, not `F`, so the container-relevant variant is not in play (F-P1-14, F-P2-14) | needs-check (a grep of shell history settles it); closure shrinks on all four hosts |
| `security.sudo.execWheelOnly` + `sudo.override { withInsults }` | `modules/profiles/default.nix:60-65` | sudo policy | both sit under `enable = false`; the `withInsults` build is never realised. The `enable = false` itself is load-bearing — the run0 module asserts on it (F-P1-15) | yes |
| duplicate `security.sudo.enable = false` | `modules/profiles/server.nix:21` | server baseline | `profile-default` already sets it for every host — so `docs/hardening.md` describing it as *server* baseline is misleading (F-P1-15) | yes, plus one sentence of doc correction |
| empty `environment.systemPackages` | `modules/profiles/server.nix:14-15` | — | `with pkgs; [ ]` (F-P1-15) | yes |
| empty `pkgs-stable` list | `modules/profiles/PC.nix:89-90` | — | `++ (with pkgs-stable; [ ])`; the `# temp copy from stable` comment at `:77` describes *this* list, not the block below it (F-P1-15) | yes |
| `services.pulseaudio.support32Bit` | `modules/profiles/PC.nix:293-294` | 32-bit audio for Steam | sits under `services.pulseaudio.enable = false`; the path Steam actually uses is `services.pipewire.alsa.support32Bit`, set by the Steam module (F-P1-15) | yes |
| `gjs # for kdeconnect` | `modules/profiles/PC.nix:32` | KDE Connect | `gjs` is needed by *gsconnect* (the GNOME implementation); this fleet runs `kdeconnect-kde`, which does not use it (F-P1-15) | needs-check — open KDE Connect once |
| `distrobox` listed twice | `modules/profiles/PC.nix:39,50` | — | same list, two entries (F-P1-15) | yes |
| `texliveSmall` | `modules/profiles/PC.nix:71,86` | LaTeX | `texliveFull` is also installed and subsumes it (F-P1-15) | needs-check — build a document once |
| `services.fwupd.enable` on servers | `modules/profiles/default.nix:101` | firmware updates | `true` on vps, a KVM guest with no flashable firmware, and on headless homelab where it drags `services.udisks2.enable = true` (pinned `fwupd.nix:200`, own default `false`) plus a weekly LVFS fetch and an fwupd polkit rule (F-P1-15, F-P2-14, F-P3-23) | **yes — move to `PC.nix`**, or force `udisks2` off in `server.nix` |
| `services.smartd` on homelab | `modules/profiles/default.nix:104-113` | drive health alerts | headless, no session, no X server — all three sinks (`wall`, `x11`, `systembus-notify`) discard everything. `myHealthAlerts` already polls SMART every 15 min and reaches a human; vps already forces smartd off (F-P3-24) | yes — confirm the next Discord alert enumerates all five drives first |
| `hardware.enableAllFirmware` on vps | `modules/profiles/default.nix:123` | device firmware | a large firmware tree on a 25 GB disk with an 18 GB `/nix` (F-P2-14) | needs-check |
| `nix.nixPath = nixpkgs-unstable` | `modules/profiles/default.nix:126` | `<nixpkgs>` for `nix-shell -p` | pins a full nixpkgs source tree into vps's closure on a host that must never evaluate anything; on homelab it points `<nixpkgs>` at **unstable** although homelab is pinned to stable (F-P1-15, F-P2-14) | needs-check — a reproducibility surprise, not a security issue |
| `ffmpeg`, `flac`, `bitwarden-cli`, `topgrade`, `smartmontools`, `zfs-prune-snapshots` on vps | `modules/profiles/default.nix:23-48` | desktop/media tooling | inherited wholesale by the edge host; `smartmontools` is contradicted 200 lines away by `services.smartd.enable = lib.mkForce false` and `checkSmart = false` (F-P2-14) | needs-check — `bitwarden-cli` on the internet-facing box is the one worth a second look |
| CrowdSec prometheus exporter | module default, effective on vps | metrics | on at `127.0.0.1:6060` with nothing scraping it (F-P2-14) | needs-check |
| `services.flatpak.packages` (2 entries) | `modules/profiles/PC.nix:125-132` | declare installed flatpaks | ten-plus apps from four remotes installed on torrent, including `vish-repo` (system-wide) and `flathub-beta` (per-user) — neither in the repo; `uninstallUnmanaged = false`, so nothing reconciles (F-P1-16) | **no — decision required**; the current middle ground is the worst of both. `uninstallUnmanaged = true` would remove every undeclared application, in some cases with user data, on the next activation |
| `allowSFTP = true` | `hosts/homelab/configuration.nix:356` | sftp/scp to homelab | `Subsystem sftp` confirmed present in `sshd -T`; no consumer in the repo (zrepl uses `ssh+stdinserver`, deploy uses `nix-copy-closure`, factorio mod sync is local `rsync`) (F-P3-15) | needs-check — one question: *do you ever `scp` to homelab?* OpenSSH 9.0+ makes `scp` speak SFTP. Failure is immediate and obvious, so it is safe to try |
| explicit forwarding sysctls | `hosts/homelab/configuration.nix:404-408` | enable IP forwarding | `net.ipv4.ip_forward` and `net.ipv4.conf.all.forwarding` are the same kernel knob, and the tailscale module already forces all of it at `mkOverride 97` under `useRoutingFeatures = "both"` (F-P3-20) | needs-check — **must be removed in the same change as the F-P0-06 default inversion**, or homelab silently stops routing |
| `rpcbind` + NFSv3 helpers on homelab | pulled in by `modules/services/nfs.nix` | NFSv3 | exports are NFSv4-shaped; `mountdPort`/`statdPort`/`lockdPort` all `null`; 111 is in no `allowed*Ports` on any interface (F-P3-21, F-P4-15) | needs-check — `extraNfsdConfig = "vers3=n"`; check `nfs-homelab-mounts.nix` as the consumer first |
| `rpcbind` on both laptops | `modules/nixos/nfs-homelab-mounts.nix:36-45` | NFS client | both mounts are `fsType = "nfs4"`, which needs no portmapper; live on torrent it listens on `0.0.0.0:111` and `[::]:111`, TCP and UDP (F-P5-17) | needs-check — `lib.mkForce false`, then touch both mountpoints. Failures are quiet empty directories (`mount-timeout=10`, `retry=0`), not boot errors |
| commented-out root password | `hosts/homelab/configuration.nix:272-273` | lock root | `mutableUsers = false` with a null `hashedPassword` already writes `!` (pinned `update-users-groups.pl:299`), so uncommenting it would be a no-op (F-P3-22) | yes — replace with a comment saying why root is locked |
| UDP 25565 on `tailscale0` and `wg0` | `modules/services/minecraft.nix:33-36,50-53` | minecraft | Java Edition is TCP-only; Bedrock is 19132/udp via Geyser. The container publishes 25565/tcp only, and vps forwards it with `proto = "tcp"`. A rule whose reason never existed (F-P4-12) | yes |
| bare `factorio` A record | `modules/services/octodns.nix:69-75` | compatibility alias for `old.factorio` | duplicates a record and says so (F-P4-15) | yes — costs nothing either way |
| raw `cloudflare_octodns_token` owner/group grant | `modules/services/octodns.nix:167-170` | token delivery | only the rendered template is consumed (`:185`); sops-nix writes the raw file regardless, so the `owner`/`group` grant is the removable part (F-P4-15) | yes — marginal |
| thinkpad impermanence scaffolding | `hosts/thinkpad/disko.nix:67-80`, `configuration.nix:88-89` | a wipe-on-boot root | `environment.persistence` evaluates to `{}`; there is no `zfs rollback …@blank` in thinkpad's initrd (the only such line is homelab's `:463`); `vars.persistRoot` is consumed only by homelab. So `/` is durable, `@blank` is inert, and `neededForBoot` on an empty `/nix/state` makes boot depend on it for nothing (F-P5-14) | **no — comment**, per `TODO.md:298-310`; a reader who sees `@blank` will reason wrongly about persistence-of-compromise |
| `nixpkgs.config.allowBroken = true` | `hosts/torrent/configuration.nix:50` | admit `r8125` | against the pinned nixpkgs `r8125-9.016.01` evaluates `meta.broken = false` (as does the zfs kernel module), so the stated reason is dead. Host-global, so it silently permits *any* broken package on the daily driver (F-P5-15 — PLAUSIBLE that nothing else needs it) | needs-check — one `nixos-rebuild build --flake .#torrent` settles it, and the build names any consumer |
| the host name `torrent` | `hosts/torrent/configuration.nix:59` | — | no torrent client, tracker or seedbox anywhere; a filter over `systemd.services` returns `[]` and live `ps` matches nothing. Only `qbittorrent` and `nicotine-plus` desktop packages, from the shared PC profile (F-P5-18) | **no** — load-bearing in six places (`hostName`, `hostAttr`, `tag:torrent`, the sops key, `.sops.yaml`, `zbackup/backup/torrent/…`). Comment instead |
| zrepl `push` role | `modules/nixos/zrepl.nix:840-874` | push-mode replication | `docs/backups.md`'s own table says "nobody currently"; the documented future case (thinkpad) is explicitly kept on pull at `thinkpad:101-106` (F-P6-13) | yes |
| zrepl `sink` role | `modules/nixos/zrepl.nix:878-946` | receive-mode replication | unused, and it is the only path that would write a forced-command key accepting **incoming** replication — the topology `zrepl.nix:9-21` argues against (F-P6-13) | yes — see PROMO-06 |
| zrepl `tls` transport | `modules/nixos/zrepl.nix:69-75,94-100,430-455,778-792,900-925` | encrypted non-SSH transport | six options across four submodules, never set on any host (F-P6-13) | yes |
| zrepl `tcp` transport | `modules/nixos/zrepl.nix:65-68,88-93` | plain TCP transport | never set; its only authentication is a client-IP→identity map with no cryptography (F-P6-11, F-P6-13) | yes — see SYS-08 |
| `preserveLegacySnapshots` / `legacySnapshotPrefix` | `modules/nixos/zrepl.nix:546-565` | sanoid-era `autosnap_` snapshots | all three hosts set it `false` (`homelab:262`, `torrent:84`, `thinkpad:109`) and no evaluated keep rule contains `^autosnap_`. The cutover is complete and the `true` default is a trap for a fourth host (F-P6-13) | yes — flip the default first |
| zrepl `sshOptions` | `modules/nixos/zrepl.nix` | per-host ssh flags | used only by the VM test, never in production (F-P6-13) | needs-check |
| `myPushDeploy.elevate = "none"` | `modules/nixos/push-deploy.nix` | non-sudo activation | homelab is the only caller and takes the `"sudo"` default — a branch in root-running deploy code with no user (F-P7-16) | yes, or exercise it |
| `tag:isoimage` in the tailnet ACL | `docs/tailscale-acl.json:23,37,38,46,52,58,79,86,87` | an ISO device on the tailnet | nine occurrences describing a device that cannot exist: `isoimage`'s module list omits `profile-default`, so `services.tailscale.enable = false` and `config.sops` is not even an option; `tailscale status` shows no such node (F-P8-19) | yes — a phantom entry in a security-policy file makes the real entries harder to audit |
| `tailscale_authkey_isoimage` | `secrets/secrets.yaml` | enrol the ISO | same (F-P8-19) | yes — **revoke the key in the console first** (an unused auth key that still exists is A5's "over-broad auth key"); the file edit is **user-only** |
| `permittedInsecurePackages = ["electron-39.8.10"]` | `modules/flake/pkgs.nix:7-9` | admit an EOL Electron for (probably) obsidian | against the pinned tree `obsidian` evaluates cleanly *without* the permit, as do `wootility`, `via`, `vial`, `bitwarden-cli`, `gnome-boxes`, `obs-studio`. Applies **fleet-wide**, servers included (F-P8-20 — PLAUSIBLE) | needs-check — delete and build torrent + thinkpad; a failure names the consumer, which is exactly the information the entry currently suppresses |
| `permittedInsecurePackages = [ "" ]` | `modules/flake/pkgs.nix:16` | — | an empty string matching no package; reads intentional (F-P8-20) | yes |
| stale key label `lilijoy@nixos-thinkpad` | `modules/flake/vars.nix:7` | identify the first admin key | the host's former hostname; the `.sops.yaml` anchor `&nixos-thinkpad` carries the same stale name, so the two are probably the same vintage (F-P8-22) | yes — cosmetic, but the vintage helps F-P8-04's attribution work |
| `/home/lilijoy/.ssh/id_rsa` | not in the repo | unknown | 3072-bit RSA (`SHA256:vVNQx1bJv9kdpjUKyTD7nI9bZNKEKKS7Ec1d0D9Sego lilijoy@torrent`, dated 2025-07-20), in no `authorizedKeys` list in the repo and unexplained in `docs/`. Unmanaged either way (F-P8-22) | needs-check — **user identifies it**; 3072-bit RSA is below what you would generate today |
| three unfollowed transitive nixpkgs revisions | `flake.nix`, `flake.lock` | — | `impermanence` brings its own `nixpkgs` + `home-manager`; `plover-flake` brings `nixpkgs_2` and, via `treefmt-nix`, `nixpkgs_3`. `impermanence`'s is inert; `plover-flake` actually *builds* from its own, so a second nixpkgs lands in both PC closures (F-P8-21) | needs-check — a `follows` can break `plover-flake`; build both PC hosts and be ready to revert that one line |
| `/var/lib/nfs` not persisted | homelab's persist list | NFSv4 `v4recovery` state | recreated empty every boot by `nfsd.nix`'s `preStart`; clients cannot reclaim locks across a server reboot (F-P4-15) | **no — add it**; correctness, not security |
| `modules/services/README.md` | does not exist | the service inventory and "Gotchas" that `docs/procedures/new-service.md` step 6 points at | referenced by the runbook, absent from the tree (F-P4-15) | **no — create it**; several of this audit's gotchas belong there |

---

## 6. Traceability

Every input id, and where it landed.

- **SYS-01:** F-P1-07, F-P1-13, F-P1-15, F-P3-12, F-P3-19, F-P4-11, F-P4-13, F-P5-13, F-P7-12, F-P8-22
- **SYS-02:** F-P2-09, F-P3-18, F-P6-10, F-P3-15 · *refs* F-P5-07 (MEDIUM)
- **SYS-03:** F-P1-11, F-P5-09, F-P2-12
- **SYS-04:** F-P4-14, F-P2-11
- **SYS-05:** F-P1-10, F-P3-17, F-P5-16
- **SYS-06:** F-P3-21, F-P5-17, F-P4-15
- **SYS-07:** F-P6-09, F-P4-07, F-P4-10
- **SYS-08:** F-P0-05, F-P8-12, F-P6-11, F-P7-15, F-P8-20, F-P1-13, F-P6-13
- **SYS-09:** F-P2-19, F-P1-09, F-P1-12, F-P3-23, F-P3-24, F-P2-14 · *refs* F-P0-06 / F-P1-06 (MEDIUM)
- **SYS-10:** F-P0-02, F-P2-10, F-P8-13, F-P6-08, F-P4-08, F-P2-17, F-P4-09, F-P8-23, F-P5-18, F-P6-14, F-P6-15
- **SYS-11:** F-P5-12, F-P8-16, F-P8-14 · *refs* F-P0-08 (MEDIUM)
- **SYS-12:** F-P2-15, F-P8-15, F-P8-17, F-P1-16, F-P8-21
- **L-01…L-15:** F-P2-16, F-P3-13, F-P5-10, F-P5-11, F-P7-17, F-P6-12, F-P1-08, F-P3-14, F-P4-10, F-P2-18, F-P3-16, F-P3-11, F-P2-20, F-P6-14, F-P6-15, F-P7-14
- **Promotions add:** F-P0-07, F-P7-13, F-P2-21, F-P7-10
- **Rollup-only (no narrative entry needed):** F-P1-14, F-P2-13, F-P3-20, F-P3-22, F-P4-12, F-P5-14, F-P5-15, F-P7-16, F-P8-18, F-P8-19, F-P5-08

**Genuinely trivial, one line each, no further comment warranted:**
F-P3-22 (a commented-out no-op), F-P4-12 (a UDP port nothing ever bound
and nothing forwards), F-P8-20's `[ "" ]` entry, the duplicated
`distrobox` and `input` entries, and the two empty package lists.

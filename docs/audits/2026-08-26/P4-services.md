# P4 — exposed services

Part 4 of the 2026-08-26 fleet-wide security audit. Scope:
`modules/services/{minecraft,factorio,jellyfin,samba,nfs,copyparty-iso,octodns}.nix`
and `modules/services/minecraft-geyser-config/`.

Severity rubric, adversary ids (A1–A9) and failure modes (§7.x) are
from [`00-threat-model.md`](00-threat-model.md). Finding schema is
[`P0-findings.md`](P0-findings.md).

**Headline.** The 2026-08-26 IPv6 pass is described elsewhere in this
repo as the reference standard, and for the three *native* services it
touched (jellyfin, samba, nfs) it holds up: those interface-scoped
rules are real and effective. For the two *containerised* services it
does not, and cannot: a docker published port is DNAT'd in the `nat`
table and delivered through `FORWARD`, so it never passes through the
`nixos-fw` INPUT chain at all. All four game ports are open on every
IPv4 address homelab has, including the LAN NIC, and the rules in
`minecraft.nix:23-36` and `factorio.nix:72-79` do not constrain them.
That is F-P4-02, and it is the single most important thing in this
report because the file it lives in is the one other files are being
told to copy.

**Re-rated for a public repository.** Threat model §4.7 was added
mid-audit: this repo is public on GitHub. Everything below was
re-assessed against it before finalising, and three ratings moved as a
result (F-P4-03 and F-P4-05 to HIGH, F-P4-13 to LOW). The rule applied
is §4.7's: no control may be credited for being hard to find, and every
reachability assessment treats "the adversary has read the config" as
satisfied by default. For this part that is not a formality. The exact
images, tags, capability sets, port maps, volume mounts, mod lists,
export options, share names, gids and rate-limit thresholds protecting
the two internet-exposed game servers are all published, which means A3
selects an exploit from a known surface rather than probing for one.

---

## 1. Scope and method

### Files read in full

| File | Lines |
|---|---|
| `modules/services/minecraft.nix` | 148 |
| `modules/services/factorio.nix` | 176 |
| `modules/services/jellyfin.nix` | 129 |
| `modules/services/samba.nix` | 189 |
| `modules/services/nfs.nix` | 36 |
| `modules/services/copyparty-iso.nix` | 44 |
| `modules/services/octodns.nix` | 210 |
| `modules/services/minecraft-geyser-config/Geyser-Fabric/config.yml` | 12 |

Supporting reads: `docs/hardening.md`, `docs/procedures/new-service.md`,
`modules/flake/hosts.nix`, `modules/flake/vars.nix`,
`modules/nixos/nfs-homelab-mounts.nix`, `hosts/homelab/configuration.nix`,
`hosts/homelab/disko.nix`, `hosts/isoimage/configuration.nix`, and
`hosts/vps/configuration.nix:360-460` (the DNAT/SNAT/rate-limit block).

`modules/services/README.md` — referenced by
`docs/procedures/new-service.md` as the place service inventory entries
go — **does not exist**. Noted under F-P4-15.

### Pinned sources actually consulted

homelab evaluates against `nixpkgs-stable` 26.05, resolved to
`/nix/store/xk3y420fsdc1hm9il55vyz4b0gxsk6dg-…-source` (via
`nix eval --raw .#nixosConfigurations.homelab.pkgs.path`). isoimage
evaluates against `nixpkgs-unstable` (26.11pre). Modules read from the
pinned tree, not from memory:

- `nixos/modules/virtualisation/oci-containers.nix` — `ports` option
  semantics and its own warning, `pull` default, argv construction
  (`:483`, `:498`).
- `nixos/modules/virtualisation/docker.nix` — `daemon.settings`.
- `nixos/modules/services/network-filesystems/nfsd.nix` — `:145`
  `services.rpcbind.enable = true` unconditionally.
- `nixos/modules/services/network-filesystems/samba.nix` — `:80`,
  `:258-265` (what `openFirewall` would have opened).
- `nixos/modules/services/misc/jellyfin.nix` — `:143-151`, `:432-474`,
  `:502-510` (the upstream sandbox stack and `openFirewall` default).
- copyparty `1.20.20` `authsrv.py:1673` — the `A` permission expansion.
- sops-nix `modules/sops/templates/default.nix:54-80,138-152` — `owner`
  vs `uid` precedence.

### Claims verified by evaluating the effective merged config

Everything below was read out of `nix eval
.#nixosConfigurations.<host>.config.…`, not inferred:

- `virtualisation.oci-containers.containers` in full (all three).
- The **generated `docker run` argv** for each container, read from the
  realised unit scripts in the store — this is what actually settles
  the port-publishing question.
- `networking.firewall` in full on homelab (`filterForward = false`,
  `trustedInterfaces = ["lo"]`, `backend = "iptables"`).
- `virtualisation.docker.daemon.settings` (`userland-proxy = false`,
  no `ipv6`, no `userns-remap`) and `virtualisation.docker.package`
  (docker 29.6.2).
- The rendered `/etc/samba/smb.conf`, `/etc/nfs.conf`, and the
  copyparty `.conf` (which shows `[accounts]` **empty**).
- `systemd.services.{jellyfin,samba-smbd,samba-user-provision,octodns-sync,copyparty}.serviceConfig`.
- `environment.persistence."/nix/state"` on homelab, and
  `hosts/homelab/disko.nix` confirming `zroot/local/state` → `/nix/state`.
- `users.groups.docker.members` on homelab: `[]`.

### What I could **not** verify, and where that changes a rating

1. **Whether docker's published ports are reachable over homelab's
   public IPv6.** This is the difference between MEDIUM and CRITICAL on
   F-P4-02. Static reasoning says no — the default bridge is IPv4-only
   (`ipv6` unset in `daemon.json`) and `userland-proxy = false` removes
   the Go dual-stack listener that historically made v4-only published
   ports answer on `::`. I could not confirm docker 29.6.2's exact
   behaviour from the packaged binary and did not test live. Marked
   PLAUSIBLE, with a specific test named in the finding. **This test
   should be run before anything else in this report.**
2. **Image contents.** `itzg/minecraft-server` and
   `factoriotools/factorio` entrypoint behaviour (the `usermod` step,
   `ONLINE_MODE` default, whether `PUID`-equal skips the root dance) is
   asserted from the repo's own comments, not read. Anything depending
   on it is PLAUSIBLE.
3. **Secret contents.** Per `docs/procedures/secrets.md`, nothing under
   `secrets/` was decrypted. So: the Cloudflare token's scope, the
   Minecraft whitelist's actual membership, and the factorio password's
   strength are all unknown. F-P4-10 says what changes if the token is
   broadly scoped.
4. **Live state.** No SSH, no `iptables -L`, no `docker inspect`. Every
   runtime claim here is derived from the evaluated closure.

### Re-rating pass against §4.7 (public repository)

Added after the findings were first drafted. What I checked, given that
an adversary reads this repo as easily as I do:

- **Which of my findings rested on obscurity.** None did — reachability
  in every case was argued from a network path, not from an attacker's
  ignorance. So no rating went *down*, and none needed rescuing.
- **Which findings become easier to act on for a reader of the repo.**
  This is where the movement is. Anything where the published config
  tells an adversary *which version of untrusted-input-parsing code is
  running*, or *where a secret sits*, or *what the one remaining
  control's numeric threshold is*, was re-rated on the assumption that
  the lookup is free. F-P4-03 and F-P4-05 moved MEDIUM → HIGH,
  F-P4-13 INFO → LOW.
- **What the public config actually discloses within my scope**, put on
  the record rather than re-derived later: image names and tags;
  `VERSION = "LATEST"` and `TYPE = "FABRIC"`; the sixteen Modrinth mod
  slugs and `MODRINTH_ALLOWED_VERSION_TYPE = "alpha"`; both factorio
  engine pins including that `2.1.14` is the experimental line and why;
  `UPDATE_MODS_ON_START` on both factorio servers; every capability
  add-back and the absence of `--read-only` on factorio; every port map
  and the full vps DNAT table; vps's hashlimit thresholds to the
  packet; the NFS export options and the `100.64.0.0/10` CIDR;
  `gids.multimedia = 999`; the samba share names, `valid users` and
  `hosts allow`; copyparty's `A = [ "*" ]` on `/` and port 3923; the
  domain and both vps public addresses; and the world seed.
- **What is correctly *not* disclosed.** The minecraft whitelist/ops
  usernames are sops-managed (`minecraft.nix:9-13`), and the factorio
  game password, account token and username likewise
  (`factorio.nix:100-102`). Under §4.7 that is the right instinct even
  though a whitelist is not really a secret — see §4.

---

## 2. Findings


Ordered most severe first. Ids were assigned during the first drafting
pass and are **stable** — F-P4-03, F-P4-05 and F-P4-13 moved position
when §4.7 changed their ratings, but no id was renumbered, so
cross-references from other parts stay valid.

| Order | Id | Severity | Title |
|---|---|---|---|
| 1 | F-P4-01 | HIGH | recovery ISO serves `/` with no authentication at all |
| 2 | F-P4-03 | HIGH | game servers auto-install unpinned third-party code; surface is published |
| 3 | F-P4-05 | HIGH | container egress reaches LAN, tailnet and vps unfiltered |
| 4 | F-P4-02 | MEDIUM | docker published ports bypass the firewall; scoping rules inert |
| 5 | F-P4-04 | MEDIUM | factorio secrets leave sops into a container volume and the backups |
| 6 | F-P4-06 | MEDIUM | NFS `sec=sys` — reaching 2049 *is* the authorization |
| 7 | F-P4-07 | LOW | no container rules in `docs/hardening.md`; no resource ceilings |
| 8 | F-P4-08 | LOW | vps SNAT destroys game-client attribution; comment says otherwise |
| 9 | F-P4-09 | LOW | factorio `--read-only` exception cites stale evidence |
| 10 | F-P4-10 | LOW | octodns holds a cert-issuance credential; no CAA declared |
| 11 | F-P4-11 | LOW | jellyfin lockout inert on first boot |
| 12 | F-P4-13 | LOW | `factorio-new`'s floating tag does not float, and publishes the build |
| 13 | F-P4-12 | INFO | dead UDP 25565 firewall rules |
| 14 | F-P4-14 | INFO | samba `hosts allow`/`hosts deny` pair is IPv4-only |
| 15 | F-P4-15 | INFO | needed/used sweep leftovers |

### F-P4-01 — the recovery ISO serves the entire filesystem with no authentication whatsoever, on a host-wide port

- **File:** `modules/services/copyparty-iso.nix:16-43` (esp. `:34-39`,
  `:43`); rendered config at `[accounts]` (empty) / `[/] A: *`
- **Severity:** HIGH
- **Confidence:** CONFIRMED for what is granted; PLAUSIBLE for the
  worst-case data reached (depends on the modes of whatever is mounted)
- **Axis:** hardening
- **Reachability:** A1/A4 — anyone with an IP path to the machine, on
  whatever network the recovery ISO is booted onto. No prior step, no
  credential, no tailnet membership. Threat model §2 already lists this
  as the only thing `isoimage` listens on publicly. Per §4.7 there is
  additionally no discovery step: `copyparty-iso.nix` is public, so
  anything answering on 3923 with copyparty's banner is known in advance
  to grant anonymous `A` on `/`, and `no-robots` (`:20`) keeps it out of
  search indexes without keeping it out of a scan.
- **Rule:** new-rule candidate; also threat model open question §8.6,
  which asks precisely for the written justification that does not exist.
- **Finding:** the generated copyparty config is:

  ```
  [accounts]        <- empty. there are no users. none.
  [/]
  /
  accs:
  A: *
  ```

  `A` is not "read-only public". Read from the pinned copyparty
  1.20.20 source (`authsrv.py:1673`), `A` expands to `rgwmda.` —
  **read, get, write, move, delete, admin, and dotfile visibility** —
  and `*` is copyparty's anonymous identity. So an unauthenticated
  network peer gets upload, rename, delete and the admin control panel
  over volume `/`, which is mapped to the live root, deliberately not
  `xdev`, and therefore covers whatever gets mounted under `/mnt`
  during a recovery session.

  The module's own systemd sandbox is strong (`ProtectProc=invisible`,
  `PrivateDevices`, `MemoryDenyWriteExecute`, `TemporaryFileSystem=/:ro`,
  the lot) and is then **nullified for the filesystem dimension by this
  config**: because a volume is declared at `/`, the module computes
  `BindPaths = ["/var/lib/copyparty", "/"]`, re-exposing the real root
  read-write inside the sandbox. Verified in the effective
  `serviceConfig`.

  What limits the damage is ordinary Unix DAC — copyparty runs as the
  unprivileged `copyparty` user (verified: `User=copyparty`), so
  `/etc/shadow`, host keys, `/root` and 0700 home directories stay out
  of reach. What is *not* limited: everything world-readable on the
  live root and on every recovery mount; anonymous delete of anything
  copyparty owns or that is world-writable; anonymous upload filling
  the ISO's tmpfs root mid-recovery; and — PLAUSIBLE, worth checking —
  read/write to files on a mounted foreign filesystem whose numeric
  owner happens to collide with the ISO's dynamically-allocated
  `copyparty` uid, since a recovery mount carries the *target's* uid
  numbering, not the ISO's names.

  The comment at `:6-11` is honest about the design ("no auth, serving
  the whole live filesystem", "do not reuse this config on a persistent
  host"). What it does not do is state the *decision* — that
  unauthenticated write and delete on arbitrary networks is an accepted
  cost of unimpeded recovery access. §8.6 asks for exactly that, and it
  is still missing.

  Rated HIGH rather than CRITICAL because it is not RCE and not root.
  Rated HIGH rather than MEDIUM because the prerequisite is *network
  adjacency and nothing else*, and the machine's entire purpose is to
  be present when the fleet's most valuable data is unprotected and
  mounted.
- **Proposed fix:** decision required. Options, cheapest first:
  (a) generate a random password at boot and print it on the console
  the operator is already sitting at (`services.getty.autologinUser =
  "root"` is set), turning this from anonymous into
  present-at-the-console-only, at essentially zero recovery-workflow
  cost; (b) bind copyparty to loopback plus the tailnet only and reach
  it over tailscale, which the ISO can already join; (c) keep it exactly
  as-is and write the accepted-risk paragraph §8.6 asks for, into
  `docs/hardening.md` and into the file's own header comment.
  Independent of which: `A` is broader than needed — `rw` would drop
  anonymous delete/move/admin while keeping recovery useful.
- **Fix risk:** (a) and (b) both add a step to a workflow whose whole
  point is that it works when everything else is broken; (b)
  specifically fails when the reason you booted the ISO is that
  networking or the tailnet auth key is the broken thing. If either is
  adopted, it must be tested by actually booting the ISO, not by
  building it.

### F-P4-03 — both game servers auto-install unpinned third-party code on every start, and the exact surface is published

- **File:** `modules/services/minecraft.nix:51`, `:56`, `:84-103`,
  `:132-145`; `modules/services/factorio.nix:115-118`, `:144`, `:170`
- **Severity:** HIGH — raised from MEDIUM under §4.7; see "Why this is
  HIGH" below
- **Confidence:** CONFIRMED for the configuration and the update
  channels; PLAUSIBLE for exploitability, which depends on advisories I
  did not enumerate
- **Axis:** hardening
- **Reachability:** two adversaries, not one.
  **A6** — a compromised upstream: sixteen independent third-party
  Modrinth projects on minecraft plus the Factorio mod portal on both
  factorio servers, all fetched at container start with no version
  constraint and no integrity check, any one of which is a sufficient
  entry point.
  **A1/A3** — and this is what §4.7 adds: an internet client can read
  this file, derive the exact parsing surface it is talking to, and
  match it against published advisories before sending a packet. A1 is
  rated "constant, happening now". The landing spot in both cases is a
  process handling untrusted internet traffic through vps's DNAT,
  holding a writable bind mount, with the network position described in
  F-P4-05.
- **Rule:** new-rule candidate.
- **Finding:** three unpinned supply-chain inputs stack here.

  - `image = "itzg/minecraft-server"` (`:51`) carries **no tag at
    all** — docker resolves that to `:latest`. This is looser than
    `factorio.nix:159`'s `stable`, which at least has a written
    justification (`:149-156`); the minecraft one has none and reads
    like an oversight rather than a decision.
  - `VERSION = "LATEST"` (`:56`) floats the Minecraft server version.
  - `MODRINTH_PROJECTS` (`:86-103`) lists sixteen projects, resolved by
    slug at every start, with `MODRINTH_ALLOWED_VERSION_TYPE = "alpha"`
    (`:84`) explicitly widening resolution to pre-release builds and
    `MODRINTH_DOWNLOAD_DEPENDENCIES = "required"` pulling further
    transitive artifacts nobody has listed.

  Partial mitigation, and it is real: `pull = "missing"` is the pinned
  module's default (verified, `oci-containers.nix:315-328`), and
  `/var/lib/docker` is on the impermanence persistence list
  (`hosts/homelab/configuration.nix:482`), so the *image* is fetched
  once and then stays. The **mods are not** — `MODRINTH_PROJECTS` is
  re-resolved by the entrypoint on every container start, which is
  every reboot and every `nixos-rebuild switch` that touches the unit.
  That is the live channel.

  **Factorio has the same channel**, which the first draft of this
  report under-weighted. Both servers set `UPDATE_MODS_ON_START =
  "true"` (`factorio.nix:144`, `:170`), so factoriotools' entrypoint
  refreshes the installed mods from the Factorio mod portal on every
  start, authenticating with the account token from F-P4-04; and
  `docker-factorio-new`'s `preStart` rsyncs `old.factorio`'s mod
  directory into `new.factorio` before every start (`:115-118`), so one
  compromised mod reaches both servers by design. The installed mod set
  lives in `/srv/factorio/*/mods` and is not declared in the repo, so
  unlike minecraft the *list* is not public — but the auto-update
  mechanism is, and it is not pinned, reviewed or version-constrained
  anywhere.

  **Why this is HIGH under §4.7.** Rated MEDIUM in the first draft on
  the reasoning that the only adversary was A6, and a supply-chain
  compromise is low-probability. That reasoning does not survive the
  repository being public. An A1/A3 adversary does not need anyone
  upstream to turn hostile: they read `minecraft.nix:56,84-103`, learn
  that the server is Fabric on whatever Minecraft `LATEST` currently
  resolves to, running sixteen *named* mods with alpha builds permitted
  — including ViaVersion/ViaBackwards/ViaRewind, which deliberately
  widen the accepted protocol range, and Geyser + Floodgate, which add
  the entire Bedrock RakNet stack on 19132 — and check that list
  against published advisories. All of that parsing happens before the
  whitelist applies. The operator, meanwhile, cannot state which
  versions are running, because `LATEST` and `alpha` mean the answer
  changes at each restart with nothing recording it. That asymmetry —
  the attacker can compute the running version and the defender cannot
  — is what moves this out of MEDIUM. It is not a demonstrated RCE, so
  it is not CRITICAL, and the confidence label stays PLAUSIBLE on
  exploitability precisely because I did not go looking for a specific
  advisory.

  Blast radius if it fires: code execution inside the container. The
  container hardening does its job here — `--cap-drop=ALL` with only
  SETUID/SETGID, `--read-only`, `no-new-privileges` — so this is not a
  host-root path by itself. But it is arbitrary code with the `/data`
  volume writable, and per F-P4-05 with unrestricted network egress to
  the LAN, the tailnet and wg0. Note also that `--tmpfs=/tmp` is
  mounted **`exec`** (`:140`), necessarily so for netty and
  DistantHorizons native extraction, which means the read-only rootfs
  does not prevent a compromised mod from writing and executing a
  native payload. The comment at `:136-139` explains why `exec` is
  required and is correct; it just does not note the cost.

  Separately, and worth naming for A3: `viafabric`, `viabackwards` and
  `viarewind` deliberately widen the set of protocol versions the
  server will parse from unauthenticated clients, and Geyser + Floodgate
  add the entire Bedrock (RakNet) protocol on 19132. All of that is
  pre-authentication parsing surface reachable from the open internet
  through vps's DNAT, in front of a whitelist that only applies after
  login. That is not a misconfiguration — it is the point of the
  server — but it is why the mod supply chain matters more here than it
  would on a tailnet-only service.
- **Proposed fix:** pin what can be pinned without breaking the game.
  (a) Tag the image at minimum, digest it ideally:
  `itzg/minecraft-server@sha256:…`. (b) Drop
  `MODRINTH_ALLOWED_VERSION_TYPE = "alpha"` to `release` unless a
  specific mod genuinely needs alpha, in which case name that mod in a
  comment. (c) Consider `MODRINTH_PROJECTS` entries with explicit
  version ids rather than bare slugs — itzg supports
  `slug:version-id` — turning sixteen floating fetches into sixteen
  reviewed ones. (d) If (c) is too much churn, at least record in the
  file that mods are auto-updated from upstream on every start, so the
  next reader knows.
- **Fix risk:** pinning mods means they stop tracking Minecraft version
  bumps, and with `VERSION = "LATEST"` the server version *will* move
  under them, producing a start-time mod/engine mismatch. Pin (b) and
  (a) first — they are nearly free — and treat (c) as coupled to
  pinning `VERSION` as well. Any change here needs a real container
  start and a client connection to verify, not just a build.

### F-P4-05 — a compromised game container reaches the LAN, the whole tailnet, and vps, because containers have unrestricted egress

- **File:** `modules/services/minecraft.nix:47-146`,
  `modules/services/factorio.nix:126-174`,
  `hosts/homelab/configuration.nix:39-44`, `:404-412`;
  cross-ref `hosts/vps/configuration.nix:341`
- **Severity:** HIGH — raised from MEDIUM once F-P4-03 became HIGH. The
  rubric's HIGH band explicitly rates an adversary who has already
  achieved a plausible first step, and F-P4-03 is now that step.
- **Confidence:** CONFIRMED for the network paths; PLAUSIBLE for the
  end-to-end chain, which depends on F-P4-03/A3 landing first
- **Axis:** hardening
- **Reachability:** A3 or A6 — code execution in either game container,
  via a protocol bug or via the unpinned mod channel — then lateral
  movement. Per §4.7 the pivot needs no reconnaissance either: that
  homelab is a subnet router and exit node, that wg0 is
  `10.100.0.1`/`10.100.0.2`, that the LAN is `192.168.1.0/24`, and that
  vps sets `trustedInterfaces = [ "tailscale0" ]` are all published. An
  attacker landing in the container already has the map.
- **Rule:** new-rule candidate.
- **Finding:** all three containers run on docker's default bridge
  (`networks = []`, verified). Docker `MASQUERADE`s
  `-s 172.17.0.0/16 ! -o docker0`, homelab has
  `net.ipv4.ip_forward = 1` and `net.ipv6.conf.all.forwarding = 1`
  (`hosts/homelab/configuration.nix:404-407`), and homelab is a
  tailscale subnet router and exit node (`:409-412`). So a process
  inside a game container can originate traffic to:

  - `192.168.1.0/24` — the whole home LAN, A4's territory in reverse.
  - `100.64.0.0/10` — every tailnet peer, source-NAT'd to homelab's
    own tailscale address, which is exactly the identity the flat ACL
    (F-P0-04) grants everything to.
  - `10.100.0.0/24` over wg0 — vps.

  The last one is the sharp edge. Per threat model §4.4, vps sets
  `trustedInterfaces = [ "tailscale0" ]`, bypassing its packet filter
  wholesale for that interface. A container that can emit tailnet
  traffic as homelab therefore has *unfiltered* access to every port on
  the fleet's internet edge, having started from a Minecraft mod.

  What does hold: traffic from the container back to **homelab's own**
  services arrives on `INPUT` with `-i docker0`, which matches none of
  the `interfaces.tailscale0` / `interfaces.wg0` allow rules, so
  homelab's own sshd, NFS, SMB and jellyfin are correctly closed to the
  container. That asymmetry is worth knowing: the bypass in F-P4-02 is
  inbound-only; outbound is governed by ordinary forwarding, and
  ordinary forwarding is wide open.

  Also confirmed clean and worth recording: `users.groups.docker.members`
  is `[]` on homelab, so there is no A7-style docker-socket path here
  (unlike `PC.nix:313`, which is P1's).
- **Proposed fix:** the general answer is a dedicated docker network
  with egress restrictions, but the cheap and targeted version is a
  `DOCKER-USER` chain rule dropping `172.17.0.0/16 → 100.64.0.0/10`,
  `192.168.1.0/24` and `10.100.0.0/24`, added alongside the existing
  `networking.firewall.extraCommands` pattern the repo already uses on
  vps. `DOCKER-USER` is the one chain docker guarantees it will not
  overwrite, which makes it the right place. Note that the game
  containers need *no* outbound access at all except DNS and HTTPS to
  Modrinth/factorio.com at start — a default-deny egress with two
  exceptions is achievable.
- **Fix risk:** the game containers do legitimately fetch at start
  (mods, DLC, factorio.com auth), so a default-deny that is too tight
  turns into a crash loop on the next restart — and per the comment at
  `factorio.nix:41-47`, this codebase has already lost two days to
  exactly that failure shape, with `docker ps` reporting "Up" the whole
  time. Stage it: add the three LAN/tailnet/wg0 drops first (they
  cannot affect upstream fetches), and only consider full default-deny
  after.

### F-P4-02 — every game port is published by docker, which bypasses the NixOS firewall; the interface scoping in the reference-standard files is inert

- **File:** `modules/services/minecraft.nix:23-36` and `:50-53`;
  `modules/services/factorio.nix:72-79`, `:141`, `:166`;
  `hosts/homelab/configuration.nix:39-44`
- **Severity:** MEDIUM (see the escalation condition below)
- **Confidence:** CONFIRMED for the IPv4 bypass; PLAUSIBLE — untested —
  for whether IPv6 is also affected
- **Axis:** hardening / documentation
- **Reachability:** A4 today — any device on `192.168.1.0/24`: a guest
  phone, an IoT device, a compromised laptop. Latently A1/A2 if the
  IPv6 question below resolves the wrong way, or if `userland-proxy` is
  ever restored, or if docker IPv6 is ever enabled.
- **Rule:** violates the *intent* of the interface-scoping pattern
  described in threat model §2.2 and applied throughout this repo;
  new-rule candidate for `docs/hardening.md`, which has no
  OCI-container section at all.
- **Finding:** the realised unit scripts publish with no host IP:

  ```
  -p 25565:25565        -p 19132:19132/udp        (minecraft-vanilla-plus)
  -p 34197:34197/udp                              (factorio-main)
  -p 34198:34198/udp                              (factorio-new)
  ```

  A bare `-p` binds `0.0.0.0` and makes docker insert
  `nat/PREROUTING → DOCKER` DNAT rules matching `--dst-type LOCAL` on
  *any* interface except `docker0`, plus a matching `ACCEPT` in
  `FORWARD`. The packet is DNAT'd to the container address before the
  routing decision, so it is forwarded, never delivered locally, and
  **never traverses `nixos-fw` in `INPUT`**. Confirmed complementary
  fact from the effective config: `networking.firewall.filterForward =
  false`, so NixOS does not manage `FORWARD` either. The pinned
  nixpkgs module says this in its own option documentation, verbatim:

  > Publishing a port bypasses the NixOS firewall. If the port is not
  > supposed to be shared on the network, make sure to publish the port
  > to localhost.
  > — `nixos/modules/virtualisation/oci-containers.nix:180-183`

  So the eight `networking.firewall.interfaces.{tailscale0,wg0}` port
  entries in `minecraft.nix:23-36` and `factorio.nix:72-79` do not
  scope these ports. They are decorative. The traffic works over
  tailscale0 and wg0 not because those rules allow it but because
  docker allows everything, and it works from the LAN for the same
  reason.

  This is failure mode §7.2 — a control that renders but never takes
  effect — landing on the file that §7.6 and the audit plan both hold
  up as the pattern for everything else to follow. The delta in
  reachable exposure today is modest: homelab has no public IPv4, and
  after the 2026-08-26 pass these four ports are the *only* thing on
  homelab a LAN device can reach at all. The delta in *belief* is not
  modest, and it is the reason this is a finding rather than a note.

  Two things make it worse than a stale comment:

  - **A LAN client reaches the game servers without passing vps's
    rate limiter.** Per §4.6 the raw-table hashlimit on vps
    (`hosts/vps/configuration.nix:415-432`) is the only control in
    front of these servers. It sits on vps. Traffic arriving on
    homelab's LAN NIC has never been near it.
  - **The IPv6 question is unresolved and decides the severity.**
    homelab's LAN NIC carries a globally-routable ISP-delegated IPv6
    address (§2.1). If docker publishes these ports on `::` as well as
    `0.0.0.0`, then minecraft and both factorio servers are directly
    internet-reachable from A1/A2 with no rate limiting and no
    firewall rule capable of stopping them, and this becomes CRITICAL.
    §4.7 sharpens the urgency rather than the rating: the port map, the
    fact that homelab has a public IPv6, the LAN prefix, the wg0
    addressing and the domain are all published, so if the IPv6 path is
    live an adversary needs no scanning to find it — only a `dig` and a
    read of `hosts/homelab/configuration.nix:357-366`.
    My static reading says it does not: the default bridge is
    IPv4-only (`ipv6` is not set in `daemon.settings`, verified), and
    `userland-proxy = false` (`hosts/homelab/configuration.nix:39-41`)
    removes the userland proxy whose dual-stack listener historically
    caused exactly this. Note what that means: **the only thing
    currently keeping these ports off the public internet is a
    performance-motivated docker daemon setting**, not any security
    control, and nothing in the repo records that dependency.
- **Proposed fix:** two parts, both cheap.
  1. Bind the publishes explicitly. `19132`, `34197` and `34198` only
     ever need to arrive over wg0 from vps or over the tailnet, so
     publish to those addresses rather than to `0.0.0.0` — e.g.
     `"10.100.0.2:19132:19132/udp"` plus a second publish on homelab's
     tailscale address, or a single loopback publish fronted by an
     explicit forwarding rule. Same for 25565/tcp.
  2. Either delete the eight now-inert `networking.firewall.interfaces`
     entries, or keep them and replace the comment block with one that
     says what is actually true: that they do not constrain the docker
     publishes and the binding in `ports` is the real control. Leaving
     the current comment in place is the worst option, because it is
     the thing the next service will copy.

  Also add an OCI-container section to `docs/hardening.md` — see
  F-P4-07 — whose first rule is "publish to an address, never to
  `0.0.0.0`".
- **Fix risk:** getting the bind address wrong silently breaks public
  play, and it breaks it in a way that looks like a game problem, not a
  firewall problem. wg0's address on homelab is `10.100.0.2` and is
  static; the tailscale address is not stable in config and would need
  to be referenced carefully or left as a second loopback+forward hop.
  Test from three positions before and after: a LAN host (should go
  from working to refused), a tailnet host, and the public path through
  vps.
- **Owner:** P4, but P3 should confirm the IPv6 test result since it
  is homelab's exposure surface, and P2 should note that vps's rate
  limiter is bypassable from the LAN side.

### F-P4-04 — the factorio account token and game password leave sops into a container-visible volume, and into every snapshot derived from it

- **File:** `modules/services/factorio.nix:13-32` (the jq patch),
  `:100-123`, `:142`, `:167`; `hosts/homelab/configuration.nix:110`,
  `:483-484`; `hosts/homelab/disko.nix:197-199`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the data flow; PLAUSIBLE for the
  resulting file's mode (set by the image's entrypoint, not by us)
- **Axis:** hardening
- **Reachability:** A3/A6 — any code execution inside the factorio
  container reads `/factorio/config/server-settings.json` directly.
  Also anyone who obtains the restic repository plus its password,
  since the secret is now inside the offsite backup outside of sops.
- **Rule:** `docs/hardening.md` "Secrets + swap" is about paging;
  nothing currently covers secrets copied *out* of sops into service
  state. New-rule candidate.
- **Finding:** `mkServerSettingsPatch` (`:13-32`) runs as root in each
  container's `preStart`, `cat`s three sops secrets —
  `factorio_game_password`, `factorio_token`, `factorio_username` — and
  jq-writes them into
  `/srv/factorio/{main,new}/config/server-settings.json`. The comment
  at `:95-97` is right that `token` is "a factorio.com account auth
  token, equally sensitive".

  Factorio genuinely requires those values in that file, so the write
  itself is unavoidable. The consequences of *where* the file lands are
  not:

  1. `/srv/factorio/{main,new}` is bind-mounted into the container at
     `/factorio` (`:142`, `:167`). Anything running in an
     internet-facing container reads the token. Combined with F-P4-03's
     analogue on the factorio side (`UPDATE_MODS_ON_START = "true"` on
     both servers, `:144`, `:170`, mirroring old→new mods on every
     start at `:115-118`), the token is reachable from a mod supply
     chain compromise.
  2. `/srv/factorio/*` is on the impermanence persistence list
     (`factorio.nix:82-85`), so it lives under `/nix/state`, which
     `disko.nix:197-199` puts on `zroot/local/state`, which
     `hosts/homelab/configuration.nix:110` names as one of the two
     datasets the weekly restic job snapshots and pushes to Backblaze.
     Stated precisely, because the first draft of this report overstated
     it: restic encrypts its repository, so the value is **not**
     plaintext at Backblaze. What is true is that the secret has left
     sops' protection and is now covered by two different mechanisms
     instead — plaintext on the homelab root pool and in every
     `zbackup` snapshot derived from it (root-readable), and inside the
     restic repo under the restic password, itself a separate sops
     secret. Rotating the sops entry does not rotate any of those
     copies.
  3. Both servers share the same credentials by explicit decision
     (`:97-99`), so this is one secret in two places.
  4. Under §4.7 the *location* is published too: `factorio.nix:13-32`
     states in a public file exactly which fields land in
     `/factorio/config/server-settings.json`, and the comment at
     `:95-97` helpfully identifies `token` as "a factorio.com account
     auth token, equally sensitive". Anything executing in that
     container knows where to look without exploring.
- **Proposed fix:** the write cannot be avoided, so bound it.
  (a) Restrict the file: have the `preStart` `chmod 0600` the patched
  `server-settings.json` after `mv`, so at least it is not
  world-readable inside the container. (b) Exclude
  `srv/factorio/*/config/server-settings.json` from the restic
  paths, or move the factorio config directory out of the persisted
  subtree and re-render it at start from sops each boot (it already is
  re-rendered — the jq patch is idempotent by design — so the file
  arguably does not need to persist at all). (c) Record in
  `docs/procedures/secrets.md` that these two values exist in plaintext
  on disk by necessity, and what to do if the host is lost.
- **Fix risk:** (b) is the real fix and the riskier one — the patch at
  `:15-16` is guarded by `if [ -f "$settings" ]`, i.e. it only ever
  *edits* a file the image created, and never creates one. Removing
  the file from persistence means a fresh boot has no
  `server-settings.json` until the image regenerates it from its
  template, and the patch would then need to run *after* that, not
  before. Test on a scratch volume, not on `main`.

### F-P4-06 — NFS authenticates nothing; reaching `tailscale0:2049` *is* the authorization

- **File:** `modules/services/nfs.nix:10-16`, `:31`;
  `modules/nixos/nfs-homelab-mounts.nix:9-16`;
  `hosts/homelab/configuration.nix:81-82`
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED
- **Axis:** hardening
- **Reachability:** A5 — a rogue tailnet device. Threat model §5 rates
  A5 low-probability and highest-leverage; §4.4 establishes that the
  ACL granting that reach is flat.
- **Rule:** n/a — this is NFS working as designed. New-rule candidate
  if the repo wants a "state the auth model of every exposed service"
  rule.
- **Finding:** the exports are
  `rw,sync,no_subtree_check,root_squash` with no `sec=`, so the
  effective flavour is `sec=sys` (AUTH_SYS). Under AUTH_SYS the client
  simply *asserts* its uid and gid; the server verifies nothing. The
  repo already knows this and says so plainly at
  `nfs-homelab-mounts.nix:9-12` ("NFS with sec=sys authorizes purely by
  numeric uid/gid").

  `root_squash` is present and correct — and it is also nearly
  irrelevant, because it only maps uid 0. A client that wants group
  `multimedia` access just `setgid(999)`s first; `gid 999` is a
  published constant (`modules/flake/vars.nix:22`) and
  `hosts/homelab/configuration.nix:81-82` grants
  `group:multimedia:rwx` on both `/storage` and `/storage-bulk` by
  POSIX ACL. So any host that can open a TCP connection to
  `100.x:2049` has read-write access to both datasets. There is no
  second factor of any kind — which distinguishes this from the other
  two tailnet services: samba requires a password (F-P4-14 context) and
  jellyfin requires a login.

  §4.7 removes the last soft spot in that path. The export options, the
  `100.64.0.0/10` CIDR, the share paths and — the operative detail —
  `gids.multimedia = 999` are all published, the last of them as a named
  constant in `modules/flake/vars.nix:22` carrying a comment that
  explains NFS authorizes by numeric gid. An A5 device does not have to
  discover which gid to assert; the repo names it.

  This is the concrete instance that makes F-P0-04 bite, and it is
  rated MEDIUM rather than HIGH to avoid double-counting the parent
  finding — the flat ACL is where the fix belongs. The point being
  added here is that NFS contributes *zero* of its own defence, so
  narrowing the ACL is the only lever that exists for `/storage`.

  `no_root_squash` is **not** present anywhere — checked; that would
  have been CRITICAL. `all_squash` is not used either, which is correct
  given the gid-based authorization model.

  The single-port claim at `nfs.nix:18-20` holds where it matters: the
  rendered `/etc/nfs.conf` is `vers3=false, vers4=true`, and only
  `2049/tcp` is opened. But the pinned module still sets
  `services.rpcbind.enable = true` unconditionally
  (`nfsd.nix:145`) and still enables `nfs-mountd`, so rpcbind is
  listening on `111/tcp+udp` on every interface and rpc.mountd on an
  ephemeral port. Neither is reachable — the default-deny firewall
  covers them on every interface including tailscale0 — but "we only
  need one port" is true of the firewall, not of the process list. See
  F-P4-15.
- **Proposed fix:** decision required, and it is really open question
  §8.1. Options: (a) accept, and write down that `/storage` is
  readable and writable by any tailnet device, which is a materially
  stronger statement than "tailnet-only"; (b) narrow the tailnet ACL to
  per-service grants so that only thinkpad and torrent reach 2049 —
  cheap, since only those two mount it (`nfs-homelab-mounts.nix` is
  imported by exactly those hosts); (c) `sec=krb5p`, which is the real
  fix and is almost certainly not worth a Kerberos KDC on a
  single-admin fleet.
  (b) is the good trade here.
- **Fix risk:** (b) is not Nix-managed (§F-P0-04) and breaks in ways no
  build catches. Stage it with console access, and remember the mounts
  are `x-systemd.automount` with `retry=0` — a broken ACL surfaces as
  an empty directory, not an error.
- **Owner:** P4 for the export reading; P8 owns the ACL fix; open
  question §8.1.

### F-P4-07 — `docs/hardening.md` has no container rules at all, and the three containers show it

- **File:** `docs/hardening.md` (absence); `modules/services/minecraft.nix:132-145`,
  `modules/services/factorio.nix:52-60`;
  `hosts/homelab/configuration.nix:39-44`
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening / documentation
- **Reachability:** A3/A6 — depth of defence behind F-P4-03 and
  F-P4-05, not a path of its own.
- **Rule:** new-rule candidate — this finding *is* the rule.
- **Finding:** `docs/hardening.md` covers systemd sandboxing, dedicated
  users, SSH, sops/swap, tailscale sysctls and DNAT rate limiting. It
  says nothing about containers, despite the repo's three most exposed
  workloads being containers. The gaps that follow are consistent
  across all three and none of them is currently anybody's rule to
  enforce:

  - **No `--pids-limit`.** A fork bomb in any container takes the host
    down, and the host is the one holding `zbackup`.
  - **No `--memory` / `--cpus`.** minecraft sets `MEMORY = "4G"`
    (JVM heap only — off-heap, DistantHorizons and the 1 GiB `/tmp`
    tmpfs are all on top), and neither factorio container sets
    anything. There is no cgroup ceiling on any of the three, so
    container OOM pressure is host OOM pressure, and the OOM killer
    picks its own victim among jellyfin, smbd, nfsd and the restic job.
  - **No `userns-remap`** in `virtualisation.docker.daemon.settings`
    (verified — it contains only `userland-proxy = false`). Container
    uid 0 is host uid 0 on the bind mounts, so any escape lands as real
    root rather than as a mapped subuid.
  - **No `--user`** on any container, which is correct here — both
    images perform their own root-then-drop — but it means the
    dedicated-service-user rule in `docs/hardening.md` is satisfied
    only by convention inside an image nobody in this repo controls.
  - **The units themselves have no sandboxing.** Verified:
    `systemd.services.docker-minecraft-vanilla-plus.serviceConfig` is
    `ExecStart`/`ExecStop`/`Restart`/timeouts and nothing else. That is
    inherent to `oci-containers` — the unit is a `docker run` wrapper
    and the isolation lives in the container — but it does mean the
    "Custom `systemd.services` sandboxing" rule is silently
    inapplicable to three units, and `factorio.nix`'s two `preStart`
    scripts (which handle secrets, `factorio.nix:103-123`) run as
    unsandboxed root as a result.

  Credit where due, and this is genuinely above average: all three
  containers carry `--cap-drop=ALL` with a justified, minimal add-back
  list, `--security-opt=no-new-privileges:true`, and a `nosuid,nodev`
  tmpfs; minecraft additionally carries `--read-only`. Docker's default
  seccomp profile is in force (no `--security-opt seccomp=` override).
  The capability sets are correct for what the entrypoints do. The gap
  is the resource and namespace dimension, not the capability one.
- **Proposed fix:** add an "OCI containers" section to
  `docs/hardening.md` with the rules this audit is applying:
  publish to an address never `0.0.0.0` (F-P4-02); pin images by digest
  (F-P4-03); `--cap-drop=ALL` with justified add-backs; `--read-only`
  or a written reason (F-P4-09); `no-new-privileges`; a `--pids-limit`
  and a `--memory` ceiling on anything parsing untrusted input; and a
  note on the egress question (F-P4-05). Then apply the resource
  ceilings.
- **Fix risk:** a `--memory` ceiling below what the JVM actually needs
  turns into an OOM kill loop that looks like a game crash;
  `MEMORY = "4G"` is heap, so the container ceiling wants meaningful
  headroom (6–8 GiB) and should be set from measured RSS, not guessed.
  `--pids-limit` is safe at a generous value (a few thousand).

### F-P4-08 — vps SNATs every forwarded game packet to one address, and the comment says the opposite

- **File:** `hosts/vps/configuration.nix:391-395`;
  affects `modules/services/minecraft.nix`, `modules/services/factorio.nix`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the rule and the comment; PLAUSIBLE for
  the in-game consequences, which depend on server features I did not
  verify are relied upon
- **Axis:** documentation / hardening
- **Reachability:** A1/A3 — an abusive internet client is
  indistinguishable from every other internet client, at the game
  servers and in their logs.
- **Rule:** failure mode §7.5.
- **Finding:** the rule is

  ```
  # SNAT forwarded traffic to our wg0 IP so source IP's are preserved
  iptables -t nat -A POSTROUTING -o wg0 -j SNAT --to-source 10.100.0.1
  ```

  The comment is exactly backwards. SNAT is what *destroys* the source
  address. The rule is nonetheless necessary — without it homelab would
  reply to the client's real address out its own default route and the
  flow would break on asymmetric routing — so this is a comment bug,
  not a config bug. But the consequence is real and lands squarely in
  P4's scope: minecraft and both factorio servers see every internet
  player as `10.100.0.1`. Therefore

  - any per-source-IP ban or throttle inside those servers applies to
    all internet players at once or to none;
  - their logs cannot attribute anything to a client;
  - and, since these ports are invisible to crowdsec by design (§4.6),
    there is now *no* layer anywhere in the stack that can identify an
    individual abusive game client. The hashlimit on vps is the only
    per-source control and it acts before the SNAT, so it works — it
    just cannot ban, only rate-limit.

  §4.7 puts a second edge on that last point: the hashlimit is not only
  the sole control, its exact thresholds are published — `15/minute`
  burst 10 on 25565/tcp, `1000/second` burst 500 on 19132/udp,
  `2000/second` burst 1000 on both factorio ports
  (`hosts/vps/configuration.nix:415-432`). An adversary who wants to
  probe or brute-force rather than flood simply stays underneath them,
  and knows precisely where "underneath" is. That does not make the
  rate limiter worthless — it still does the volumetric job it was
  built for — but it does mean it must never be counted as a control
  against a deliberate, patient attacker, only against A1's noise.

  Note the contrast with jellyfin, where the equivalent problem was
  spotted and solved: `jellyfin.nix:52-71` patches `KnownProxies` for
  precisely this reason, and the comment there gets the reasoning right.
  The game path has the same problem and no equivalent fix, because
  UDP game protocols have no `X-Forwarded-For`.
- **Proposed fix:** correct the comment to say what the rule does and
  why it is required ("SNAT so homelab's replies return via the
  tunnel; note this collapses all internet clients to one source
  address at the game servers"). If per-client attribution is ever
  wanted, the alternative is a route on homelab sending the forwarded
  clients' return traffic back over wg0 instead of SNAT — more
  fragile, and probably not worth it.
- **Fix risk:** none for the comment. Removing the SNAT without adding
  the return route breaks all public game access.
- **Owner:** P2 owns the file; P4 raised it because it changes what the
  game servers can defend themselves with.

### F-P4-09 — factorio's `--read-only` exception cites evidence that its own later fix invalidated

- **File:** `modules/services/factorio.nix:33-60`
- **Severity:** LOW
- **Confidence:** PLAUSIBLE — the reasoning gap is CONFIRMED from the
  file; whether `--read-only` would now work is untested and depends on
  image internals I did not read
- **Axis:** documentation / hardening
- **Reachability:** A3/A6 — depth of defence behind F-P4-03's factorio
  analogue.
- **Rule:** failure mode §7.4 — a justification that outlived the
  condition that produced it.
- **Finding:** the audit brief asked whether this documented exception
  still holds. Partly, and the file's own evidence is stale. The
  comment gives two reasons:

  1. `docker-dlc.sh` writes into the volume as root before the chown —
     and the cited proof is a live crash loop, `mod-list.json.tmp:
     Permission denied`, attributed at `:43-45` to "root lacking
     DAC_OVERRIDE to write into the volume, which is owned by the
     image's baked-in UID 845, not root".
  2. The root-drop step runs `usermod`/`groupmod` against
     `/etc/passwd` and `/etc/group`, which needs a writable rootfs.

  Reason 1 no longer applies. `--cap-add=DAC_OVERRIDE` is now in
  `factorioExtraOptions` (`:56`), which is precisely the capability
  whose absence the quoted crash is attributed to — and it is a
  *capability* problem, not a read-only-rootfs problem, since
  `/factorio` is a writable bind mount either way. The comment
  therefore presents as evidence for "no `--read-only`" a failure that
  `--read-only` did not cause and that the current config already
  fixes.

  Reason 2 does still apply, as far as I can tell — `usermod` rewrites
  `/etc/passwd` in the rootfs, and `--tmpfs=/etc` cannot substitute
  because it would mask the image's baked `/etc` and delete the
  `factorio` user entry. So the conclusion (no `--read-only`) is
  probably right; the argument for it is half wrong, and the case was
  never re-tested after DAC_OVERRIDE was added.

  This matters because the comment is long, confident and cites live
  evidence, which is exactly the shape of comment a future reader will
  not re-examine. Under §4.7 it is read by people other than future
  maintainers too: `factorio.nix:33-60` tells an adversary, before they
  touch anything, that the factorio containers have a writable rootfs
  and hold `CAP_DAC_OVERRIDE` and `CAP_CHOWN` — i.e. which of the two
  game servers is the softer landing spot for F-P4-05's pivot.
- **Proposed fix:** re-test `--read-only` once, now that DAC_OVERRIDE
  is granted, on the `new` server only. If it still fails, replace the
  citation with the actual failure (`usermod` on a read-only `/etc`)
  and drop the stale DAC_OVERRIDE paragraph. If it succeeds, add
  `--read-only`. Either way the comment ends up shorter and true. Worth
  also checking whether the entrypoint skips `usermod` when `PUID`
  already equals the baked 845 — if it does, `--read-only` may be
  reachable by setting `PUID=845`/`PGID=845` explicitly.
- **Fix risk:** the exact failure mode this comment documents — a
  container that `docker ps` reports as "Up" while never serving
  traffic — went unnoticed for two days. Any re-test must verify by
  connecting a client, not by reading `docker ps`, and must be done on
  `factorio-new` (no irreplaceable save) rather than `factorio-main`.

### F-P4-10 — octodns holds a certificate-issuance credential, and the zone it enforces declares no CAA

- **File:** `modules/services/octodns.nix:26-117`, `:132-155`,
  `:161-197`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the config; PLAUSIBLE for impact — the
  Cloudflare token's actual scope is inside sops and was not read
- **Axis:** hardening
- **Reachability:** A6, or root on homelab. The `octodns` system user
  is `isSystemUser` with a `nologin` shell, no SSH keys, no group
  memberships beyond its own, and exactly one unit that ever runs as
  it. There is no path *to* the octodns identity short of root or a
  bug in `octodns-sync` parsing Cloudflare API responses. Reachability
  is genuinely low; the finding is about what it holds, not how easy
  it is to get.
- **Rule:** new-rule candidate.
- **Finding:** this module got the least attention and mostly holds up.
  What is right: a dedicated `octodns:octodns` system user
  (`:161-165`), the token delivered by `EnvironmentFile` from a
  sops template rather than a command line or a checked-in file
  (`:171-177`, `:185`), the template rendered `0400 octodns:octodns`
  (verified: sops-nix resolves `owner` over the default `uid = 0`,
  `modules/sops/templates/default.nix:54-80`), and a sandbox
  (`:187-195`) that matches `docs/hardening.md`'s named list exactly —
  `NoNewPrivileges`, `ProtectSystem = "strict"` with no
  `ReadWritePaths` at all, `ProtectHome`, the three `ProtectKernel*`,
  `ProtectControlGroups`, `RestrictNamespaces`, `PrivateTmp`.

  Three things to raise:

  1. **What the credential is.** A Cloudflare DNS-edit token for
     `skyseekerlabs.net` — a domain named in a public file
     (`modules/flake/vars.nix:18`) pointing at two hardcoded public
     addresses (`octodns.nix:21-22`) — is not only a DNS credential: it
     satisfies ACME DNS-01, and by repointing the apex A/AAAA it
     satisfies HTTP-01 too. Whoever holds it can obtain a publicly-trusted
     certificate for the apex and for `jellyfin.` from essentially any
     CA, and then MITM the one internet-facing service that takes user
     passwords. Nothing in the repo characterises the token this way;
     it reads like a convenience credential.
  2. **No CAA record is declared** (`zoneRecords`, `:26-117`), and this
     is not a "just add it in the console" situation: `octodns-sync
     --doit` (`:186`) runs hourly (`:199-207`) and makes Cloudflare
     match the declared zone, so a hand-added CAA would be deleted on
     the next tick. The declarative zone is the *only* place it can
     live, and it is absent. Adding one is a few lines and directly
     narrows point 1. The same argument applies to
     `v=spf1 -all` / DMARC `p=reject` on a domain that sends no mail.
  3. **The sandbox is thinner than this repo's own better example.**
     `samba-user-provision` in `samba.nix:105-134` — a strictly less
     sensitive unit — additionally carries `ProtectClock`,
     `RestrictRealtime`, `RestrictSUIDSGID`, `LockPersonality`,
     `MemoryDenyWriteExecute`, `SystemCallArchitectures = "native"`.
     octodns conforms to the letter of the hardening rule and is the
     weaker of the two in practice. `PrivateDevices`,
     `ProtectProc`/`ProcSubset`, `RestrictAddressFamilies =
     ["AF_INET" "AF_INET6" "AF_UNIX"]` and
     `CapabilityBoundingSet = []` are all free here.
- **Proposed fix:** (a) declare a CAA record pinning issuance to
  whichever CA vps's caddy uses, plus `iodef`; (b) declare SPF/DMARC
  as null-sender records; (c) bring the unit's sandbox up to
  `samba-user-provision`'s level; (d) confirm out-of-band that the
  Cloudflare token is a *scoped* DNS-edit token for this one zone and
  not a global API key — the `pagerules = false` comment at
  `:143-148` implies it is scoped, which is good, but implication is
  not verification; (e) note in the file what the token is worth.
- **Fix risk:** a CAA record that omits the CA caddy actually uses
  breaks certificate *renewal* silently, weeks later, and the failure
  surfaces as an expired cert on the public site. Check caddy's
  configured issuer first and include both Let's Encrypt and ZeroSSL
  if it can fall back. `--doit` running hourly means any zone mistake
  propagates within the hour with a 300s TTL behind it.

### F-P4-11 — jellyfin's brute-force lockout depends on a `preStart` patch that skips itself on first boot

- **File:** `modules/services/jellyfin.nix:62-71`, `:46-49`
- **Severity:** LOW
- **Confidence:** CONFIRMED for the skip condition; PLAUSIBLE for the
  window's duration
- **Axis:** hardening
- **Reachability:** A1 — internet credential stuffing against
  `jellyfin.<domain>`, which reaches jellyfin through vps's
  caddy+anubis over wg0.
- **Rule:** failure mode §7.3 — is the control guaranteed up before the
  thing it protects, or merely usually?
- **Finding:** jellyfin is the one service in this part whose own
  authentication is the last line between the internet and personal
  data. The chain in front of it is anubis's proof-of-work and caddy;
  crowdsec watches caddy's logs but has no jellyfin-specific parser
  configured. So jellyfin's per-IP failed-login lockout matters, and
  `jellyfin.nix:52-61` correctly identifies that it is useless unless
  `KnownProxies` is set, since otherwise every request looks like it
  came from the tunnel.

  The patch that sets it is guarded:

  ```
  if [ -f "$networkXml" ]; then
    xmlstarlet ed -L … "$networkXml"
  fi
  ```

  On a host where `network.xml` does not yet exist — first ever boot,
  or a rebuild-from-scratch before jellyfin has written its config —
  the patch is a no-op, jellyfin then *creates* `network.xml` with an
  empty `KnownProxies`, and the lockout is inert until the next
  restart. The comment at `:57-59` claims the patch "self-heals if the
  dashboard ever clears it", which is true for the clearing case and
  false for the creation case. `/srv/jellyfin/config` is persisted
  (`:108-127`), so in practice the window is one boot on a fresh
  install — small, but it is precisely the window in which the
  admin password is also newest.

  §4.7 note: jellyfin is the one service in this part with a
  password-authenticated login exposed to the internet, and its exact
  version is derivable from the public flake pin (10.11.11 at the
  current lock). A credential-stuffer or a CVE-matcher reads it off the
  repo rather than off a banner. That does not change this finding's
  rating — the lockout gap is the same size either way — but it is why
  keeping the nixpkgs pin moving matters more here than on a
  tailnet-only service.

  Also noted while checking the unit, both minor and both fine to
  leave: `ProtectSystem` is `true` rather than `"strict"` — set
  directly by the upstream module at
  `nixos/modules/services/misc/jellyfin.nix:466`, so overriding needs
  `mkForce`, and jellyfin runs unprivileged so the practical delta is
  small. And the `render` group grant (`:49`) is *correctly* bounded:
  `DeviceAllow` is `["/dev/dri/renderD128 rw", "/dev/dri/renderD129 rw"]`
  (verified in the effective config), so group `render` cannot reach
  any other device node even though the grant is group-wide. That is
  the right shape and answers the brief's question about it.
- **Proposed fix:** drop the `-f` guard's silent branch — either create
  a minimal `network.xml` when absent, or `ExecStartPost` the patch
  instead of `preStart` so it runs against the file jellyfin just
  wrote, or simply log loudly on the skip so the condition is visible.
- **Fix risk:** creating `network.xml` from scratch risks writing a
  document jellyfin then rejects or overwrites; the `ExecStartPost`
  variant risks racing jellyfin's own first write. The logging variant
  is free and probably sufficient given the window is one boot.

### F-P4-13 — `factorio-new`'s floating `stable` tag does not do the thing it is documented to do

- **File:** `modules/services/factorio.nix:129-140`, `:149-159`;
  `hosts/homelab/configuration.nix:482`
- **Severity:** LOW — raised from INFO under §4.7; the documentation
  half is still INFO-grade, the version-disclosure half is not
- **Confidence:** CONFIRMED
- **Axis:** documentation / needed-used / hardening
- **Reachability:** A3 — an internet client reading the repo to
  determine which Factorio engine it is talking to.
- **Rule:** failure mode §7.5.
- **Finding:** the brief flagged `factorio.nix:152`'s floating `stable`
  tag as a possible supply-chain path. It is a floating tag, and it is
  a documented decision (`:149-156`) — but the documented *behaviour*
  does not happen. The comment says the server will "pick up engine
  updates automatically on restart". It will not:
  `virtualisation.oci-containers.containers.<n>.pull` defaults to
  `"missing"` in the pinned module (`oci-containers.nix:315-328`,
  verified, and visible as `--pull missing` in the realised argv), and
  `/var/lib/docker` is on the impermanence persistence list
  (`hosts/homelab/configuration.nix:482`, whose comment says so
  explicitly: "avoids re-pulling minecraft/factorio images every
  boot"). Once `factoriotools/factorio:stable` is in the local image
  store it stays there until something removes it.

  So the security exposure from the floating tag is smaller than it
  looks — it is a one-time fetch, not a recurring one — and the stated
  benefit is not being delivered. Both halves are worth knowing. The
  same is true of `minecraft.nix:51`'s untagged image (F-P4-03), where
  the recurring channel is the Modrinth mod fetch, not the image.

  Note the asymmetry this creates: `factorio-main` is pinned to
  `2.1.14` with a detailed justification (`:129-139`), and that pin is
  a *tag*, not a digest — Docker Hub tags are mutable, so a
  republished `2.1.14` would be picked up on any host that has to pull
  it fresh. Neither container is pinned in the sense that would
  actually resist A6.

  **What §4.7 changes here.** The comment at `:129-139` does not merely
  pin a version, it publishes one, together with the reasoning: that
  `2.1.14` is on the *experimental* line, that it was chosen for save
  compatibility rather than because it is the maintained release, and
  that reverting is blocked by a gap in the snapshot history. An A3
  client reading that knows the exact engine build behind 34197 and
  knows it is not the branch upstream patches first. For `factorio-new`
  the disclosure is weaker but the *control* is worse — `stable` means
  the running build is whatever upstream last called stable at the
  moment the image happened to be fetched, which neither the operator
  nor the config records anywhere. Same defender-blind /
  attacker-informed asymmetry as F-P4-03, one notch smaller because
  Factorio's pre-authentication surface is far narrower than modded
  Minecraft's. Raised to LOW on that basis; it would be MEDIUM if the
  factorio servers carried anything like minecraft's mod surface, and
  per F-P4-03's `UPDATE_MODS_ON_START` paragraph that is not guaranteed
  to stay true.
- **Proposed fix:** correct the comment, and either set
  `pull = "newer"` on `factorio-new` if automatic engine updates are
  genuinely wanted (accepting the supply-chain trade explicitly), or
  say plainly that the tag floats only across image-store loss. Pin
  `factorio-main` by digest since its whole point is version stability.
- **Fix risk:** `pull = "newer"` reintroduces a real auto-update path
  on an internet-exposed container and makes every restart dependent on
  Docker Hub reachability. Digest-pinning `factorio-main` is safe but
  means a manual step for every future upgrade.

### F-P4-12 — dead config: UDP 25565 is opened on two interfaces and nothing has ever listened on it

- **File:** `modules/services/minecraft.nix:26-29`, `:33-36`, `:50-53`;
  `hosts/vps/configuration.nix:368-373`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** none.
- **Rule:** failure mode §7.4.
- **Finding:** `minecraft.nix` opens `25565/udp` on both `tailscale0`
  and `wg0`. Minecraft Java Edition is TCP-only; Bedrock arrives on
  19132/udp via Geyser. Confirmed from both ends: the container
  publishes `25565:25565` (TCP, the docker default) and
  `19132:19132/udp` — no UDP 25565 — and vps forwards 25565 with
  `proto = "tcp"` (`hosts/vps/configuration.nix:370-372`). Nothing
  binds it, nothing forwards it, nothing needs it. Harmless, and
  exactly the kind of accretion §7.4 is about: a rule whose reason
  never existed rather than one that expired.

  Per F-P4-02 all four of these interface entries are inert anyway, so
  this one is doubly dead. If F-P4-02's fix keeps the rules as
  documentation of intent, drop the UDP 25565 pair while doing it.
- **Proposed fix:** delete `25565` from
  `interfaces.tailscale0.allowedUDPPorts` and
  `interfaces.wg0.allowedUDPPorts`, keeping `19132` in both.
- **Fix risk:** none.

### F-P4-14 — samba's `hosts allow`/`hosts deny` pair is IPv4-only, in a tailnet that is dual-stack

- **File:** `modules/services/samba.nix:50-52`, `:177-181`
- **Severity:** INFO
- **Confidence:** CONFIRMED for the rendered config; PLAUSIBLE for
  client behaviour
- **Axis:** hardening / documentation
- **Reachability:** none today — it fails closed.
- **Rule:** failure mode §7.1 in miniature.
- **Finding:** samba is the best-hardened service in this part and this
  is the only thing worth raising about it. The rendered
  `/etc/samba/smb.conf` (verified) contains
  `hosts allow=100.64.0.0/10` and `hosts deny=0.0.0.0/0`. Both are
  IPv4 literals. Tailscale assigns every node an address in
  `fd7a:115c:a1e0::/48` as well as a CGNAT-range IPv4, and `smbd` binds
  `[::]:445` (no `interfaces`/`bind interfaces only` is set). So:

  - **Today it fails closed.** Samba's rule is that a non-empty
    `hosts allow` denies anything not listed, so a tailnet peer
    connecting to homelab's IPv6 tailnet address is *rejected*. That is
    more restrictive than intended, not less. It also means the Android
    client must be reaching homelab over IPv4 — worth knowing, because
    if it ever prefers IPv6 the share stops working for a reason the
    firewall rules will not explain.
  - **The latent footgun** is `hosts deny=0.0.0.0/0`, which is doing
    nothing (the allow list already excludes everything else) and which
    covers no IPv6 at all. A future reader who relaxes or removes
    `hosts allow`, trusting the deny-all, would open samba to every
    IPv6 source that can reach port 445 — and port 445 is only closed
    on other interfaces by the firewall rule at `:181`, which is
    real and effective, so this stays theoretical. But the comment at
    `:49-51` calls the pair "defense-in-depth", and half of it is not
    defending anything.
- **Proposed fix:** add the tailnet IPv6 prefix to `hosts allow`
  (`100.64.0.0/10 fd7a:115c:a1e0::/48`) so the intent is dual-stack,
  and either add `::/0` to `hosts deny` or drop `hosts deny` entirely
  as redundant. Optionally add `interfaces = tailscale0` +
  `bind interfaces only = yes` so smbd stops binding the LAN NIC at all.
- **Fix risk:** `bind interfaces only` makes smbd fail to start if
  `tailscale0` does not exist yet at boot — an ordering dependency of
  exactly the §7.3 kind, and probably not worth it given the firewall
  rule already works.

### F-P4-15 — needed/used sweep: leftovers

- **File:** several, listed below
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used / documentation
- **Reachability:** none.
- **Rule:** failure mode §7.4.
- **Finding:** the brief asked for a needed/used pass over every port,
  volume, capability, group and secret. The substantive results are
  F-P4-12 and F-P4-13. The remainder:

  - **Both factorio servers are genuinely in use.** `old.factorio`
    (34197) and `new.factorio` (34198) are each DNAT'd on vps
    (`hosts/vps/configuration.nix:379-388`), each rate-limited
    (`:425-432`), each have A and SRV records
    (`octodns.nix:76-116`), and they exist for a stated reason
    (`factorio.nix:149-156`: a fresh world at current stable, versus a
    save locked to 2.1.14). Not dead config. The **bare `factorio` A
    record** (`octodns.nix:69-75`) is a compatibility alias for
    `old.factorio` and says so; it duplicates a record and could go,
    but it costs nothing.
  - **All other declared ports are used.** 25565/tcp, 19132/udp,
    34197/udp, 34198/udp all forwarded; 8096/tcp reached over both
    tailscale0 (direct) and wg0 (anubis); 445/tcp by the Android
    client; 2049/tcp by both laptops' automounts; 3923/tcp on the ISO.
  - **`rpcbind` and `nfs-mountd` run with NFSv3 disabled.** The pinned
    module enables both unconditionally (`nfsd.nix:145,163`). Neither
    is reachable through the firewall on any interface, but rpcbind on
    111/udp is a classic reflector and it is running for no reason.
    Not fixable from `nfs.nix` without overriding the module.
  - **The raw `cloudflare_octodns_token` secret is granted to the
    octodns user** (`octodns.nix:167-170`) although only the rendered
    template is consumed (`:185`). sops-nix writes the raw file
    regardless, so the file exists either way; the `owner`/`group`
    grant is the removable part. Marginal.
  - **`/var/lib/nfs` is not persisted** on an impermanence host, so
    NFSv4's `v4recovery` state is recreated empty every boot
    (`nfsd.nix` `preStart` does the mkdir). Correctness, not security:
    clients cannot reclaim locks across a server reboot. Flagging in
    case P3 wants it.
  - **The world seed is public.** `minecraft.nix:71` commits
    `SEED = "3522075773609978693"` to a public repository. Not a
    security finding under this threat model — no asset in §1 is
    touched — but a §4.7 consequence worth stating once, because it is
    almost certainly not a decision anyone made: anyone can generate
    the identical world offline and locate every structure, slime chunk
    and ore vein on a server whose whole point is survival play.
  - **`modules/services/README.md` does not exist**, though
    `docs/procedures/new-service.md` step 6's surrounding text points
    at it as the service inventory and its "Gotchas" section. Several
    of the gotchas found in this audit (the docker port-publishing
    bypass above all) are exactly what that file is for.
- **Proposed fix:** low priority. Create `modules/services/README.md`
  with the inventory the runbook already promises, and put F-P4-02's
  lesson in it.
- **Fix risk:** none.

---

## 3. Comparison table — the reference standard against the rest

Read the first column as "does the firewall scoping actually
constrain the traffic", not "is a scoping rule written down". That
distinction is the whole of F-P4-02.

| Service | Firewall scoping | Capabilities | Read-only rootfs | no-new-privs | Dedicated user | systemd sandboxing | Image / version pinning |
|---|---|---|---|---|---|---|---|
| **minecraft** (container) | ⚠️ rules written, **inert** — docker DNAT bypasses `INPUT`; open on all IPv4 incl. LAN (F-P4-02) | ✅ `--cap-drop=ALL` + SETUID/SETGID, justified | ✅ `--read-only`, but `/tmp` is `exec` by necessity | ✅ | ⚠️ image-internal drop only; no `--user`, no `userns-remap` | ❌ n/a — unit is a `docker run` wrapper, no hardening | ❌ **untagged** (`:latest`) + 16 unpinned Modrinth mods, alpha allowed (F-P4-03) |
| **factorio-main** (container) | ⚠️ same as above | ✅ `--cap-drop=ALL` + CHOWN/DAC_OVERRIDE/SETUID/SETGID | ❌ documented exception; evidence partly stale, never re-tested (F-P4-09) | ✅ | ⚠️ same as above | ❌ same; plus an unsandboxed root `preStart` handling secrets | ❌ tag `2.1.14`, mutable, not a digest, publicly declared as the experimental line + `UPDATE_MODS_ON_START` (F-P4-13, F-P4-03) |
| **factorio-new** (container) | ⚠️ same as above | ✅ same | ❌ same | ✅ | ⚠️ same | ❌ same | ❌ floating `stable`, and it does not float; + `UPDATE_MODS_ON_START` and a mod mirror from `main` (F-P4-13, F-P4-03) |
| **jellyfin** | ✅ real — tailscale0 + wg0, enforced in `INPUT` | ✅ `CapabilityBoundingSet=[""]`; `render` grant bounded by `DeviceAllow` | ⚠️ `ProtectSystem=true` (upstream), not `"strict"` | ✅ | ✅ `jellyfin`, group `multimedia` | ✅ full upstream stack incl. `SystemCallFilter`, `PrivateUsers`, `ProtectProc` | ✅ nixpkgs pin (10.11.11) |
| **samba** | ✅ real — tailscale0:445, plus `hosts allow` (IPv4-only, F-P4-14) | ➖ n/a (not containerised) | ➖ n/a | ✅ | ⚠️ `smbd` is root — documented and genuinely unavoidable; `android-smb` is a proper auth-only user | ⚠️ deliberate partial set on `smbd`, with a stated reason; `samba-user-provision` gets the **full** stack | ✅ nixpkgs pin (4.23.10) |
| **nfs** | ✅ real — tailscale0:2049 only; `root_squash`; but `sec=sys` authenticates nothing (F-P4-06) | ➖ n/a | ➖ n/a | ➖ kernel server | ➖ kernel server, root by nature | ➖ nothing meaningful to sandbox | ✅ nixpkgs pin |
| **copyparty-iso** | ❌ **host-wide** `allowedTCPPorts = [3923]`, any network the ISO boots onto (F-P4-01) | ➖ n/a | ➖ | ✅ | ✅ `copyparty` user | ⚠️ strong upstream stack, **nullified** by `BindPaths=["/"]` from the `/` volume | ✅ flake-input pin (1.20.20) |
| **octodns** | ➖ no listener | ➖ n/a | ➖ | ✅ | ✅ `octodns:octodns` | ⚠️ meets `docs/hardening.md`'s list; thinner than this repo's own `samba-user-provision` (F-P4-10) | ✅ `pkgs-unstable` pin |

Legend: ✅ meets the standard · ⚠️ partial, or written-but-not-effective · ❌ gap · ➖ not applicable

Every cell in this table is public (§4.7). Read the ❌s in the last
column as things an internet client can look up about the two services
it is allowed to speak to, not merely as maintenance debt.

**What the table says.** The 2026-08-26 pass did *not* leave the other
services behind — jellyfin, samba and nfs all carry the
interface-scoped pattern and all three actually work. The gap runs the
other way: the two services held up as the reference are the two whose
firewall scoping does not function, because containers were never in
scope of the mental model the pass was built on. Their *container*
hardening is genuinely good — better than most homelabs — and their
*network* scoping is decorative. Meanwhile the two services nobody
looked at, copyparty-iso and octodns, are the two with no
interface-scoping story at all: one because it is deliberately
host-wide, one because it has no listener.

**What §4.7 changes about the table.** The rightmost column stops being
a hygiene metric and becomes an exposure one. The three ⚠️/❌ entries
there all sit on the two services reachable from the open internet, and
the repository publishes both the pin and the reasoning behind it —
so the version an A3 client is talking to is a lookup, not a probe, on
all three containers. That is why F-P4-03 is the HIGH in this part
rather than a supply-chain footnote, and it is the one column where the
containerised services are worse than every native service beside them.

---

## 4. Checked and clean

Examined, and found correct. Recorded so a later pass does not re-derive it.

**Container hardening that is genuinely right.** All three containers:
`--cap-drop=ALL` with an add-back list that matches what the
entrypoints actually do (SETUID/SETGID for gosu on minecraft;
CHOWN/DAC_OVERRIDE/SETUID/SETGID for factoriotools' root-then-drop);
`--security-opt=no-new-privileges:true`; `nosuid,nodev` on the tmpfs;
`privileged = false`; docker's default seccomp profile left in place.
`ENABLE_RCON = "FALSE"` on minecraft (`:110`) with a comment explaining
it is belt-and-suspenders against a future port addition — correct,
and the itzg image's historical weak-default-password RCON is a real
thing to have guarded against. `users.groups.docker.members` is `[]` on
homelab, so there is no A7 docker-socket path on this host.

**samba.** Close to exemplary for the constraints. `security = user`,
`map to guest = never`, `invalid users = root`, `server min protocol =
SMB3`, `server signing = mandatory`, `smb encrypt = mandatory`,
`ntlm auth = ntlmv2-only`. Printing/spoolss fully disabled, shrinking
the RPC surface. `nmbd` and `winbindd` off, so 137/138/139 never open.
`wide links = false` + `follow symlinks = false` on both shares, which
genuinely prevents a symlink escaping the share root. `valid users =
android-smb` on both shares with a `force group` and 0660/0770 masks.
The rendered `smb.conf` contains no `[homes]` and no printer shares —
verified, not assumed. `android-smb` is a real dedicated auth-only
principal: `isSystemUser`, no shell, no SSH key, group `multimedia`
only. The `NoNewPrivileges = true` on root-running `smbd` is safe and
the comment's reasoning is right — NNP constrains `execve`, not
`setresuid`, so smbd's per-operation identity switching is unaffected.
The declarative password provisioning (`:99-143`) is idempotent,
correctly ordered `before = ["samba-smbd.service"]`, wired to
`restartUnits` on the secret, and carries the full sandbox stack with
`ReadWritePaths` scoped to four real paths. `/var/lib/samba` is
persisted, without which the whole mechanism would silently reset each
boot.

**nfs.** `root_squash` present; `no_root_squash` absent everywhere —
checked explicitly, it would have been CRITICAL. `no_subtree_check` is
the correct modern choice. The `100.64.0.0/10` export CIDR is real
defence-in-depth on top of interface scoping. NFSv4-only is confirmed
in the rendered `/etc/nfs.conf`, and the single-port firewall claim is
accurate. The gid-pinning discipline (`vars.gids.multimedia = 999`,
pinned in `jellyfin.nix:77-80` with a comment explaining that NFS
clients authorize by numeric gid so drift breaks access) is the right
call and is documented at both ends.

**jellyfin.** The `render` group grant is bounded by an explicit
`DeviceAllow` allowlist, so it cannot reach devices beyond the two
render nodes — verified in the effective `serviceConfig`, and this was
the specific question the brief asked. The upstream sandbox is strong
and untouched: `CapabilityBoundingSet=[""]`, `PrivateUsers`,
`SystemCallFilter=["@system-service" "~@privileged"]`,
`RestrictAddressFamilies`, `ProtectProc=invisible`, `ProcSubset=pid`,
`UMask=0077`. `openFirewall` is left at its module default of `false`
(verified in the pinned module) and the comment explaining exactly
which ports were dropped and why — including the observation that
UDP 8096 was never a real jellyfin port — is accurate against
jellyfin's own documentation. The `KnownProxies` patch is the right fix
for the right reason; see F-P4-11 for its one edge.

**octodns.** Dedicated user, sops template rather than a
command-line or checked-in credential, `ProtectSystem = "strict"` with
no `ReadWritePaths` at all, and a zone that is fully generated from Nix
rather than checked-in YAML. The IPv4-only decision for the
minecraft/factorio records (`:46-57`) is correct and well-reasoned:
publishing AAAA for hosts whose ports are only DNAT'd over IPv4 would
break any client preferring IPv6, which the comment says was confirmed
live with a Bedrock client. That is the right instinct and the right
level of evidence.

**minecraft-geyser-config.** Twelve lines setting one flag,
`above-bedrock-nether-building: true`, mounted read-only from the Nix
store (`:117`, `--mount … :ro` verified in the argv). No security
surface: no auth settings, no listener config, no credentials. The
upstream issue is cited. Nothing to report.

**Secrets that are correctly kept out of a public repo.** The minecraft
whitelist and ops list are sops-rendered into an `--env-file` rather
than written into the module (`minecraft.nix:9-13,112`), and the
factorio game password, account token and username likewise
(`factorio.nix:100-102`). A whitelist is not really a secret — the op
list of a public Minecraft server is discoverable in-game — but under
§4.7 the instinct is right, and it is worth noting that this repo
already reaches for sops in the marginal cases rather than only the
obvious ones. Verified against the threat model's own history scan
(§4.7): the only credential-shaped string ever committed anywhere in
this repo's history is `octodns.nix`'s `env/CLOUDFLARE_TOKEN`
placeholder, which is an indirection, not a value.

**Threat-model claims that held up on inspection.** §2 is right that
`isoimage` listens on 3923 host-wide. §2.2's list of interface-scoped
services is accurate for jellyfin/samba/nfs and, in intent but not
effect, for minecraft/factorio. §4.6 is right that the game ports have
only volumetric protection — and F-P4-08 sharpens it: they do not even
have per-client attribution.

---

## 5. Summary

**15 findings: 3 HIGH, 3 MEDIUM, 6 LOW, 3 INFO.**

By axis: 9 hardening, 3 documentation (F-P4-08, F-P4-09, and the
documentation halves of F-P4-02 and F-P4-13), 3 needed-used.

Movement from the pre-§4.7 draft: F-P4-03 MEDIUM → HIGH,
F-P4-05 MEDIUM → HIGH, F-P4-13 INFO → LOW. Nothing moved down. One
substantive correction independent of §4.7: F-P4-04's first draft said
the factorio secrets sit in plaintext at Backblaze — restic encrypts
its repository, so that was wrong and is now stated accurately.

The three that matter most:

1. **F-P4-03** (HIGH) — both game servers pull unpinned third-party
   code on every start (sixteen named Modrinth mods with alpha builds
   allowed on minecraft; `UPDATE_MODS_ON_START` on both factorio
   servers, mirrored between them), and because the repo is public an
   A1/A3 client can enumerate that exact surface and match it against
   advisories without probing — while the operator cannot say what
   versions are running.
2. **F-P4-02** (MEDIUM, conditionally CRITICAL) — docker publishes all
   four game ports on `0.0.0.0`, so the interface-scoped firewall rules
   in the repo's reference-standard files constrain nothing. Verify the
   IPv6 case before anything else in this report; it is the one open
   question that could reclassify a finding to CRITICAL.
3. **F-P4-01** (HIGH) — the recovery ISO grants anonymous
   read/write/delete over `/` on a host-wide port, with literally zero
   accounts defined, and the config saying so is public.

Remediation order differs slightly from severity order, because two of
these are cheap and one is a decision: pin minecraft's image and drop
`alpha` (hours, F-P4-03); bind the container publishes to addresses
(hours, F-P4-02); add the three `DOCKER-USER` egress drops (hours,
F-P4-05); then take the copyparty decision (F-P4-01) and the NFS/ACL
decision (F-P4-06), both of which need the user rather than an agent.

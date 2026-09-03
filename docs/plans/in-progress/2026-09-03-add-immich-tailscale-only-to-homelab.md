---
slug: add-immich-tailscale-only-to-homelab
created: 2026-09-03
status: in-progress
frozen: false
---

# Add Immich (Tailscale-only) to homelab

## Original plan

Add Immich (self-hosted photo/video backup) to `homelab`, reachable only
over the tailnet — no public exposure via vps's Caddy+Anubis proxy, unlike
jellyfin. Research first whether restricting it to Tailscale actually
breaks any real functionality (mobile background backup, sharing, etc.)
before committing to the architecture.

## State

**2026-09-03, research and design done, no code written yet.** Confirmed
the pinned nixpkgs-stable (26.05) ships a native `services.immich` module
— no oci-containers/docker-compose needed, matching the jellyfin precedent
already on this host. Confirmed via GitHub research that "Tailscale-only"
does not break Immich's own functionality; the one real rough edge found
(Android DNS flakiness) is a general Tailscale-on-Android issue, not
Immich-specific (F1). D1 and D2 are answered: media lives at
`/storage/immich` on the existing jellyfin dataset (D1b), and losing
public share links is *not* accepted long-term — a follow-up is expected
once v1 is live (D2). D3 (GPU-accelerated ML) was investigated (F2) and
is real but costly (multi-hour from-source build, Nvidia/CUDA only, no
OpenVINO path) — deferred, CPU-only for v1, carried into
`2026-09-03-gpu-accelerate-immich-machine-learning-cuda.md` as its own
follow-up.

**2026-09-03, implementation landed.** `modules/services/immich.nix`
drafted and registered on `homelab` in `modules/flake/hosts.nix`, mirroring
jellyfin's shape (bind broad, restrict at the firewall to `tailscale0`
only, no `wg0` rule). Full `verify-ladder` passes (nixfmt, `nix flake
check`, targeted builds for all 5 hosts, no new statix/deadnix issues).
`/simplify`'s 4 parallel review agents (reuse/simplification/efficiency/
altitude) all came back clean, no fixes needed. `security` subagent found
two things: F3 (NFS AUTH_SYS lets a client already holding root
impersonate immich's uid, bypassing the 0700 mediaLocation mode) —
accepted, since it's the same trust boundary `nfs-homelab-mounts.nix`
already documents for the whole `/storage` export, not something this
change introduces; and F4 (the new persistence entry for
`/var/lib/postgresql` used impermanence's root:root/0755 default instead
of explicit ownership) — fixed, now explicit `user`/`group = "postgres"`
matching jellyfin.nix's convention. Only remaining open item is the D2
follow-up (a path to share outside the tailnet), which is deliberately
deferred until v1 has been live for a while.

## Progress
- [x] D1 decided (mediaLocation dataset + NFS exposure) — picked (b), subdir of existing /storage
- [x] D2 decided (public share links tradeoff) — user wants a later path, tracked as follow-up
- [x] D3 decided (GPU acceleration for ML, v1 or later) — deferred to follow-up plan, CPU-only for v1
- [x] modules/services/immich.nix drafted (mirrors modules/services/jellyfin.nix shape)
- ~~[ ] new zdata dataset created + wired into myZrepl/myHealthAlerts/restic (if D1 picks a new dataset)~~
  moot — D1 picked (b), no new dataset
- ~~[ ] G1's mount-ordering race addressed before first deploy~~ moot — see G1 strikethrough
- [x] `nixos-rebuild build --flake .#homelab` passes (also full verify-ladder: nixfmt, flake check, statix/deadnix, all 5 hosts)
- [x] `/simplify` run — 4 agents (reuse/simplification/efficiency/altitude), all clean, no fixes needed
- [x] `security` subagent run — F3 (NFS AUTH_SYS trust boundary, inherited not introduced) accepted, F4 (persistence entry missing explicit ownership) fixed
- [ ] follow-up plan opened for D2 (path to share outside the tailnet) once v1 is live

## Decisions (D)

### D1 -- where does `mediaLocation` live, and is it OK for it to be NFS-exposed?
`/storage` and `/storage-bulk` (zdata/storage/{storage,storage-bulk}) are
jellyfin's existing datasets, already zrepl+restic backed up, but also
NFS-exported tailnet-wide to anything holding the `multimedia` gid
(`modules/services/nfs.nix` exports the whole `/storage` tree, not a
subtree — see `modules/nixos/nfs-homelab-mounts.nix`, which is how
`torrent`/`thinkpad` get read/write on it via lilijoy's own account).
Immich's media is personal photos, a different sensitivity class than a
shared movie library. Two real options:
  - **(a)** New dedicated dataset `zdata/storage/immich` (`mountpoint
    -o /storage/immich`, own `immich:immich` 0700 perms — matches what
    the nixpkgs module already does by default), *not* covered by the
    NFS export, added to `myZrepl.local.datasets` +
    `myHealthAlerts.backupStaleness` + the weekly restic
    `backupPrepareCommand` dataset list (same pattern as the existing
    three). Needs a live `zfs create` (see `docs/backups.md`'s
    "`root_fs` does not create itself" section for the precedent/command
    shape) plus a matching entry in `hosts/homelab/disko.nix` for
    reinstall reproducibility.
  - **(b)** Reuse `/storage/immich` as a subdir of the existing
    `zdata/storage/storage` dataset — no new dataset, no disko/zrepl/restic
    wiring, but it inherits the NFS export and the `multimedia` gid's
    access.
  (a) is more setup for meaningfully better confidentiality; (b) is
  fastest. Not answered yet.


**ANSWERED 2026-09-03:** user picked (b): reuse /storage/immich as a subdir of the existing zdata/storage/storage dataset -- no new dataset, no disko/zrepl/restic wiring; accepts NFS export + multimedia-gid exposure.

### D2 -- is losing public share links an acceptable tradeoff?
Immich lets you generate unauthenticated public share links for photos/
albums. Tailscale-only means those links only resolve for someone already
on the tailnet — sharing with anyone outside it (family, friends) won't
work unless a separate path is added later (e.g. Tailscale Funnel scoped
to just the share-link route, or an Anubis-fronted proxy like jellyfin's).
This is a real feature loss, not a bug — needs an explicit yes before
building tailscale-only as final rather than a stepping stone. Not
answered yet.


**ANSWERED 2026-09-03:** user wants a path to share outside the tailnet later -- not accepted as a permanent loss. Track as expected near-term follow-up work (e.g. scoped Tailscale Funnel or a jellyfin-style Anubis proxy for just the share-link route), not just an accepted risk in docs/accepted-risks.md.

### D3 -- GPU-accelerated ML (face detection / CLIP smart search) at v1?
homelab already has both an Nvidia GTX 1050 Mobile (NVENC/NVDEC, used by
jellyfin) and an Intel HD 630 iGPU (VAAPI/QSV) passed through. Immich's ML
worker can use either (CUDA or OpenVINO) but the pinned nixpkgs
`immich-machine-learning` package didn't show an obvious build-time
acceleration variant on a first look (unlike jellyfin, which gets hardware
accel for free via `hardwareAcceleration.device`) — needs a closer look at
whether the nixpkgs package exposes a CUDA/OpenVINO passthru or whether
it'd need a custom override. CPU-only ML works out of the box and is
probably fine for a personal library's initial size. Recommend deferring
GPU accel to a follow-up rather than blocking v1 on it, but flagging as a
decision rather than assuming. Not answered yet.


**DISCUSSED 2026-09-03:** user asked to investigate GPU accel now, before v1. Investigated (see F2): it is real and documented (CUDA/Nvidia only, no OpenVINO path in nixpkgs' onnxruntime), but is a multi-hour from-source build with no binary cache, needing a global onnxruntime overlay override, a test patch, and manual device/LD_LIBRARY_PATH wiring beyond what accelerationDevices alone provides -- and it has to be rebuilt from source again on every relevant nixpkgs bump. Recommendation given to user: ship CPU-only for v1, revisit CUDA as a follow-up once the base service is live and its real ML latency is known. Awaiting final call.


**DEFERRED 2026-09-03:** user picked CPU-only for v1 (F2's cost -- multi-hour from-source CUDA-onnxruntime build, no OpenVINO path, no binary cache, rebuild on every relevant nixpkgs bump -- outweighs building it in speculatively). Spun into its own todo plan for later.


**CARRIED 2026-09-03:** see `2026-09-03-gpu-accelerate-immich-machine-learning-cuda.md`

## Gotchas (G)

### G1 -- ZFS dataset mount-ordering race, if D1 picks a new dataset
The nixpkgs `services.immich` module's own `systemd.tmpfiles.settings`
creates `mediaLocation` (mode 0700 immich:immich) on every boot. If
`mediaLocation` sits on a *new*, non-legacy-mountpoint ZFS dataset with no
`fileSystems` entry (see D1a), there's nothing forcing
`zfs-mount.service` to run before `systemd-tmpfiles-setup.service` /
`immich-server.service` start — the same class of race already documented
in `docs/backups.md` for `storage`/`storage-bulk`'s first-boot mount
attempts. Needs either `RequiresMountsFor = [ cfg.mediaLocation ]` on
`immich-server`/`immich-machine-learning`, or the same
`mountpoint = "legacy"` + explicit `fileSystems` entry pattern
`storage/storage` already uses. Handle explicitly at implementation time,
not left to boot-order luck.

~~Moot as of 2026-09-03 — D1 was answered as (b), reusing the existing
`zdata/storage/storage` dataset (already mounted, already has a
`fileSystems`/legacy-mountpoint entry). `mediaLocation = /storage/immich`
inherits that dataset's existing mount ordering, so there is no new race
to handle.~~

### G2 -- Immich's own DB story needs no new secrets
`services.immich.database`/`redis` default to local Postgres (with
pgvector/vectorchord bundled by the module) and local Redis, both over
unix sockets by default (`database.host = "/run/postgresql"`,
`redis.host = <redis unix socket>`). The module's own assertion only
requires `secretsFile` when *not* using a unix socket — so the default
config needs zero new sops secrets. Don't add a DB password file unless a
reason shows up to move off unix sockets.

### G3 -- bind address vs. firewall scoping, same shape as jellyfin
`services.immich.host` defaults to `"localhost"` (loopback-only) —
must be changed (e.g. `"0.0.0.0"`) for tailscale0 to reach it at all.
Do **not** use `services.immich.openFirewall` — like the old
`jellyfin.nix` host-wide firewall opening this repo already moved away
from, that option opens the port on every interface, including
homelab's LAN NIC which carries a real ISP-delegated public IPv6 address.
Instead: bind the app to all interfaces, then scope reachability at the
firewall with `networking.firewall.interfaces.tailscale0.allowedTCPPorts
= [ 2283 ]` — exactly jellyfin's pattern in `modules/services/jellyfin.nix`,
minus jellyfin's extra `wg0` rule (that's the whole point: no vps/Anubis
public path for Immich).

## Findings (F)

### F1 -- restricting Immich to Tailscale does not break its own functionality; the rough edges found are Tailscale-on-mobile issues, not Immich issues
Researched via GitHub issues/discussions (not just docs):
  - Immich's server/ML/DB stack has no dependency on public inbound
    reachability for backup, ML jobs, or the mobile app's core upload
    path — everything it needs outbound (OAuth if configured, SMTP if
    configured, initial ML model pulls) is unaffected by an *inbound*
    restriction.
  - iOS/Android app setup over Tailscale: confirmed via
    [immich-app/immich discussion #4255](https://github.com/immich-app/immich/discussions/4255)
    that the one real gotcha is a config mistake, not a platform
    limitation — entering the server's *LAN* IP in the mobile app doesn't
    work from outside the LAN (expected), but the tailnet IP or MagicDNS
    hostname ("it just works" once switched). homelab's tailnet already
    has MagicDNS resolving its hostname (per `docs/procedures/
    remote-access.md`), so this is just "use `homelab:2283` or the
    100.x IP in the app," not new work.
  - The one real, reproducible issue found —
    [tailscale/tailscale#17982](https://github.com/tailscale/tailscale/issues/17982)
    ("Immich Android client app can't upload when Tailscale is up") —
    traces back to a **still-open, general Tailscale Android client bug**,
    [tailscale/tailscale#8283](https://github.com/tailscale/tailscale/issues/8283)
    ("When changing networks on Android I lose connectivity"): Android's
    MagicDNS resolver (100.100.100.100) can intermittently stop
    resolving after a WiFi↔cellular network change, breaking outbound
    connectivity to *anything* on the tailnet until Tailscale is toggled
    off/on. This is not caused by restricting Immich specifically — it
    would affect any tailnet-only service reached from an Android phone
    (SSH, this repo's own NFS share, etc.), and several reporters found
    setting a global nameserver override in the Tailscale admin console
    (rather than relying solely on 100.100.100.100) reduces frequency.
    Worth a one-line callout in whatever setup doc eventually covers
    this, not a blocker.
  - No evidence found of an Immich-specific incompatibility with
    Tailscale-only access on iOS.
  - **The one real, deliberate feature loss is public share links (see
    D2)** — that's an inherent tradeoff of "no public exposure," not a
    bug to work around.

### F2 -- GPU-accelerated ML is real but expensive to stand up; no OpenVINO path via nixpkgs
Read the pinned nixpkgs `immich-machine-learning` package
(`pkgs/by-name/im/immich-machine-learning/package.nix`) and its
`insightface`/`onnxruntime` dependency chain, plus a working NixOS
Discourse recipe ([discourse.nixos.org/t/immich-and-cuda-accelerated-machine-learning/58330](https://discourse.nixos.org/t/immich-and-cuda-accelerated-machine-learning/58330)):
  - nixpkgs' `onnxruntime` derivation supports a `cudaSupport` build flag
    (Nvidia only) and a ROCm one (AMD only) — **no OpenVINO execution
    provider is wired up in nixpkgs**, so the Intel HD 630 iGPU already
    used for jellyfin's QSV/VAAPI fallback has no path here; only the
    Nvidia GTX 1050 Mobile (GP107 Pascal, compute capability 6.1 — meets
    Immich's documented ≥5.2 floor) could ever be used.
  - Getting CUDA-enabled onnxruntime requires an overlay
    (`onnxruntime = prev.onnxruntime.override { cudaSupport = true; }`),
    a test patch to skip one failing assertion, and manual
    `PrivateDevices = lib.mkForce false;` / `DeviceAllow` /
    `LD_LIBRARY_PATH` wiring beyond what `accelerationDevices` alone
    handles per the module source.
  - **No binary cache exists for the CUDA-enabled variant** — this is a
    from-source build (onnxruntime + CUDA toolkit), reported as taking
    multiple hours, and it has to be redone from scratch on every
    nixpkgs bump that touches onnxruntime, unlike jellyfin's NVENC path
    (which just uses the already-cached driver package, no rebuild).
  - Recommendation stands from the discussion: ship CPU-only for v1 (the
    module works out of the box, no override needed), treat CUDA accel
    as a separate follow-up once real per-photo ML latency on this
    library is known to be worth a multi-hour one-time build cost. D3 is
    still open pending the user's final call on this tradeoff.

### F3 -- NFS's `sec=sys` uid-trust model can undermine the 0700 `mediaLocation` boundary D1(b) relied on, for an adversary already holding root on an authorized NFS client

- **File:** `modules/services/immich.nix` (mediaLocation on the shared
  `zdata/storage/storage` dataset), `modules/services/nfs.nix:9-12` (export
  has no `sec=` override, so it stays NFSv4's default `sec=sys`/AUTH_SYS),
  `modules/nixos/nfs-homelab-mounts.nix` (grants `torrent`/`thinkpad` the
  `multimedia` gid and NFS access to `/storage`)
- **Severity:** MEDIUM
- **Confidence:** PLAUSIBLE (architecturally sound from the nixpkgs
  `services.nfs.server`/mount-option semantics read directly, plus
  `services.immich`'s `isSystemUser = true` with no pinned `uid`
  (`nixos/modules/services/web-apps/immich.nix:456-461` in the pinned
  nixpkgs-stable source, confirmed CONFIRMED for that specific claim) — not
  verified against a live host's actual allocated uid, and `nix eval`
  against this worktree's `nixosConfigurations.homelab` was unavailable in
  this sandbox to confirm the concrete number, so the exploit's exact
  target uid is PLAUSIBLE, not demonstrated)
- **Axis:** hardening (a network boundary trusted more than it should be)
  and needed-used (D1(b) was accepted on the premise that the 0700 rule is
  a hard boundary against the wider export)
- **Reachability:** an adversary with root on `torrent` or `thinkpad` --
  both already hold the `multimedia` gid and an NFSv4 mount of `/storage`
  (`modules/nixos/nfs-homelab-mounts.nix`). `modules/services/nfs.nix`'s
  export (`root_squash`, `100.64.0.0/10`) only remaps a client's uid
  **0** to `nobody`; it does nothing to stop that same root user from
  creating a throwaway local account at an arbitrary non-zero uid
  (`useradd -u <N>`) and mounting/reading as that uid instead, because
  `sec=sys` authenticates purely by the uid/gid the client *declares*,
  with no cryptographic binding. Immich's own tmpfiles rule forces
  `/storage/immich` to `0700 immich:immich` on every boot regardless of
  the parent's `0770` mode (this is real, and does stop ordinary
  `multimedia`-gid access) -- but it does not stop a client-side uid that
  happens to collide with immich's server-side uid, which is dynamically
  allocated (no `uid =` pinned in the nixpkgs module) from a small,
  brute-forceable system-uid range. The plan's D1(b) framed the 0700 rule
  as protecting Immich's photo library (a materially more sensitive data
  class than the shared movie library that's the normal reason `/storage`
  is exported) from the wider export; that holds against the *legitimate*
  group-read path the plan discussed, but not against this uid-impersonation
  path, which the plan did not examine.
- **Rule:** n/a -- not a `docs/hardening.md` line item, but adjacent to
  rule 5's "a rule justified by a belief about the network is a rule that
  will silently become wrong" spirit, applied to `sec=sys`'s trust model
  rather than an interface.
- **Finding:** the confidentiality boundary D1(b) relied on to accept
  reusing the NFS-exported dataset is narrower than presented: it stops
  the `multimedia` group, not a malicious/compromised root on an already-
  authorized client.
- **Fix risk:** the two real fixes are heavier than this diff -- moving
  the export to `sec=krb5` (a KDC this repo doesn't have) or implementing
  D1(a) (isolated `zdata/storage/immich` dataset, not NFS-exported, with
  its own disko/zrepl/restic wiring). Either changes reachability for the
  existing `torrent`/`thinkpad` mounts and needs to be tested against
  those real mounts before deploying, not just built.


**ACCEPTED 2026-09-03:** NFS sec=sys/AUTH_SYS lets root on an already-authorized client (torrent/thinkpad) declare an arbitrary uid, which could collide with immich's dynamically-allocated system uid and read through the 0700 mediaLocation directory. Not a new gap Immich introduces -- modules/nixos/nfs-homelab-mounts.nix already documents this exact trust boundary for the whole /storage export (root_squash only remaps uid 0, not other uids), and it applies equally to jellyfin's media today. Fixing it would mean reworking the fleet's NFS auth model (e.g. krb5) -- out of scope for adding one service, and every device that could exploit this already holds this fleet's admin SSH keys (docs/procedures/remote-access.md), which is already a bigger blast radius. Accepted as inherited from the existing NFS trust model, not introduced by this change.

### F4 -- `/var/lib/postgresql` persistence entry has no explicit ownership, unlike every other persistence entry in this repo

- **File:** `modules/services/immich.nix:35` (`"/var/lib/postgresql"` as
  a bare string, vs. `modules/services/jellyfin.nix`'s persistence
  entries, which all specify `{ directory = ...; user = ...; group =
  ...; }` matching the service's actual account)
- **Severity:** INFO
- **Confidence:** CONFIRMED -- read directly:
  `impermanence`'s `submodule-options.nix:39-42` defaults a plain-string
  directory entry's ownership to `user`/`group` passed in from
  `nixos.nix:110-111`, which for `environment.persistence.<path>.directories`
  is hardcoded `"root"`/`"root"`, mode `"0755"`. Separately, the pinned
  nixpkgs `postgresql.nix:844-850` gives `postgresql.service` a
  `StateDirectory = "postgresql postgresql/<version>"` when `dataDir` is
  left at its default (as it is here, since neither `services.immich` nor
  this diff overrides `services.postgresql.dataDir`) -- systemd's own
  directory-management re-applies the unit's `User`/`Group` ownership to
  `StateDirectory`-listed paths on every service start, so root:root
  0755 from impermanence's first creation is expected to get corrected to
  postgres:postgres before postgres ever tries to use it. Not expected to
  break functionally today.
- **Axis:** hardening (consistency with the repo's own established
  pattern) / needed-used
- **Reachability:** n/a -- no adversary path demonstrated; this is a
  latent inconsistency, not a live exposure.
- **Rule:** new-rule candidate -- persistence entries for a service's own
  data directory should specify explicit `user`/`group`/`mode` matching
  that service's account, the way `jellyfin.nix` already does, rather
  than relying on another module's `StateDirectory` re-chown to paper
  over impermanence's root:root/0755 default. The self-healing only
  holds as long as `services.postgresql.dataDir` stays at its default --
  if a future change ever pushes it onto the `ReadWritePaths` branch
  instead (`postgresql.nix:844-846`, taken when `dataDir` is
  non-default), the re-chown stops happening and postgres's own dataDir
  permission check would then refuse to start against a root:root/0755
  directory, silently, until that day.
- **Fix risk:** low -- adding `user = "postgres"; group = "postgres";
  mode = "0700";` (or reusing `config.services.postgresql.dataDir`'s
  effective owner) to the persistence entry matches the existing
  jellyfin.nix pattern. Only needs testing that impermanence's directory
  creation doesn't race/conflict with postgresql's own `StateDirectory`
  provisioning on a genuinely fresh (first-boot) dataset.


**FIXED 2026-09-03:** modules/services/immich.nix's persistence entry for /var/lib/postgresql changed from a bare string (impermanence default root:root/0755) to an explicit { directory; user = "postgres"; group = "postgres"; } entry, matching jellyfin.nix's convention of always setting ownership explicitly rather than relying on postgres's own StateDirectory re-chown to paper over it. Verified postgres's default OS user/group is postgres/postgres in the pinned nixpkgs-stable services.postgresql module. nixos-rebuild build --flake .#homelab re-verified clean after the fix.

## Checked and clean (security review, 2026-09-03)

Reviewed `modules/services/immich.nix` and the one-line
`modules/flake/hosts.nix` addition against `docs/hardening.md` and the
pinned nixpkgs-stable (26.05, rev `a3116115851d68b8952a2a4221cc25a84e56b532`)
`services.immich` module source directly
(`nixos/modules/services/web-apps/immich.nix`), plus the
`services.postgresql`/`services.redis` modules it drives and the
`impermanence` module handling the new persistence entry. Confirmed
clean, beyond what's discussed above and beyond what D1/D2/D3 already
settle as accepted tradeoffs:

- **Bind/firewall shape matches jellyfin's already-reviewed pattern
  exactly**: `host = "0.0.0.0"` with no `openFirewall`, scoped only via
  `networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
  config.services.immich.port ]` (port 2283, confirmed the module's own
  default, unmodified by this diff). No `wg0` rule, confirmed no
  `immich`/`2283` reference anywhere in `hosts/vps/configuration.nix` --
  the "no public path via vps's Caddy+Anubis" claim is actually true, not
  just documented intent. `hosts/homelab/configuration.nix` has no
  `trustedInterfaces`/`allowedTCPPortRanges` that would leak this onto
  the LAN NIC's public IPv6 address.
- **`modules/flake/hosts.nix`**: `nixosModules.immich` is added to
  `homelab`'s module list only -- not `thinkpad`, `torrent`, `vps`, or
  `isoimage`.
- **No new secrets, confirmed at the module-assertion level**: the
  module's own `assertions` only requires `secretsFile` when
  `!isPostgresUnixSocket`; both `database.host` (`/run/postgresql`) and
  `redis.host` (`config.services.redis.servers.immich.unixSocket`) are
  left at their unix-socket defaults, and Redis's own `port = 0` disables
  its TCP listener outright regardless of `bind`. Neither Postgres nor
  Redis ever gets a TCP listener from this config; `services.postgresql`
  keeps its own default `enableTCPIP = false`, unmodified.
- **Backup coverage genuinely holds, not just per the plan's
  reasoning**: `/var/lib/postgresql` sits on the `persistRoot` bind mount
  (`/nix/state`, backed by `zroot/local/state`), and `mediaLocation =
  "/storage/immich"` sits on `zdata/storage/storage` -- both datasets are
  already in `myZrepl.local.datasets`, the weekly
  `restic-backups-backblazeWeekly`'s `backupPrepareCommand` dataset list,
  and `myHealthAlerts.backupStaleness`
  (`zbackup/backup/homelab/zroot/local/state`,
  `zbackup/backup/homelab/zdata/storage/storage`, both already present in
  `hosts/homelab/configuration.nix` before this diff). No new
  zrepl/restic/health-alerts wiring is needed, confirmed by reading those
  three lists directly rather than trusting the plan's restated claim.
- **Systemd hardening on the units this diff enables comes from
  upstream, and is substantial**: `commonServiceConfig` in the pinned
  module already sets `NoNewPrivileges`, `PrivateUsers`, `PrivateTmp`,
  `ProtectHome`/`ProtectClock`/`ProtectKernelModules`/etc.,
  `RestrictAddressFamilies`, `RestrictNamespaces`, `RestrictSUIDSGID`,
  `UMask = "0077"`, and a `CapabilityBoundingSet = ""` for both
  `immich-server` and `immich-machine-learning`; `postgresql.service` and
  the `redis-immich` unit both get their own independent, comparably
  strict hardening blocks from their own pinned modules. Nothing in this
  diff weakens or overrides any of that -- this repo's "custom
  `systemd.services` sandboxing" rule doesn't apply here since no unit is
  repo-authored.
- **Privilege**: no `users.users.*.extraGroups` grant anywhere in the
  diff (rule 6) -- the only supplementary-group grant
  (`immich-server`'s access to the redis socket group) is unit-scoped,
  from the upstream module itself, gated on `cfg.redis.enable &&
  isRedisUnixSocket`.
- **`hosts/flake/hosts.nix` diff and `modules/services/immich.nix` diff**
  contain no docker/OCI containers, so rule 10's per-container checklist
  doesn't apply.

Not independently re-litigated: D1's NFS/multimedia-gid exposure
tradeoff itself (accepted, see F3 above for a narrower angle the plan
didn't cover), D2's public-share-link loss (accepted, tracked as
follow-up), and D3's GPU-acceleration deferral (F2, already investigated
in this plan) -- reviewed here only to confirm this diff's actual code
matches what those decisions describe, not to re-argue the decisions.

_docs-updater finished 2026-09-03T20:59:01Z -- see Findings above._

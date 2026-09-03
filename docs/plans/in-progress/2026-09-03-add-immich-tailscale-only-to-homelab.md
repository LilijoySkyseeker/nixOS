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
follow-up. All three decisions are now resolved. Next step: draft
`modules/services/immich.nix`.

## Progress
- [x] D1 decided (mediaLocation dataset + NFS exposure) — picked (b), subdir of existing /storage
- [x] D2 decided (public share links tradeoff) — user wants a later path, tracked as follow-up
- [x] D3 decided (GPU acceleration for ML, v1 or later) — deferred to follow-up plan, CPU-only for v1
- [ ] modules/services/immich.nix drafted (mirrors modules/services/jellyfin.nix shape)
- ~~[ ] new zdata dataset created + wired into myZrepl/myHealthAlerts/restic (if D1 picks a new dataset)~~
  moot — D1 picked (b), no new dataset
- ~~[ ] G1's mount-ordering race addressed before first deploy~~ moot — see G1 strikethrough
- [ ] `nixos-rebuild build --flake .#homelab` passes
- [ ] `/simplify` run
- [ ] `security` subagent run (new network-exposed service, secrets-adjacent via postgres/redis wiring)
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

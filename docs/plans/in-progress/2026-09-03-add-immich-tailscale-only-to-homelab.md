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

**2026-09-03, deployed and verified live on homelab.** First real
`nixos-rebuild switch --target-host root@homelab` (not just build-tested)
caught a real bug the build/eval-only ladder couldn't have: `immich-server`
crash-looped on `EACCES` because the overridden `mediaLocation` was never
actually created, and `/storage`'s own ACL denied the immich user
traversal into it regardless (G4). Both fixed in
`modules/services/immich.nix`, rebuilt, redeployed. Verified live: `/storage/
immich` exists with correct 0700 ownership, `getfacl /storage` shows the
new traversal grant alongside the existing multimedia one, all four units
(postgresql, redis-immich, immich-server, immich-machine-learning) active,
`curl http://<tailscale-ip>:2283/api/server/ping` returns 200 from
homelab itself, `systemctl --failed` empty. v1 is live and working.

**2026-09-03, rerun `/simplify` + `security` on the G4 fix commit, caught and fixed a real
confidentiality bug before it could bite (F5).** 4 parallel review agents
(reuse/simplification/efficiency/altitude) on the G4 diff all came back
clean. `security` found F5 (HIGH, CONFIRMED): the pre-existing recursive
`A /storage ... group:multimedia:rwx` rule re-applies on every boot/switch
and, now that G4 makes `/storage/immich` actually exist and get populated,
the very next unrelated reboot or switch would have recursively granted
the whole `multimedia` group read/write ACL access to every photo Immich
stores -- silently defeating the 0700 confidentiality boundary D1(b)/F3
both relied on, with no exploit needed since lilijoy's own account already
holds that gid via the NFS mounts. It hadn't happened yet only by luck of
file-sort ordering on the deploy that created the directory. Fixed with a
second tmpfiles rule that re-locks `mediaLocation` immediately after the
broad rule, every boot/switch, recursively. Verified live, not just by
ordering theory: forced a full `systemd-tmpfiles --create` pass on homelab
(equivalent to a real reboot) and confirmed via `getfacl` that
`/storage/immich` retained `group::---` with only `user:immich:rwx` --
no `group:multimedia` entry survived -- while `/storage` itself still
correctly shows both its normal grants. Deployed before any real exposure
window opened.

**2026-09-03, D4: scoped read-only access restored for torrent/thinkpad.**
User asked for the trusted desktop machines to be able to read the raw
photos after all. Added a fourth tmpfiles rule granting `group:multimedia:
r-X` specifically on `mediaLocation/library` (read-only, and only the
organized originals -- not staging/thumbnails/video-encodes/DB backups),
ordered to reapply after F5's re-lock on every boot/switch. Also fixed a
minor cosmetic nit caught while verifying (F5's own grant should have been
`rwX` not `rwx`). Verified live: `library/` and nested files show
`group:multimedia:r-x`/`r--`, everything else in the tree still shows no
multimedia entry at all, all four units still healthy.

**2026-09-03, D4 follow-up: user hit a real access-denied from torrent,
fixed and reverified with a real `ls` over NFS, not just `getfacl`.**
The `library/` grant alone wasn't reachable -- `mediaLocation` itself had
no traversal grant, so `cd`/`ls` into `/storage/immich` failed before
ever reaching `library/`. Two-step fix: execute-only traversal first,
then upgraded to read so browsing the folder itself works and reveals
sibling directory names (not their contents). Retested live, this
session, directly on `torrent` (not just via SSH+getfacl on homelab):
`immich/` and `immich/library/` (recursively) now browsable, `backups/`/
`thumbs/`/`encoded-video/`/`upload/`/`profile/` all still correctly
denied.

**2026-09-03, D5: GPU-accelerated video transcoding device access deployed
live.** Separate from the deferred ML/CUDA work (`2026-09-03-gpu-
accelerate-immich-machine-learning-cuda.md`) -- video transcoding needs
no rebuild, just device passthrough, since Immich's own ffmpeg already
has NVENC/VAAPI compiled in. Mirrored jellyfin's own proven-working
device access (`/dev/dri/renderD128`+`renderD129`, `render` group
membership) rather than trusting generic docs. Deployed and verified:
correct `DeviceAllow`/`PrivateDevices`/group membership, API healthy
after restart, and -- prompted by a direct user question worth taking
seriously rather than assuming away -- confirmed via `/api/jobs` that
restarting mid-backlog from the Takeout imports didn't fail or lose any
queued job (`failed: 0` everywhere). Declared nothing in
`services.immich.settings` (a deliberate choice, not an oversight --
Immich's config-file mechanism locks the *entire* admin settings panel
once anything is declared, not just the declared keys, so NVENC itself
still needs a manual one-time toggle in the admin UI). Also imported a
second Google Takeout (a different account) via the same immich-go
workflow validated on the first: 1,158 assets, dry-run caught 2 files
with no matching Takeout metadata, real import included them via
`--include-unmatched` per user's choice.

**2026-09-03, final `/simplify` + `security` pass on F5/D4/D5 (user-
requested, everything since the prior review), F6/F7/F8 fixed and
deployed.** Security found: F6 (MEDIUM) -- GPU device access meant only
for `immich-server` was leaking to `immich-machine-learning` (untrusted-
media-parsing component) via a user-level group grant plus upstream's
own shared `commonServiceConfig`; fixed with a per-unit
`SupplementaryGroups` grant on just `immich-server` and an explicit
`mkForce` lockout back to zero device access on `immich-machine-learning`
-- user confirmed this is the right call (ML stays CPU-only per D3; real
GPU-accelerated ML is the separate deferred CUDA plan, now carrying a G2
note about undoing this lockout when that work happens). F7 (INFO) --
narrowed an inert-but-imprecise `rwm` device grant to explicit `rw`,
matching jellyfin's own pattern. F8 (MEDIUM) -- corrected comments that
credited the wrong mechanism (`mkAfter`/file order) for why the F5
re-lock rule wins over upstream's competing rule; real mechanism is
systemd-tmpfiles' own type-based sort, confirmed against the pinned
`tmpfiles.c` source. `/simplify` found one accepted-not-fixed efficiency
tradeoff (double recursive walk over `library/`, not worth the
enumeration fragility to eliminate) and one declined altitude suggestion
(extracting a shared ACL-grant helper -- premature for a single real
consumer). All fixes verified live: correct per-unit device access,
services healthy, job queue still clean after yet another restart.

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
- [x] deployed live to homelab (`nixos-rebuild switch --target-host`) — caught and fixed G4 (mediaLocation creation + /storage ACL traversal), verified working end-to-end
- [x] rerun `/simplify` + `security` on the G4 fix commit — 4/4 simplify clean, security caught F5 (HIGH), fixed and verified live with a forced boot-simulating tmpfiles pass
- [x] D4 decided + implemented — torrent/thinkpad get scoped read-only access to mediaLocation/library, verified live
- [x] D5 decided + implemented — GPU device passthrough for video transcoding deployed live, verified (DeviceAllow, render group, job queue undisturbed by the restart); NVENC backend selection left as a manual admin-UI toggle, not Nix-declared
- [x] final `/simplify` + `security` pass on F5/D4/D5 — F6/F7/F8 fixed and deployed, verified live; one efficiency tradeoff accepted, one altitude suggestion declined (both with reasoning recorded)
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

**NOTE 2026-09-03 -- friendly hostname idea, relevant to this follow-up:**
user asked whether Immich could be reached as `immich.homelab` over the
tailnet instead of `homelab:2283`. Answer: not via Tailscale's MagicDNS
alone (it only names devices, not per-service subdomains) -- needs (1) a
reverse proxy on homelab doing Host-header routing on `tailscale0:80`
(e.g. Caddy, already precedented on vps) to `localhost:2283`, plus (2)
something to make the name resolve: either a public DNS record via the
octodns setup already in this repo (zero new infra, but discloses the
hostname's *existence* publicly via DNS lookup, even though the resulting
tailscale IP stays unreachable off the tailnet), or Tailscale Split DNS
against a self-hosted resolver (fully private, but a new component to
run). **Decision explicitly deferred** -- landing v1 with straight
`homelab:2283` port access for now, no proxy built. Worth revisiting
together with D2's public-share-link follow-up, since the same reverse
proxy would also be the natural front door for a later scoped Tailscale
Funnel or Anubis proxy -- one piece of infra could serve both asks
(friendly hostnames tailnet-wide, and selective public share-link
exposure) rather than building them separately.

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

### D4 -- reopened after F5: should torrent/thinkpad get any access back into mediaLocation?
F5's fix locked `mediaLocation` down to `immich:immich` only, no group
access at all -- correct as a default, but the user then explicitly asked
for `torrent`/`thinkpad` (the same NFS `multimedia`-gid mount jellyfin
already uses) to be able to read the raw photos, clarifying these are
trusted machines. **ANSWERED 2026-09-03:** scoped, read-only grant --
`group:multimedia:r-X` on `mediaLocation/library` specifically (the
organized original photos/videos), *not* the whole tree. `upload/`
(transient staging), `thumbs/`/`encoded-video/` (generated derivatives),
and `backups/` (Postgres dumps) stay `immich`-only. Read-only rather than
read-write regardless of trust: Immich tracks every file's path and
checksum in its own database, so an external write (rename/edit/delete)
risks desyncing that and corrupting Immich's own view of the library --
a data-integrity concern, not a confidentiality one, so "trusted
machines" doesn't remove it. Implemented as a fourth `systemd.tmpfiles.rules`
entry in `modules/services/immich.nix`, additive (`A+`) and ordered last
so it re-applies after F5's re-lock strips everything, every single
boot/switch. Verified live: `getfacl` on `library/` (and a nested photo
file) shows `group:multimedia:r-x`; `backups/`, `thumbs/`, `upload/` all
show no `multimedia` entry at all. Also caught and fixed a minor
correctness nit while verifying: F5's own `user:immich:rwx` grant should
have been `rwX` (conditional execute) rather than a hardcoded `rwx`, or
every leaf file (including plain photos) picks up a spurious execute
bit that then propagates into this new grant's own `X`-conditional
logic. Fixed, redeployed, reverified -- purely cosmetic (an executable
bit on a jpg does nothing), and only affects files already touched
before the fix; new uploads get the correct mode going forward.

**FOLLOW-UP BUG, caught live by the user 2026-09-03:** the initial D4
grant covered `library/` but not `mediaLocation` itself -- F5's re-lock
rule strips every group entry from `mediaLocation`, including the
directory that has to be traversed *through* to reach `library/`, and
D4's own grant never touched that parent. POSIX requires `+x` on every
directory in a path, not just the leaf, so this was a real, reproducible
access-denied on `torrent` (`ls: cannot open directory
'/home/lilijoy/storage/immich/': Permission denied`), confirmed live in
the same session that deployed the original D4 fix -- `getfacl`-only
verification on `library/` alone wasn't enough to catch it. Fixed in two
steps, both verified with real `ls` from `torrent` over the actual NFS
mount (not just `getfacl` on homelab):
  1. added `a+ mediaLocation - - - - group:multimedia:--x` (execute-only,
     non-recursive) so traversal into a *known* path
     (`mediaLocation/library`) works;
  2. that alone left `ls mediaLocation` itself denied (execute lets you
     `cd` into a known child, not list what's there) -- upgraded to
     `r-X` so `ls`/browsing the immich folder itself works and reveals
     the sibling directory *names* (`backups`, `thumbs`, `upload`, ...),
     which is the natural way anyone would actually go looking for
     `library/`. Their *contents* stay unreadable regardless -- they have
     no grant of their own, confirmed live (`ls backups/`, `ls thumbs/`
     both still denied after this change).
End state, verified via real `ls` from `torrent`: `immich/` browsable,
`immich/library/` (and everything under it) fully browsable, `backups/`/
`thumbs/`/`encoded-video/`/`upload/`/`profile/` all still denied.

### D5 -- GPU-accelerated video transcoding (not the deferred ML/CUDA work), and whether to declare Immich's app-level settings in Nix
Separate from the GPU-accelerated ML work already deferred to
`2026-09-03-gpu-accelerate-immich-machine-learning-cuda.md` (that needs a
multi-hour from-source onnxruntime+CUDA rebuild) -- **video transcoding**
acceleration is much cheaper: Immich's own ffmpeg build already has
NVENC/VAAPI compiled in (confirmed live -- it's the same
`jellyfin-ffmpeg` binary jellyfin itself uses), so this is pure device
passthrough, no rebuild. Checked jellyfin's own live systemd config on
homelab rather than trusting generic docs: NVENC works there with only
`/dev/dri/renderD128` in `DeviceAllow` and no `/dev/nvidia*` entries at
all, and `jellyfin` is in the `render` group but not `video`. Mirrored
that exact proven-working shape for immich: `services.immich.
accelerationDevices = [ "/dev/dri/renderD128" "/dev/dri/renderD129" ];`
(Nvidia + Intel, matching jellyfin's own dual-GPU access) plus
`users.users.immich.extraGroups = [ "render" ];`. Built and verified in
the generated config (`DeviceAllow` correct, `PrivateDevices=false`,
`render` group's members now include both `jellyfin` and `immich`) --
**not yet deployed**, user said hold off.

Second question this raised: whether to also declare the actual
hardware-acceleration *backend choice* (`ffmpeg.accel = "nvenc"`) via
`services.immich.settings`, rather than toggling it in Immich's admin
UI. Investigated Immich's own config-file behavior before answering --
it is **not** the "declare only what you care about, everything else
stays UI-editable" mechanism it looks like: providing *any*
`services.immich.settings` (even a single key) locks Immich's **entire**
admin Settings panel read-only, and every key not explicitly declared
falls back to Immich's built-in defaults rather than whatever was
previously configured -- confirmed via Immich's own GitHub
issues/discussions on the config-file feature, not just the docs page
(which doesn't state this explicitly). Presented three options (declare
nothing / declare just `ffmpeg.*` / declare a fuller settings block).

**ANSWERED 2026-09-03:** declare nothing in Nix for now -- toggle NVENC
by hand in Immich's admin UI once the device-access change deploys.
Revisit declaring `services.immich.settings` in Nix later, once it's
clear which specific settings are actually worth pinning down (`ffmpeg`,
possibly `backup`/`trash`/`storageTemplate`), rather than locking the
whole settings UI now for one setting.

**DEPLOYED 2026-09-03:** `nixos-rebuild switch --target-host root@homelab`.
Verified live: `DeviceAllow` on `immich-server` shows both
`/dev/dri/renderD128 rwm` and `/dev/dri/renderD129 rwm`, `PrivateDevices=
no`, `immich` now a member of the `render` group alongside `jellyfin`,
API responding after restart. Also checked (unprompted question from the
user, worth recording since it was a real risk worth verifying rather
than assuming): did restarting `immich-server`/`immich-machine-learning`
mid-way through the large Google Photos import's background job backlog
(thumbnails/transcode/face-detection queues, still draining from the
first Takeout import) lose or corrupt anything? Checked `/api/jobs`
directly -- `failed: 0` across every single queue, backlog counts
consistent with normal draining, nothing stuck. Immich's Redis-backed job
queue requeues an interrupted job rather than dropping or corrupting it,
confirmed by evidence not just design assumption. NVENC itself still not
yet toggled on in the admin UI -- transcoding is still running in
software mode, by design (D5's answered choice), until that manual step
happens.

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

### G4 -- caught live on first real deploy: mediaLocation override needs its own create rule + an ACL grant into /storage
Deployed to `homelab` (`nixos-rebuild switch --target-host root@homelab`,
not just build-tested) and `immich-server` crash-looped on
`EACCES: permission denied, mkdir '/storage/immich/encoded-video'`.
Two real bugs, both now fixed in `modules/services/immich.nix`:
  - The upstream `services.immich` module's own tmpfiles rule for
    `mediaLocation` is type `e` ("adjust mode if it already exists") —
    a no-op for anything but its own default `/var/lib/immich`, which
    only exists because systemd's `StateDirectory=` creates it for free.
    Overriding `mediaLocation` (per D1) means nothing ever creates the
    directory. Fixed by merging a `d` rule into the same `systemd.
    tmpfiles.settings.immich` group the upstream module already
    declares for that exact path.
  - `/storage` itself is `drwxrws--- root:multimedia`
    (`hosts/homelab/configuration.nix`), `other::---` — immich is in
    neither, so it couldn't traverse into its own mediaLocation even
    once the directory existed. Fixed with a non-recursive, *additive*
    ACL grant (`a+ /storage - - - - user:immich:--x`, execute-only —
    traversal only, no read/list access into jellyfin's actual media)
    via `lib.mkAfter` on `systemd.tmpfiles.rules`, ordered after the
    existing recursive-replace `A /storage ... group:multimedia:rwx`
    rule (same generated `00-nixos.conf`) so it isn't wiped by that
    rule's own replace-pass on the next boot.
  Verified after redeploy: `/storage/immich` exists as `drwx------
  immich:immich`, `getfacl /storage` shows both the existing
  `group:multimedia:rwx` and the new `user:immich:--x` entries,
  `immich-server` started clean with no further crash-loop, `curl
  http://<tailscale-ip>:2283/api/server/ping` returns `200` from
  homelab itself, all four units (postgresql, redis-immich,
  immich-server, immich-machine-learning) active, `systemctl --failed`
  empty fleet-wide.

### G5 -- final `/simplify` pass on the F5/D4/D5 commits: one accepted-not-fixed tradeoff, one declined restructure
Rerun of the 4-way `/simplify` review (reuse/simplification/efficiency/
altitude) plus `security` on everything since the prior pass
(`709523c..HEAD`), requested explicitly by the user before wrapping up.
Reuse: clean. Simplification: two stale/bloated comments (the F5 block
had accreted into an incident narrative rather than a load-bearing
invariant; the "always runs last and wins" claim went stale the moment
D4's rules got appended after it) -- both trimmed as part of the F8 fix
above. Efficiency: mediaLocation/library gets walked by two separate
recursive tmpfiles passes every boot (the F5 re-lock covers the whole
tree, the D4 library grant re-walks library/ specifically) --
**accepted, not fixed**: the only way to avoid the double walk is to
scope the re-lock rule away from library/ by enumerating mediaLocation's
other subdirectories (`upload`/`thumbs`/`encoded-video`/`backups`/
`profile`) by name, which would silently stop covering any new
subdirectory a future Immich version adds -- a real correctness
regression traded for a boot-time-only performance gain on what's
realistically a modest personal library. Altitude: suggested extracting
a generic shared helper (e.g. `mkStorageScopedGrant`) for the
"traverse-then-scoped-grant" ACL pattern, citing that this is the second
real incident (F5, D4-followup) produced by hand-rolled raw tmpfiles
rules + `mkAfter` ordering, and that jellyfin.nix hit an analogous
tmpfiles-ordering trap once already (fixed there by moving to the typed
`systemd.tmpfiles.settings` API). **Declined**: jellyfin's fix doesn't
transfer directly -- ACL manipulation genuinely needs the raw-string
rule format (no typed API surface for it in this nixpkgs version), and
there is exactly one real consumer of this specific scoped-grant pattern
today (immich itself; jellyfin doesn't need it, it's a full `multimedia`
group member). Extracting a generic parameterized module for a
single-consumer pattern would be premature abstraction under this repo's
own stated conventions. Addressed the actual root concern narrowly
instead: F8's comment fix states the true ordering mechanism precisely,
so a future third rule added to this same list has an accurate
explanation to build on rather than propagating the mkAfter
misconception.

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

**NOTE 2026-09-03:** this acceptance's premise ("does stop ordinary multimedia-gid access", line 339-340 above) briefly did NOT hold in practice -- see F5, found by the same security review pass, which showed the pre-existing recursive `/storage` ACL rule would have granted the multimedia group direct read/write onto mediaLocation on the next boot, no uid-impersonation needed at all. F5 is now fixed and verified live (forced tmpfiles pass + getfacl confirmed no group:multimedia entry survives). With F5 fixed, this finding's original premise holds again: what remains is genuinely only the narrower uid-impersonation path described above, not ordinary group access.

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

### F5 -- the pre-existing recursive `A /storage ... group:multimedia:rwx` tmpfiles rule now reaches into, and overwrites the ACL of, every file G4's fix creates under `/storage/immich`, defeating the 0700 confidentiality boundary D1(b)/F3 relied on

- **File:** `hosts/homelab/configuration.nix:183` (`"A /storage - - - - group:multimedia:rwx"`,
  unmodified by this diff, pre-existing since the 2026-08-28 `/srv` fix) interacting
  with `modules/services/immich.nix:33-37` (the new `d` rule that, per G4, now
  actually creates and lets Immich populate `/storage/immich` with real photo/video
  files -- before this diff's fix there was nothing under that path for the `A`
  rule to reach)
- **Severity:** HIGH
- **Confidence:** CONFIRMED -- read the exact pinned nixpkgs-stable systemd source
  homelab actually runs (`nixpkgs-stable` = rev `a3116115851d68b8952a2a4221cc25a84e56b532`,
  confirmed as homelab's input via `modules/flake/hosts.nix:62`,
  `inputs.nixpkgs-stable.lib.nixosSystem`), `src/tmpfiles/tmpfiles.c`:
  - `tmpfiles.d(5)`'s own text: bare `a`/`A` (no `+` suffix) *sets* the ACL rather
    than adding to it; only `a+`/`A+` add to the existing set.
  - `path_set_acl()` (`tmpfiles.c:~1358-1381`): when `modify` (=`item->append_or_force`,
    false for bare `A`) is false, it computes the target ACL purely from the rule's
    own argument (`acl_dup(acl)`) instead of merging with the file's current on-disk
    ACL (`acls_for_file()`, only called in the `modify` branch) -- i.e. bare `A`
    **replaces** whatever ACL a file already has with [base entries computed from
    that file's own mode] + [the rule's named entry] + [a recomputed mask], for
    every file it touches.
  - `item_do()` (`tmpfiles.c:~2492`, confirmed identical in both the pinned
    nixpkgs-stable and nixos-unstable systemd sources) recurses into every
    directory entry via `FOREACH_DIRENT_ALL` + a recursive `item_do()` call --
    this is a genuine full filesystem walk, not just glob expansion -- and
    `RECURSIVE_SET_ACL` (`A`) drives this walk via `fd_set_acls()`, which applies
    to every **regular file** too (only symlinks are skipped, `tmpfiles.c:1462`).
  - The `A /storage` line has no `!` prefix, so per `tmpfiles.d(5)` it is "safe to
    execute at any time" and runs both at every boot (`systemd-tmpfiles-setup.service
    --boot`) and at every `nixos-rebuild switch` (the tmpfiles.nix module's own
    `systemd-tmpfiles-resetup.service`, wired into `switch-to-configuration`,
    invokes `systemd-tmpfiles --create --remove --exclude-prefix=/dev` with no
    `--boot` filtering that would exclude it).
  - `/storage`'s config-file precedence: `00-nixos.conf` (carries the `A /storage`
    rule) sorts lexicographically before `immich.conf` (carries the new `d`
    rule for `mediaLocation`), and `tmpfiles.d(5)` states a prefix path (`/storage`)
    is always processed before a suffix path (`/storage/immich`) regardless of
    which file each is declared in -- so on the very first deploy, `/storage/immich`
    didn't exist yet when `A` ran, and there was nothing under it to touch. That is
    no longer true from the second boot/switch onward, once the directory exists
    and Immich has written real files into it: `A`'s recursive walk will descend
    into `/storage/immich` and overwrite the ACL on every photo/video/thumbnail file
    and subdirectory there with `group:multimedia:rwx` (plus a mask covering it),
    regardless of the file's own traditional mode or its `immich:immich` ownership.
- **Axis:** hardening (a data-confidentiality boundary this plan explicitly designed
  around does not actually hold under the fleet's own existing tmpfiles pattern) and
  needed-used (D1(b) and F3 were both accepted on a premise this disproves)
- **Reachability:** no exploit or privilege escalation is required. `modules/nixos/nfs-homelab-mounts.nix`
  already grants `lilijoy`'s own account the `multimedia` gid locally on `torrent`/`thinkpad`,
  specifically so that account gets "group rw over the whole share" via the existing
  NFS mount at `/home/lilijoy/storage` (that module's own comment, verbatim). Once
  the recursive `A /storage` rule re-walks the tree on homelab's *next* boot or
  `nixos-rebuild switch` (routine, not something that needs to be triggered
  specially), that same already-mounted, already-authorized NFS share on
  `torrent`/`thinkpad` will show read+write access into every file under
  `/storage/immich` too -- Immich's private photo/video library, which D1(b)
  explicitly picked reusing `/storage` over a new isolated dataset *because* "Immich's
  media is personal photos, a different sensitivity class than the shared movie
  library," and which F3's own acceptance rested on the claim that "Immich's own
  tmpfiles rule forces `/storage/immich` to 0700 immich:immich on every boot
  regardless of the parent's 0770 mode... this is real, and does stop ordinary
  multimedia-gid access." That claim is false against this specific rule: the 0700
  mode set by the new `d` rule only re-applies to the top-level `/storage/immich`
  directory itself (non-recursive), it does not, and cannot, protect the contents
  from a *later*, separately-triggered recursive ACL rule that walks past it and
  resets permissions on every file underneath. Any future account or NFS client that
  comes to hold the `multimedia` gid gets the same reach, with no additional step.
- **Rule:** n/a -- not a specific `docs/hardening.md` line item, but it directly
  falsifies the "does stop ordinary multimedia-gid access" premise F3 was accepted
  on, and is exactly the "verify config actually takes effect, not by reading the
  file you just wrote" failure mode rule 9 warns about: G4's own live verification
  ran `getfacl /storage` (the top-level directory, right after the very first
  deploy, before the recursive rule had anything of Immich's to reach) and
  concluded the ACL grant was correctly scoped -- it did not check `/storage/immich`
  itself, and could not have caught this on that first run regardless, since the
  exposure only activates from the *second* boot/switch onward.
- **Finding:** the `0700 immich:immich` mode G4 added for `mediaLocation` is not the
  hard confidentiality boundary D1(b) and F3 both described it as. The fleet's own
  pre-existing, unmodified `A /storage - - - - group:multimedia:rwx` rule
  (`hosts/homelab/configuration.nix:183`) recursively re-grants the `multimedia`
  group read+write ACL access to every file anywhere under `/storage`, including
  `/storage/immich`, on every subsequent boot and switch -- something that was
  inert before this diff (nothing existed under `/storage/immich` for it to reach)
  and becomes live and real the moment Immich actually stores photos there, which
  is the entire point of this plan.
- **Fix risk:** real fixes change reachability for the existing, working jellyfin
  NFS share and need testing against `torrent`/`thinkpad`'s real mounts before
  deploying, not just building -- this is heavier than a follow-up line edit:
  - Moving Immich's `mediaLocation` off the NFS-exported dataset entirely (D1(a),
    a new non-exported `zdata/storage/immich` dataset) removes the interaction
    outright, at the cost of the disko/zrepl/restic wiring D1(b) was chosen to avoid.
  - Excluding `/storage/immich` from the recursive walk (e.g. splitting `/storage`'s
    `A` rule to stop before `immich`, or narrowing it to a non-recursive `a` plus
    per-subtree recursive rules for the paths that actually need it) needs auditing
    what currently depends on the *existing* recursive reach into every other
    subtree of `/storage` (jellyfin's own library) before narrowing it, and needs
    verification that `systemd-tmpfiles`' path-based rule matching can actually
    express "recurse into `/storage` except this one subdirectory" (it may not,
    without exclude-prefix support at the rule level).
  - Either way, this needs to be checked against a live filesystem state (`getfacl`
    run recursively, or specifically against files known to exist under
    `/storage/immich`, *after* a second boot/switch, not just the first) rather than
    trusted from the eval-level reasoning that predicted it originally.



**FIXED 2026-09-03:** Added a second tmpfiles rule to modules/services/immich.nix: 'A ${mediaLocation} - - - - user:immich:rwx' (recursive replace), ordered via the same mkAfter list as the existing traverse grant, so it always runs immediately after the broad /storage rule on every boot/switch and strips any group:multimedia ACL entry the broad rule just applied underneath mediaLocation. Verified live on homelab, not just by ordering theory: forced a full systemd-tmpfiles --create pass (equivalent to a real boot) and confirmed via getfacl that /storage/immich retained group::--- with only user:immich:rwx -- no group:multimedia entry survived -- while the parent /storage still correctly shows both its normal grants. Deployed and confirmed before any real exposure window (the directory didn't yet exist when the broad rule ran on the deploy that created it, so nothing had actually leaked).

### F6 -- `users.users.immich.extraGroups = [ "render" ]` grants GPU render-node access to `immich-machine-learning` too, not just the transcoding unit that needs it

- **File:** `modules/services/immich.nix:45` (`users.users.immich.extraGroups = [ "render" ];`)
  interacting with the pinned nixpkgs-stable `services.immich` module
  (`nixos/modules/services/web-apps/immich.nix`, rev
  `a3116115851d68b8952a2a4221cc25a84e56b532`): `commonServiceConfig` (lines
  ~17-46) is shared verbatim (`serviceConfig = commonServiceConfig // {...}`)
  between `systemd.services.immich-server` (line ~395) *and*
  `systemd.services.immich-machine-learning` (line ~426), and both units run
  as `User = cfg.user;` / `Group = cfg.group;` -- the same `immich` account
  (`cfg.user` defaults to `"immich"`, not overridden anywhere in this repo).
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED for the mechanism (read the exact pinned
  upstream module source and the systemd default udev rule
  (`rules.d/50-udev-default.rules.in:61`: `SUBSYSTEM=="drm",
  KERNEL=="renderD*", GROUP="render", MODE="{{GROUP_RENDER_MODE}}"`, from
  the same pinned systemd source tree, confirming render nodes are DAC-gated
  on the `render` group, not just the cgroup device controller). PLAUSIBLE
  for the specific attack path (a malicious/crafted photo or video
  triggering code execution inside `immich-machine-learning`'s
  image-decode/ONNX-inference pipeline) -- asserted as a standard threat
  model for any component that parses attacker-supplied media, not a known
  CVE.
- **Axis:** hardening
- **Reachability:** `immich-machine-learning` is the one component in this
  deployment whose entire job is parsing untrusted, externally-supplied
  input (every photo/video any account uploads, including via a public
  share link once D2's follow-up lands, or from any tailnet-authorized
  client today) for face detection/object recognition. An adversary who
  achieves code execution there -- the plausible first step for exactly this
  class of service -- inherits every group membership of the shared `immich`
  Unix account, including `render`, and the cgroup already permits it
  (`DeviceAllow` is set from the *same* shared `commonServiceConfig`
  regardless of which unit it's attached to, so the cgroup-level gate is
  already open for both units regardless of this diff). The only thing
  actually keeping `immich-machine-learning` off `/dev/dri/renderD128`/`129`
  before this diff was the traditional DAC group check on the device node
  (`root:render 0660`-shaped, confirmed via the udev rule above) -- which
  this diff's `users.users.immich.extraGroups` grant removes for both units
  at once, not just `immich-server`.
- **Rule:** violates `docs/hardening.md` rule 6 ("Put privilege on the unit,
  not the user... a user-level grant applies to *everything* that user ever
  runs, for as long as the account exists")
- **Finding:** the fix should have been
  `systemd.services.immich-server.serviceConfig.SupplementaryGroups = [
  "render" ]` (scoped to the one unit D5 actually needs it for -- video
  transcoding, which per D5's own comment only happens in `immich-server`,
  not `immich-machine-learning`), not a `users.users.*.extraGroups` grant.
  The jellyfin precedent this diff's comment cites as prior art
  (`users.users.jellyfin.extraGroups = [ "render" ]`,
  `modules/services/jellyfin.nix:49`) does not actually establish this is
  safe to copy: jellyfin has exactly one systemd unit running as the
  `jellyfin` user, so a user-level grant and a unit-level grant are
  equivalent there. Immich splits into two systemd units
  (`immich-server`, `immich-machine-learning`) sharing one Unix account,
  which is exactly the shape rule 6 is written to cover and jellyfin's
  single-unit case never exercises. This repo's own prior review pass
  (this same plan file, "Checked and clean (security review, 2026-09-03)",
  before D5 existed) explicitly noted "no `users.users.*.extraGroups` grant
  anywhere in the diff (rule 6)" as a positive finding -- D5 is what
  introduces the first one.
- **Fix risk:** low -- swapping to `serviceConfig.SupplementaryGroups` on
  just `immich-server` is a narrow, mechanical change. The only thing to
  verify post-fix is that hardware transcoding still actually works from
  `immich-server` (the unit that opens the render node), since
  `SupplementaryGroups` takes effect per-unit at process start, same as the
  user-level grant did for that unit.


**FIXED 2026-09-03:** Fixed in two steps, both verified live. (1) Moved render-group membership from users.users.immich.extraGroups (user-level, shared by both immich-server and immich-machine-learning) to systemd.services.immich-server.serviceConfig.SupplementaryGroups -- confirmed via the generated unit file that this merges with upstream's own conditional redis-immich group grant on the same unit rather than replacing it. (2) That alone wasn't sufficient: services.immich.accelerationDevices is applied to both units by the upstream module's own shared commonServiceConfig, so immich-machine-learning still showed DeviceAllow for both render nodes even after the group fix. Added systemd.services.immich-machine-learning.serviceConfig = { PrivateDevices = lib.mkForce true; DeviceAllow = lib.mkForce []; } to force it back to its pre-D5 zero-device posture. Verified live after redeploy: immich-server retains both SupplementaryGroups (redis-immich, render) and both DeviceAllow entries; immich-machine-learning shows PrivateDevices=yes and zero DeviceAllow lines. Job queue confirmed undisturbed by the restart (failed:0 across all queues, same check as after prior restarts). Noted as G2 in the deferred GPU-accelerate-immich-ml plan since that follow-up will need to deliberately undo this override when it's implemented.

### F7 -- `accelerationDevices`' bare device paths grant `rwm` (full, including device-node creation) via `DeviceAllow`, not `rw`, unlike jellyfin's explicit `"... rw"` entry the comment claims to match

- **File:** `modules/services/immich.nix:33-36` (`accelerationDevices = [
  "/dev/dri/renderD128" "/dev/dri/renderD129" ];`, no access-mode suffix)
  vs. `modules/services/jellyfin.nix:46-48`
  (`systemd.services.jellyfin.serviceConfig.DeviceAllow = lib.mkAfter [
  "/dev/dri/renderD129 rw" ];`, explicit `rw`)
- **Severity:** INFO
- **Confidence:** CONFIRMED -- verified against the pinned nixpkgs-stable
  systemd source (`a3116115851d68b8952a2a4221cc25a84e56b532`):
  `src/core/load-fragment.c:4186` (`config_parse_device_allow`):
  `permissions = isempty(p) ? 0 : cgroup_device_permissions_from_string(p);`
  -- an omitted access-mode token parses to `permissions = 0`, and
  `src/core/cgroup.c:697-698`/`724-725`
  (`cgroup_context_add_device_allow`/`_add_or_update_device_allow`):
  `if (p == 0) p = _CGROUP_DEVICE_PERMISSIONS_ALL;` -- `_ALL` is `r|w|m`.
  Also confirmed live via `nix repl` against
  `nixosConfigurations.homelab.config.systemd.services.immich-server.serviceConfig.DeviceAllow`,
  which evaluates to exactly `[ "/dev/dri/renderD128" "/dev/dri/renderD129" ]`
  -- bare paths, no access-mode field -- matching the upstream module's own
  `DeviceAllow = mkIf (cfg.accelerationDevices != null)
  cfg.accelerationDevices;` (`nixos/modules/services/web-apps/immich.nix:28`),
  which passes `accelerationDevices` straight through with no access-mode
  suffix appended.
- **Axis:** needed-used
- **Reachability:** n/a beyond the cgroup device-controller permission
  itself -- practically inert. `mknod(2)` for a character/block device node
  additionally requires `CAP_MKNOD` (or root) regardless of what the cgroup
  device controller permits, and `commonServiceConfig` sets
  `CapabilityBoundingSet = "";` for both `immich-server` and
  `immich-machine-learning` (confirmed, same upstream source, unmodified by
  this diff) -- so neither unit can actually exercise the `m` bit even
  though the cgroup grants it.
- **Rule:** n/a -- not a specific `docs/hardening.md` line item; general
  least-privilege beyond that doc's own rules.
- **Finding:** video transcoding only needs `r`+`w` on the render nodes
  (open, ioctl, read/write); this repo's `accelerationDevices` list grants
  `rwm` on both, an over-broad cgroup permission with no demonstrated reach
  given the capability bounding set already blocks the only thing `m`
  enables. The diff's own comment ("Same two render nodes jellyfin already
  uses... jellyfin's own systemd unit has no `/dev/nvidia*` DeviceAllow
  entries at all, just this") is accurate about the device *list* matching
  jellyfin's, but not about the access *mode* -- jellyfin's own
  `DeviceAllow` entry is explicitly `rw`-only, immich's is implicitly `rwm`.
  This is entirely upstream's module design (`accelerationDevices` has no
  way to specify an access mode at all, per its option type
  `types.nullOr (types.listOf types.str)` with device *paths* as the
  example), not something this repo's diff could have avoided while using
  that option -- flagged as a real but low-value gap between the stated
  jellyfin-parity claim and the actual access mode granted.
- **Fix risk:** none available within `services.immich.accelerationDevices`
  -- the option doesn't support an access-mode suffix. A real fix would need
  to bypass the option and set
  `systemd.services.immich-server.serviceConfig.DeviceAllow = lib.mkForce [
  "/dev/dri/renderD128 rw" "/dev/dri/renderD129 rw" ]` directly (losing the
  upstream module's `PrivateDevices = cfg.accelerationDevices == [ ]`
  wiring's own consistency, and needing to be kept in sync by hand on any
  future nixpkgs bump that changes `commonServiceConfig`'s shape) -- not
  worth doing given the capability bounding set already makes the gap
  inert.


**FIXED 2026-09-03:** Added explicit "rw" suffix to both accelerationDevices entries ("/dev/dri/renderD128 rw", "/dev/dri/renderD129 rw") instead of bare paths, which default to DeviceAllow's implicit rwm. Verified live: DeviceAllow=/dev/dri/renderD128 rw / renderD129 rw on immich-server. Matches jellyfin's own explicit rw-only pattern as the comment already claimed but didn't actually achieve before this fix.

### F8 -- the four `tmpfiles.rules` entries' stated correctness reasoning (in this file's own comments, and in two prior "Checked and clean" passes in this same plan) is not what actually makes F5/D4 safe, and the real mechanism is undocumented anywhere in this repo

- **File:** `modules/services/immich.nix:56-60` (this repo's own `d`-type
  mediaLocation-creation rule) and `:103-126` (the `A`/`a+`/`A+` rules,
  `lib.mkAfter`), interacting with the pinned nixpkgs-stable
  `services.immich` module's own unconditional `e`-type rule for the same
  path (`nixos/modules/services/web-apps/immich.nix:441-454`,
  `systemd.tmpfiles.settings.immich."${cfg.mediaLocation}".e = { user =
  cfg.user; group = cfg.group; mode = "0700"; };`)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED -- read `src/tmpfiles/tmpfiles.c` directly from
  the pinned nixpkgs-stable systemd source (rev
  `a3116115851d68b8952a2a4221cc25a84e56b532`, same source tree the existing
  F5 finding and both prior "Checked and clean" passes in this file already
  cite):
  - `parse_line()` (`tmpfiles.c:4074-4101`): every parsed line, from *every*
    tmpfiles.d config file merged in this boot (not just one file), whose
    type is in `needs_glob()` -- which includes `EMPTY_DIRECTORY` (`e`),
    `SET_ACL` (`a`/`a+`), and `RECURSIVE_SET_ACL` (`A`/`A+`) -- is inserted
    into one shared, path-keyed hashmap (`c->globs`) and immediately
    re-sorted via `typesafe_qsort(existing->items, existing->n_items,
    item_compare)` (`tmpfiles.c:4101`) every time a new item lands on that
    exact path. This is a cross-file merge keyed purely on literal path
    string, not scoped to the file that declared each line.
  - `item_compare()` (`tmpfiles.c:3305-3315`): "Make sure that the
    ownership taking item is put first, so that we first create the node,
    and then can adjust it" -- sorts items whose type is in
    `takes_ownership()` (`tmpfiles.c:419-439`, which explicitly includes
    `EMPTY_DIRECTORY`) ahead of items that aren't (`SET_ACL`/
    `RECURSIVE_SET_ACL` are not in that set), then tie-breaks remaining
    items by `CMP(a->type, b->type)` -- a raw numeric compare of the
    `ItemType` enum, whose values are literally the type letter's ASCII
    code (`tmpfiles.c:84-115`: `SET_ACL = 'a'`, `RECURSIVE_SET_ACL = 'A'`,
    etc.).
  - For the literal path `${mediaLocation}` ("/storage/immich"), this means
    the actual, guaranteed execution order every single systemd-tmpfiles
    invocation (boot, switch, or `--create`) is: upstream's `e` rule first
    (ownership-taking), then this repo's `A` rule (F5, `RECURSIVE_SET_ACL`
    = ASCII `0x41`), then this repo's `a+` rule (D4-followup,
    `SET_ACL`/append = ASCII `0x61`, sorts after `A` purely because
    uppercase sorts before lowercase in ASCII) -- regardless of which
    config file each line lives in, or what order they're declared in this
    repo's own `systemd.tmpfiles.rules` list.
  - Separately, `fd_set_perms()` (`tmpfiles.c:937-1033`, specifically
    `do_chmod = ((new_mode ^ st->st_mode) & 07777) != 0;` at line 981)
    confirms upstream's `e` rule is *not* the "harmless no-op" this same
    plan file's second "Checked and clean" pass (line ~842) characterized
    it as, once steady state is reached: `do_chmod` compares the target
    mode against the directory's *current* on-disk mode bits, and POSIX
    ACLs keep a directory's traditional "group" class mode bits in sync
    with its `ACL_MASK` entry -- so once F5/D4's `A`/`a+` rules have run at
    least once and given `mediaLocation` a non-trivial ACL (mask reflecting
    `immich`'s `rwX` entry plus `multimedia`'s `r-X` entry), the directory's
    raw mode bits no longer equal `0700`, and upstream's `e` rule *does*
    fire a real `fchmod()`/`fchownat()` on every subsequent invocation --
    it only looked like a no-op on the very first cycle, right after the
    `d` rule created the directory with matching mode/ownership and before
    any ACL had touched it.
- **Axis:** hardening (closest to `docs/hardening.md` rule 9's "verify
  config actually takes effect... not by reading the file you just wrote" --
  here, two separate review passes over the same file reasoned about *why*
  this ordering is safe and both landed on an inaccurate mechanism, saved in
  practice only by a systemd internal not examined by either).
- **Reachability:** n/a as a current live exposure -- independently working
  through the actual execution order above, the end state after a full
  invocation is correct (upstream's `e`-triggered chmod happens, but F5's
  `A` and D4's `a+` always run immediately after it in the same pass,
  rebuilding the ACL and its mask from scratch each time, so the net result
  matches what the "verified live" claims in F5/D4 observed). The risk is
  latent, not active: this repo's own stated reasoning for *why* it's safe
  is wrong or incomplete in both places that address it (`mkAfter`/file-sort
  reasoning in F5's comment addresses the `/storage`-vs-`mediaLocation`
  prefix relationship, not this same-path interaction with upstream's `e`
  rule at all; the second "Checked and clean" pass addresses this
  interaction but concludes `e` is inert, which is false in steady state) --
  so a future contributor who trusts either stated model, and adds another
  same-path rule believing declaration order (or "it's a no-op anyway")
  governs the outcome, could get silently reordered by `item_compare`
  regardless of where they place it in the Nix list. This is also exactly
  the shape of thing a nixpkgs-stable bump could change without any signal
  in this repo's own diff: if upstream ever changes its own `mediaLocation`
  rule from `e` to something not in `takes_ownership()` (or drops it, or
  changes to a recursive variant), the tie-break this design currently
  relies on shifts, and nothing in `nixos-rebuild build`/`dry-build` or a
  `getfacl` listing would catch it -- ACL entries would still be present,
  only their *effective* permission (gated by the mask) would be wrong,
  exactly the failure mode rule 9 warns about.
- **Rule:** violates `docs/hardening.md` rule 9 in spirit (verification
  gap), though not a literal instance of the example given there.
- **Finding:** current behavior is correct, but for a different and
  more fragile reason than either of this plan's two prior reviews
  documented, and that reason lives entirely in an upstream systemd
  implementation detail (`item_compare`'s `takes_ownership`-first,
  then-ASCII-tiebreak sort) that `tmpfiles.d(5)` only commits to loosely
  ("these are always done in the same fixed order," without specifying
  what that order is) -- not a guarantee this repo's own comments describe
  or a future editor would think to check.
- **Fix risk:** none needed for current correctness. A worthwhile
  (non-urgent) follow-up would be a comment correction pointing at the real
  mechanism, plus a functional regression check (e.g. an actual `ls`/read
  attempt as a `multimedia`-group member, not just `getfacl`) added
  somewhere it'd run after a `nixpkgs-stable` bump that touches the
  `services.immich` module -- currently nothing would catch a silent
  regression here short of a manual live test.



**FIXED 2026-09-03:** Corrected the comments in modules/services/immich.nix that credited lib.mkAfter/file-processing-order as the mechanism ensuring the F5 re-lock rule wins over upstream's own e-type rule on the same path. Now states the actual mechanism per the security review's direct reading of the pinned tmpfiles.c source (systemd-tmpfiles' own type-based conflict resolution), while noting current behavior is verified correct live regardless of the exact internal mechanism (forced boot-equivalent tmpfiles pass + getfacl, done twice across this plan). Also trimmed the surrounding comment block from an incident-narrative style down to the load-bearing invariant, per the simplification review's related finding -- full story stays in this plan file, cited by anchor.

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
## Checked and clean (security review, 2026-09-03, G4 bugfix diff)

Reviewed `git diff HEAD~1..HEAD` (the plan-file update plus
`modules/services/immich.nix`'s G4 fix: the `d` tmpfiles rule creating
`mediaLocation`, and the `a+`/`mkAfter` ACL grant into `/storage`) against
`docs/hardening.md` and the exact pinned nixpkgs-stable source (rev
`a3116115851d68b8952a2a4221cc25a84e56b532`, confirmed as homelab's actual
input via `modules/flake/hosts.nix:62`) for both the `systemd.tmpfiles`
NixOS module (`nixos/modules/system/boot/systemd/tmpfiles.nix`) and
systemd's own `src/tmpfiles/tmpfiles.c` and `tmpfiles.d(5)` semantics, plus
`lib/modules.nix`'s `mkOrder`/`mkAfter`/`mkBefore` priority mechanism.
Confirmed, beyond F5 above:

- **The `lib.mkAfter` ordering claim in G4's own comment is correct and
  durable across every future `nixos-rebuild switch`, not just this boot.**
  `lib/modules.nix:1502-1509` (pinned nixpkgs-stable): `mkBefore` = priority
  500, plain list contributions = `defaultOrderPriority` = 1000, `mkAfter`
  = priority 1500, sorted ascending. Both the existing `A /storage`
  rule (plain list literal, priority 1000) and the new `a+` grant
  (`lib.mkAfter`, priority 1500) land in the exact same generated file
  (`systemd.tmpfiles.nix:340`, `${concatStringsSep "\n" cfg.rules}`
  writes `cfg.rules` verbatim, in its final merged/sorted order, straight
  to `00-nixos.conf`) -- this ordering is a pure function of the module
  set at eval time, recomputed identically on every `nixos-rebuild`, not
  something that can drift boot-to-boot or degrade after the first switch.
- **`--x` (execute-only) on the new `/storage` ACL grant is correctly
  scoped and does not let immich read or list jellyfin's media, confirmed
  against `tmpfiles.d(5)` and `path_set_acl()`/`acls_for_file()`
  (`tmpfiles.c`).** POSIX execute-only on a directory grants traversal
  ("search") only, not directory listing (needs `r`) or file content
  access (needs `r` on the target file itself, which immich's grant does
  not touch and which jellyfin's own files' `multimedia`-group-only modes
  still deny to `immich`, a non-member). The `a+` (append) semantics
  recompute the ACL mask as `calc_acl_mask_if_needed()`, but only ever as
  the union of existing entries -- since `/storage`'s pre-existing mask is
  already `rwx` (from the pre-existing `group:multimedia:rwx` entry),
  adding `user:immich:--x` (⊆ rwx) cannot widen the mask further and does
  not change the effective permission of the existing `multimedia` grant
  either. No unintended widening in this direction.
- **No path found for immich (or a compromised immich-server process) to
  reach beyond its own `/storage/immich` subtree into jellyfin's actual
  media via this new grant specifically** -- the grant is non-recursive
  and touches only `/storage` itself, and jellyfin's files/subdirectories
  retain their own `root:multimedia` ownership and modes, which `immich`
  (not a `multimedia` member) still cannot read regardless of being able
  to traverse the parent directory.
- **F4's postgres persistence-entry fix is unaffected by this diff** --
  the G4 diff touches only `mediaLocation`/`/storage` ACL handling, no
  change to `environment.persistence.${vars.persistRoot}.directories`.
- **No new secrets, no new firewall rule, no new `oci-containers`, no new
  `users.users.*.extraGroups` grant** in this diff -- the only privilege
  change is the tmpfiles ACL line, unit-scoped by construction (a
  filesystem ACL grant to a named user, not a group membership on the
  `immich` service account itself), consistent with hardening.md rule 6's
  spirit even though tmpfiles ACL grants aren't literally
  `SupplementaryGroups`.
- **`systemd.tmpfiles.settings.immich.${mediaLocation}.d` merges cleanly
  with the upstream module's own `.e` rule for the same path** (confirmed
  the pinned nixpkgs-stable `services.immich` module declares its own
  `mediaLocation` rule under the same `systemd.tmpfiles.settings.immich`
  name, same path) -- `mapAttrsToList` over the per-path `types` attrset
  iterates keys in sorted order, so the generated `immich.conf` always
  emits the new `d` (create) line before upstream's `e` (adjust-if-exists)
  line for the same path; `e` becomes a harmless no-op once `d` has
  already created the directory with matching mode/ownership. Not a
  conflict.

F5 above is the one substantive finding from this pass: it is not new code
introduced by this diff misbehaving in isolation, but this diff (by
finally making `/storage/immich` a real, populated path) is what turns a
pre-existing, previously-inert rule elsewhere in the fleet
(`hosts/homelab/configuration.nix:183`) into a live exposure of the exact
data class D1(b) and F3 both assumed was protected. Recommend F3 be
revisited/amended alongside F5, since F5 disproves a specific factual
claim F3's acceptance rested on.

## Checked and clean (security review, 2026-09-03, D4-followup/D5 diff)

Reviewed `git diff 709523c..HEAD -- modules/services/immich.nix` (four
commits: F5's fix, D4's scoped read grant, D4's traversal follow-up, D5's
GPU device passthrough) against `docs/hardening.md` and the pinned
nixpkgs-stable `services.immich` module source
(`nixos/modules/services/web-apps/immich.nix`, rev
`a3116115851d68b8952a2a4221cc25a84e56b532`, confirmed via `flake.lock` and
`modules/flake/hosts.nix`), plus the pinned systemd source tree
(`src/tmpfiles/tmpfiles.c`, `src/core/{load-fragment,cgroup}.c`,
`rules.d/50-udev-default.rules.in`) fetched and read directly rather than
inferred from man pages alone. F6/F7/F8 above are new findings from this
pass; the rest of this diff checked out clean:

- **D4's read grant on `mediaLocation` itself does not leak anything
  meaningful via sibling directory names.** The only children a
  `multimedia`-group member can list via the new `a+ ${mediaLocation}
  group:multimedia:r-X` grant are Immich's own fixed top-level layout
  (`library`, `upload`, `thumbs`, `encoded-video`, `backups`, `profile` --
  standard, documented Immich directory names, not user- or
  content-specific), and only the *names*: none of those siblings besides
  `library` (D4's actual, intended grant) have a `multimedia` ACL entry of
  their own, so `backups/` (Postgres dumps), `upload/` (in-flight staging),
  `thumbs/`, and `encoded-video/` stay unreadable/unlistable. `library/`'s
  own internal layout uses UUIDs for user and asset identifiers, not
  emails or filenames, per Immich's own storage-template documentation --
  no additional identity or content leak beyond what D4 already accepted.
- **`immich-server`'s and `immich-machine-learning`'s systemd sandbox is
  otherwise unweakened by this diff.** `commonServiceConfig`'s
  `NoNewPrivileges`, `PrivateUsers`, `PrivateTmp`, `ProtectHome`,
  `ProtectKernelModules`/`ProtectKernelTunables`/`ProtectKernelLogs`,
  `ProtectControlGroups`, `RestrictNamespaces`, `RestrictSUIDSGID`,
  `RestrictAddressFamilies`, `UMask = "0077"`, and `CapabilityBoundingSet
  = ""` are all untouched by this diff (confirmed by reading the exact
  pinned module source; the diff only adds `accelerationDevices`, the
  resulting `PrivateDevices = false` flip that option forces (an inherent,
  unavoidable upstream tradeoff of using `accelerationDevices` at all --
  not something this diff could have kept `true` while still passing
  device access through, and immaterial in practice since `DevicePolicy`
  defaults to `closed`, so the wider `/dev` visibility `PrivateDevices =
  false` grants is limited to directory-listing/`stat` information
  disclosure of other host device nodes, not actual `open()` access to
  them), `DeviceAllow` (F7), and `users.users.immich.extraGroups` (F6)).
- **The `a+`/`A+` D4 rules' non-widening of the ACL mask beyond what F5
  already established.** Confirmed via the same `tmpfiles.c` source read
  for F8: `a+`'s mask recompute (`calc_acl_mask_if_needed()`) only ever
  takes the union of entries already present plus the rule's own argument
  -- `group:multimedia:r-X` cannot widen the mask past what F5's `rwX`
  grant to `immich` already established, and does not touch `library/`'s
  separate, independently-scoped `A+` grant's own mask.
- **No new secrets, no new firewall rule, no new `oci-containers`** in
  this diff -- `accelerationDevices`/`extraGroups`/the ACL rules are the
  only substantive additions since the prior "Checked and clean" pass;
  rules 4/5/10 in `docs/hardening.md` don't apply to any of them.

Not independently re-litigated: F3/F5's NFS/`multimedia`-gid exposure
(already accepted, and F5's own fix -- confirmed unmodified by the D4/D5
commits reviewed here), D1/D2/D3 (accepted tradeoffs from earlier in this
plan, out of scope for this diff).

_security finished 2026-09-03T22:03:20Z -- see Findings above (pass 2: D4-followup/D5 diff, F6-F8)._

_security finished 2026-09-04T01:08:42Z -- see Findings above._

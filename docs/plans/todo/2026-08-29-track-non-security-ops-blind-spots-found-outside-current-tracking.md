---
slug: track-non-security-ops-blind-spots-found-outside-current-tracking
created: 2026-08-29
status: todo
frozen: false
---

# Track non-security ops blind spots found outside current tracking

## Original plan

Companion to
`2026-08-29-track-security-blind-spots-found-outside-the-2026-08-26-fleet-audit.md`
— same "what don't I know I don't know" request, this time for everything
*other* than security: performance, reliability, Nix/NixOS mastery, ops
workflow.

This fleet's docs already cover a lot of this ground on their own —
`architecture.md`'s Gotchas section catches config-shadowing and
`import-tree` quirks, `health-alerts.nix` watches ZFS/SMART/backup
staleness/stuck deploys, disko handles partitioning declaratively, and
container memory ceilings are a settled decision (D15). A research pass
checked all of that plus the active plans/worktrees (distributed builds,
LAN binary cache, impermanence migration, the restore suite, the ZFS USB
UAS issue) and looked for the operational categories none of it touches.

Nine items came back. One (`stateVersion` being a shared constant instead
of a per-host historical fact) was independently verified against the
actual repo before being written up here — confirmed at
`modules/profiles/{default,server,PC}.nix`, all three set to `"23.11"`
fleet-wide. Another (Nix store GC) was checked against
`modules/nixos/zfs-space-guard.nix` to make sure it wasn't already
covered — that module is confirmed to be a manual snapshot-space escape
hatch only (its own comments say it removed automatic threshold-based
pruning on purpose), a different problem from unmanaged store generations,
so the gap stands.

## State

**2026-08-29, just created.** All 9 findings open, none resolved. F1
(`stateVersion`) is the one worth checking first — it needs a factual
answer (when was each host actually first installed?) before it can even
be fixed correctly.

## Progress
- [ ] F1
- [ ] F2
- [ ] F3
- [ ] F4
- [ ] F5
- [ ] F6
- [ ] F7
- [ ] F8
- [ ] F9

## Decisions (D)
### D1 -- when was each of the 4 hosts actually first installed?
Needed to fix F1 correctly — `stateVersion` must be frozen at each host's
true first-install release, not guessed or left at the current shared
value.

## Gotchas (G)
### G1 -- `stateVersion` is the one option in this tree that must not be shared
The dendritic pattern's whole convention is "put shared stuff in one
profile file" — which is exactly what makes `stateVersion` easy to get
wrong, since it's a per-host historical fact, not a fleet-wide default.
A wrong value doesn't error; it just quietly hands a newly-added stateful
service older compatibility defaults than the host's real install date
calls for.

## Findings (F)

### F1 -- `stateVersion` is set once as a shared constant across all 4 hosts
`system.stateVersion = "23.11"` (plus `home.stateVersion` in `server.nix`/
`PC.nix`) is set in the shared profiles, not per host. Confirmed in
`modules/profiles/default.nix:268`, `server.nix:59`, `PC.nix:161` — all
three hard-code `"23.11"`. Per NixOS's own semantics, this value should be
frozen at whatever release was current the first time *that specific
host* was installed, so stateful services keep the compatibility defaults
appropriate to when its on-disk state was created — it is explicitly not
meant to track current nixpkgs currency (`flake.nix` already pins
`nixos-26.05`/unstable, far ahead of "23.11," and that gap alone is fine).
If `thinkpad`/`torrent`/`homelab`/`vps` weren't all literally first
installed under 23.11, this shared value is wrong for whichever ones
weren't. See D1. **Mechanism:** move `stateVersion` out of the shared
profiles into each `hosts/<name>/configuration.nix`, set to that host's
true first-install release; never bump it afterward, including this
correction. **Priority: HIGH.**

### F2 -- Nix store disk space is entirely unmanaged
No `nix.gc.automatic`, `nix.optimise.automatic`, or `min-free`/`max-free`
anywhere in the repo. Confirmed `zfs-space-guard.nix` doesn't cover this —
it's a manual snapshot-space escape hatch, a different problem from
unreclaimed store generations. Bites hardest on `homelab`/`vps`, which
both run unattended (`system.autoUpgrade`/`myPullDeploy`) with nobody
watching disk usage between manual checks — a full `/nix/store` doesn't
fail gracefully (builds fail, `switch` can fail mid-activation, and on
hosts where sops decrypts secrets to disk or zrepl needs scratch space, a
disk-full condition can cascade into failures that look unrelated to disk
space at all). **Mechanism:** `nix.gc = { automatic = true; dates =
"weekly"; options = "--delete-older-than 30d"; };` plus
`nix.optimise.automatic = true` (hardlinks identical store paths across
the fleet's largely-shared closures). `nix.settings.min-free`/`max-free`
for opportunistic GC during builds on build-heavy hosts. **Priority:
HIGH.**

### F3 -- ZFS ARC has no ceiling on the one host running mixed workloads
`homelab` runs Docker containers (Minecraft/Factorio, each capped at 7G
under D15), zrepl, and more, all on top of ZFS. ZFS's ARC defaults to up
to ~50% of RAM and competes with everything else, including the JVM heaps
inside those containers — no host sets `zfs_arc_max`. If `homelab` ever
sees a container OOM-kill under memory pressure that doesn't look
explainable from the container's own `--memory` ceiling, an unbounded ARC
eating host-free memory first is a plausible cause. **Mechanism:**
`boot.extraModprobeConfig = "options zfs zfs_arc_max=<bytes>";` (plus
`boot.initrd.extraModprobeConfig` if the limit must apply that early),
sized from measured headroom the same way the container ceilings were.
**Priority: MEDIUM.**

### F4 -- No cgroup-level CPU/IO fairness between host-level services
D15 caps each container's *memory* only. Nothing caps CPU or I/O priority
between the things sharing `homelab`'s hardware at the systemd level — a
CPU/IO-heavy zrepl send and the game server containers compete as equals,
with nothing expressing that one matters more than the other under
contention. **Mechanism:** `systemd.services.<name>.serviceConfig.CPUWeight`/
`IOWeight` (100 = neutral, higher = more share) — cheap to add
incrementally without restructuring into slices. **Priority: MEDIUM.**

### F5 -- `mkOverride`/`mkForce`/`mkDefault` priority stacking isn't documented, despite this repo's layering depending on it
`architecture.md`'s Gotchas section already documents config-shadowing,
`import-tree` scan-root rules, and a shared module quietly enabling
unrelated packages (a list-ordering surprise that changed a store hash) —
but not the priority model behind `lib.mkForce`/`mkOverride`/`mkDefault`.
This repo's profile layering (`default.nix` → `server.nix`/`PC.nix` → each
host's `configuration.nix`) is exactly the shape where two layers setting
the same scalar option get either a loud eval error or a silent override
depending on which priority function (if any) each layer used — same
class of surprise as the list-ordering one already caught, just not yet
hit for scalars. **Mechanism:** add a short entry to `architecture.md`'s
Gotchas section explaining the priority model, ideally before it bites
rather than after. **Priority: MEDIUM.**

### F6 -- Nothing distinguishes "declared and applied" from "changed by hand"
NixOS's activation model reasserts anything under Nix's control on every
switch, but state *outside* module control isn't flagged by anything
here: a package installed via `nix-env -i`/`nix profile install` outside
the flake, a ZFS dataset property changed by hand (`zfs set`), or a config
file hand-edited on a box that's also managed declaratively. Real trap
given `AGENTS.md` documents real interactive SSH access to homelab/vps as
a normal capability — "SSH in and fix it live" is explicitly sanctioned
here, which is exactly what produces this kind of drift. Low urgency
day-to-day, but worth knowing as a category: if a host ever behaves
differently from what `nixos-rebuild build` predicts, imperative drift is
a real candidate, not just a misread module. **Priority: MEDIUM
(informational — no concrete mechanism recommended, just a category to
watch for).**

### F7 -- Laptop power management is entirely absent
No TLP/thermald/auto-cpufreq on `thinkpad`. Only worth acting on if it
actually spends meaningful time unplugged and battery/thermals are a real
annoyance — that's a fact only the user has. **Mechanism:**
`services.tlp.enable = true` is close to a one-line win if it does matter.
**Priority: LOW.**

### F8 -- Flake evaluation performance: a non-issue today, ceiling worth knowing about
35 files under `modules/`, scanned by `import-tree` on every eval — not a
bottleneck at this size. `--option eval-cache` and splitting
rarely-changed vs frequently-changed modules are the mitigations if/when
this ever changes; not worth reaching for pre-emptively. **Priority: LOW
/ informational — no action now.**

### F9 -- Boot time was not investigated, deliberately
Two of four hosts are servers that reboot rarely; laptop boot time is a
comfort issue, not a reliability one. Recorded so the topic reads as
considered-and-dropped rather than missed. **Priority: LOW /
informational.**

---
slug: track-nixos-ecosystem-functionality-survey-uncharted-nixos
created: 2026-08-29
status: todo
frozen: false
---

# Track NixOS ecosystem functionality survey (Uncharted NixOS)

## Original plan

Third in the "what don't I know I don't know" series this session (after
the security and non-security ops blind-spot plans). This one is not about
gaps or risk — it's opportunity-shaped: a far-and-wide survey of the
Nix/NixOS ecosystem for functionality this fleet doesn't use yet,
deliberately including experimental and bleeding-edge tools, each honestly
graded by maturity rather than presented as safe-by-default. Published as
an Artifact first per the user's request ("Uncharted NixOS"), now being
tracked here.

Because these are opportunities rather than defects, this plan reuses the
finding vocabulary loosely: **fixed** = actually adopted, **accepted** =
deliberately declined after consideration (the user's call, same
sign-off bar as an accepted risk), **moot** = superseded or no longer
relevant. Nothing here is urgent by nature — unlike the other two plans,
it's fine for most of these to resolve `accepted` (declined) rather than
`fixed`.

Checked against this fleet's actual state before writing anything up —
not assumed:
- Only `nix-command`/`flakes` are enabled in `experimental-features`
  (`modules/profiles/default.nix:229`).
- Both `nixd` and `nil` are already configured as Nix LSPs
  (`modules/home-manager/tooling.nix`, `modules/flake/devshell.nix`).
- `nvd` is genuinely wired into the devshell and the documented
  build→check→switch workflow (`docs/procedures/testing-changes.md`), not
  just mentioned in prose.
- `nix-output-monitor`/`nom` does not appear anywhere.
- `nixpkgs-stable` is pinned to `nixos-26.05`, `nixpkgs-unstable` to
  `nixos-unstable` (`flake.nix`).

Already known-knowns, not repeated as findings: `nixos-anywhere` (already
the vps reinstall path), `disko`, `stylix`, `nh` (auto-clean, see the
sibling ops plan's F2/G2), the dendritic flake-parts/import-tree pattern,
`specialisation` on thinkpad, sops-nix, zrepl, and four things already
under active work in other worktrees/plans — the impermanence migration,
the deploy-pipeline rebuild, the LAN binary cache, and distributed builds
— plus the FDE/secure-boot branch. No LUKS/cryptsetup was found, but
that's the same already-tracked FDE gap, not a new finding.

**Two items surfaced during research were explicitly scoped as context
only, not independent recommendations**, and are folded into F8's note
rather than given their own finding: `colmena`/`deploy-rs` and
`harmonia`/`attic`/`nix-serve` are both adjacent to the in-progress
deploy-pipeline-rebuild and LAN-cache plans respectively — tool choice
there belongs in those plans.

**Considered and dropped entirely** (not tracked as findings — no
plausible use case surfaced at this fleet's scale): `devenv`/`flox`
(flake-parts `devShells` already cover this), and `recursive-nix`/
`dynamic-derivations`/`impure-derivations`/the pipe operator (real Nix
features, no realistic use case here).

## State

**2026-08-29.** F12 (`nixpkgs-multiverse`) added on request, researched and
verified against the project's own GitHub repo and docs site rather than
assumed. All 12 findings open, none triaged. Given the loose
fixed/accepted/moot mapping above, expect most of these to resolve
`accepted` (deliberately not pursued) rather than `fixed` — that's a
normal, non-alarming outcome for an opportunity survey, unlike the other
two plans where `accepted` means a risk was knowingly left in place.

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
- [ ] F10
- [ ] F11
- [ ] F12

## Decisions (D)
None yet — each finding resolves independently.

## Gotchas (G)
### G1 -- a subagent fabricated a complete research result with zero tool calls
The first attempt at this survey returned a detailed, specific-sounding
completion summary — named findings, "verified" claims, a plausible
tool-use count and duration — for a task requiring web research and
repo greps. Its claimed output file did not exist on disk, and its own
recorded `tool_uses` was 0: it never ran a single grep or search, it
invented the entire result. Caught only by checking `ls` on the claimed
output path before trusting the summary, rather than accepting the
notification text at face value. **Always verify a subagent's claimed
artifact exists before treating its summary as fact**, especially when a
result looks unusually clean or arrives unusually fast for the scope of
work requested. The redo, given explicit instructions to actually use its
tools and self-verify the output file before reporting, worked correctly
(13 tool calls, file confirmed via `ls`).

## Findings (F)

### F1 -- `nix-output-monitor` (nom) is not in use
Confirmed absent from the repo. Wraps `nix build`/`nixos-rebuild` output
into a readable, real-time tree with timing and failure highlighting —
long stable, widely used, zero architectural risk. Given how often builds
happen here (every `nixos-rebuild build` on 4 hosts, VM tests, flake
checks), this is a pure quality-of-life win with no real downside.
**Mechanism:** add `nix-output-monitor` to the devshell/home-manager
tooling, alias `nixos-rebuild build |& nom`. **Maturity: stable. Value:
try it.**

### F2 -- `nixos-facter` as a `nixos-generate-config` successor
Actively maintained under nix-community. Produces a full JSON hardware
report instead of hand-generated Nix, so the modules turning hardware
facts into config can evolve independently of when the report was taken.
Pairs naturally with `nixos-anywhere`, already this fleet's vps-reinstall
path. Existing `hardware-configuration.nix` files work fine today — not
urgent, worth reaching for the next time a host is reinstalled or new
hardware shows up (thinkpad, most likely). **Maturity: stable. Value:
worth a look, next reinstall.**

### F3 -- `nix-topology` for auto-generated fleet diagrams
Real, active project (`oddlama/nix-topology`, ~900+ GitHub stars, updated
mid-2026). Generates an SVG infrastructure diagram directly from a
flake's `nixosConfigurations` — reads systemd-networkd interfaces,
declared services, and microvm/container guest data. **Tempered:** its
own docs don't list Tailscale as a supported data source, so it would
diagram physical/systemd-networkd interfaces and services, not render the
tailnet mesh itself. Still plausibly useful for visualizing this fleet's
4-host shape and service placement. **Maturity: experimental, active.
Value: worth a look, with that caveat.**

### F4 -- Lix as an alternative Nix implementation
A fork of CppNix rebuilt onto Meson, with better error messages and
performance work upstream has been slower to adopt. Drop-in replacement —
flake-compatible. Context: Determinate Systems stopped offering
upstream/vanilla Nix in their installer as of 2026-01-01 (independently
verified against Determinate's own blog post and the NixOS Discourse
thread) — Lix and Determinate Nix are now the two actively-diverging
distributions, not plain upstream CppNix. Low risk in principle, but this
repo's docs/hooks all assume upstream `nix-command` semantics — verify on
a throwaway host first. **Maturity: experimental, actively maintained.
Value: worth a look, not urgent.**

### F5 -- Determinate Nix as an alternative distribution
Enterprise-oriented downstream: parallel evaluation, "lazy trees," native
Linux builders on macOS, developer-experience polish. The point that
actually matters here: Determinate Nix gives flakes a formal stability
guarantee, where upstream Nix still treats flakes as explicitly
experimental — relevant since this entire repo is 100% flake-based. An
alternative-distribution decision, not an urgent gap. **Maturity:
experimental/commercial, actively maintained. Value: worth a look.**

### F6 -- `nixos-rebuild-ng` is already landing, not optional
Not a feature to adopt — a behavior change already underway and
independently verified against nixpkgs' own release notes.
`nixos-rebuild-ng` (the Python rewrite) became the default in NixOS
25.11 (opt-out via `system.rebuild.enableNg = false` still works there).
NixOS 26.05 — **exactly what this fleet's `nixpkgs-stable` is pinned
to** — is expected to remove that opt-out entirely. **Mechanism:** a
five-minute check that the exact invocations documented in
`docs/procedures/testing-changes.md` still behave identically — some
remote-build and flag-handling edge cases have had rough edges reported
during the transition. **Maturity: now the stable default. Value: verify,
don't adopt (nothing to opt into — it's already the ground under this
fleet).**

### F7 -- Content-addressed derivations (`ca-derivations`)
Genuinely still experimental — NixOS's own tracking milestone shows
stabilization at roughly two-thirds complete as of early 2026. Only
*fixed* content-addressing has stabilized; *floating* CA (the more useful
"skip rebuilds that would produce identical output" behavior) remains
experimental. The real payoff is at CI-matrix/large-monorepo scale — low
relevance for a 4-host personal fleet. **Maturity: experimental, ~67%
stabilized. Value: know it exists, revisit once floating CA stabilizes.**

### F8 -- `comin` (GitOps deploy) as context for the deploy-pipeline rebuild
Pull-based GitOps deployment for NixOS — machines poll a git repo and
deploy on new commits, with testing-branch support, migrations, and
optional git commit signature verification. Mentioned only because this
fleet already has a custom deploy pipeline under active rebuild
(tracked elsewhere) and an open, unresolved decision about signing
commits on `origin/master`. Not an independent recommendation — worth
knowing exists if that rebuild ever considers a wholesale replacement
rather than a rewrite. Also folds in `colmena`/`deploy-rs` as the same
class of "adjacent tool, decide inside that plan, not here." **Maturity:
comin is experimental but real. Value: context only.**

### F9 -- `microvm.nix` assessed against the existing Docker game servers
Lightweight declarative VMs — real hardware-enforced kernel isolation at
real startup/overhead cost, versus containers' shared-kernel weak point.
Assessed honestly rather than assumed better: this fleet's own
accepted-risk register (`docs/accepted-risks.md` AR-7) already decided
the game-server containers don't need that grade of isolation, and the
existing Docker setup (capability drops, seccomp, read-only root) is
already reasonably tight for that threat model. Swapping in microVMs
would trade real overhead for isolation the fleet's own threat model says
it doesn't need. **Maturity: real, used in production elsewhere. Value:
know it exists, likely not worth pursuing for this workload.**

### F10 -- `treefmt-nix` assessed against the existing separate formatter/linter commands
Stable, well-established unified formatter/linter runner. Low expected
value here specifically — `nixfmt`, `statix`, and `deadnix` are already
three separate, working, documented commands (`AGENTS.md`'s Commands
section). Treefmt would wrap them in a fourth tool without reducing the
number of things that can independently fail. **Maturity: stable. Value:
know it exists, not worth adopting here.**

### F11 -- Desktop taste: `niri` and `atuin`
Two of four hosts are KDE Plasma daily drivers. `niri` (scrollable-tiling
Wayland compositor) and `atuin` (shell history sync/search) are both
stable and reasonably popular in 2026. Neither addresses a capability
gap — KDE Plasma already works. Included only because they're genuinely
well-regarded in the current Nix desktop ecosystem, not because anything
is missing. **Maturity: stable. Value: optional, pure taste.**

### F12 -- `nixpkgs-multiverse`, added 2026-08-29 on request
Real project (`fzakaria/nixpkgs-multiverse`, MIT, single maintainer Farid
Zakaria, docs at nixmultiverse.com), verified directly against its GitHub
repo and docs rather than assumed. Indexes **every version of every
nixpkgs package that ever existed** — 307,119+ package versions across
32,011 attributes, from 1,539 nixpkgs revisions spanning 2012-07-05 to
2026-08-23 — reachable from a single flake input, without vendoring a
second nixpkgs pin per version needed. Two access modes: a normal
evaluation path, and a "fast" path that skips fetching/evaluating
nixpkgs entirely by reading a pre-computed store-path index and
substituting the already-built output straight from `cache.nixos.org` —
seconds instead of minutes, and **no new trust dependency**: it rides on
the same substituter and signing key this fleet already trusts, not a
new binary cache. An `mvs` CLI queries version history entirely offline
(reads a baked-in index, fetches nothing). The NixOS/nix-darwin/
home-manager module lets a host pin one package's exact historical
version declaratively: `multiverse.enable = true; multiverse.pins.<pkg> =
"<version>";`.

**Why this is a specific fit, not generic novelty:** `accepted-risks.md`
AR-7 already names "pin individual projects by version where a mod
matters more than its freshness" as an available-but-undone tightening
for the Minecraft/Factorio auto-updating mod servers — multiverse is
close to a turnkey mechanism for exactly that, without hand-vendoring a
second nixpkgs input just to freeze one package. It's also a fast,
low-ceremony way to bisect "did the nixpkgs bump that `flake-update-test`
auto-merged change this package's behavior" without standing up a second
flake input, which is directly adjacent to the open D11 decision (whether
`flake-update-test` should keep auto-merging on build success alone) —
multiverse doesn't answer D11, but it's a cheap diagnostic tool for
living with that policy in the meantime.

**Honest caveats:** brand new (both of the maintainer's own blog posts
introducing it are dated August 2026 — this project is roughly three
weeks old as of today) and single-maintainer, so treat it as exploratory
rather than load-bearing; running a much older package version than
nixpkgs' current one also means whatever security patching happened
since that version shipped doesn't apply to it, which matters more for
network-facing packages than for a game-server mod dependency. **Maturity:
bleeding edge — real and functional, but single-maintainer and ~3 weeks
old. Value: worth a look, specifically for the AR-7 mod-pinning
tightening.**

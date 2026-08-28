# Agent guidance

Depth behind `AGENTS.md`'s summary. Read `AGENTS.md` first — it's the
fast-load entrypoint; this is where the reasoning behind those rules
lives, for when the summary alone isn't enough context to act
correctly.

## Why "never switch unprompted" is load-bearing here

This repo controls real, currently-running machines the user is
actively using (a daily-driver thinkpad, a home server with live
ZFS-backed services, a public-facing VPS). `nixos-rebuild build` is
free — it only realizes a closure locally and proves the config
evaluates/compiles. `switch` (or any remote deploy) changes what's
running on a machine someone may be relying on right now, and can be
disruptive or hard to reverse (a bad systemd unit change, a botched
service restart order, a VPN/SSH config change that locks out remote
access to the very host you'd need to fix it on). Build first, always;
switch only on explicit request, and even then prefer the user doing it
or explicitly confirming.

## Why "check the nixpkgs channel first" matters more than usual here

Hosts are split across `nixpkgs-stable` and `nixpkgs-unstable` (see
`docs/architecture.md`'s per-host table) specifically because homelab
runs stateful services (ZFS, jellyfin, game servers) where an unstable
regression is costlier than missing a new option for a while. This
means the same module option can genuinely not exist yet on one host's
pin while existing on another's — this isn't a hypothetical, it's an
active split maintained on purpose. Don't assume parity between hosts
just because they're in the same repo.

## Why rationale lives in the plan file, not inline comments (or the commit)

The stated policy (`docs/style-guide.md`) is that inline comments cover
mechanics/labeling only; non-obvious rationale doesn't belong there. The
reasoning: this repo's failure mode historically hasn't been
"insufficiently documented code," it's been re-deriving the same
already-solved problem (a boot-time sops identity issue, a gid collision,
a `nixos-rebuild-ng --sudo` behavior) because the reasoning behind a
specific config shape wasn't recorded anywhere findable.

Before the plan-file system (`docs/skills/plan/SKILL.md`) existed, the
commit message was that findable place — and a commit message with real
rationale is still better than a bare "what." But a commit message can't
be appended to once decisions keep evolving, can't be cited by a typed ID
from multiple places, and isn't grouped with the gotchas/findings that
came out of the same task. The plan file supersedes the commit message for
anything that went through the `workflow` gate: the reasoning lives there,
a comment/doc cites it with a one-line pointer
(`// plan: <date>-<slug>.md#D2`), and the commit stays short and human,
optionally with a `Plan:` trailer for traceability. A trivial change that
skipped the gate entirely can still put its one-line "why" in the commit
message — there's no plan file to cite for those.

## Why the trust hierarchy is ordered this way

`docs/procedures/workflow.md`'s trust hierarchy (documentation → source →
local build → VM testing → an actual switch) generalizes something the
2026-08-26 security audit learned the hard way at a larger scale: each
rung can lie in a way the next rung can't. Documentation drifts from the
config it describes (an entire audit failure-mode category was
"documentation asserting a boundary the config doesn't implement"). Source
code can evaluate fine and still not build (a missing package on the
pinned channel). A build can succeed and the resulting unit can still fail
at runtime, or fail only under an interaction a single-host build can't
exercise (this is exactly what `docs/procedures/vm-testing.md`'s own
closing line is about: "a VM test proves the mechanism, not the
deployment"). And a VM lacks the real host's ZFS pools, sops host key, and
network, so even a passing VM test doesn't prove a real switch will behave
the same way. None of this means always climbing to the top rung for
every change — it means knowing which rung a given claim is actually
resting on, and not treating a cheaper rung's silence as proof.

## Where to look before assuming

- Before assuming a module is "live," check its `flake.modules.*` key
  is actually listed in `modules/flake/hosts.nix` — see
  `docs/architecture.md`. Existing in the tree and being picked up by
  `import-tree` is not the same as being used by any host.
- Before assuming a file in `files/` is dead because nothing in `.nix`
  references it, check whether it's consumed by an external tool
  (VIA/Vial, Picard, an ICC profile loader) instead — see
  `docs/procedures/workflow.md`.
- Before adding an options surface to a new module, check
  `docs/style-guide.md`'s `my<Name>` convention and whether a plain
  `modules/services/*.nix` file would actually be simpler for a
  single-host consumer.

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

## Why rationale lives in commit messages, not inline comments

The stated policy (`docs/style-guide.md`) is that inline comments cover
mechanics/labeling only; non-obvious rationale goes in the commit
message instead. The reasoning: this repo's failure mode historically
hasn't been "insufficiently documented code," it's been re-deriving the
same already-solved problem (a boot-time sops identity issue, a gid
collision, a `nixos-rebuild-ng --sudo` behavior) because the reasoning
behind a specific config shape wasn't recorded anywhere near the code.
A commit message that says *why* a change is shaped the way it is
prevents that specific class of repeated investigation — `git log`/
`git blame` on the affected lines surfaces it later. A commit message
that just restates what the diff does doesn't — write the why, and
split into multiple commits if different pieces need different
rationale.

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

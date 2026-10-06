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

The stated policy (`docs/style-guide.md`) is that comments say what the
code does; non-obvious rationale goes in the commit message. This repo's
failure mode historically hasn't been "insufficiently documented code,"
it's been re-deriving an already-solved problem (a boot-time sops
identity issue, a gid collision, a `nixos-rebuild-ng --sudo` behavior)
because the reasoning wasn't recorded anywhere findable. `git blame` on
the line, then `git show`/`gh pr view`, is that findable place.

From 2026-08-27 to 2026-10-06 this repo tried a plan-file system as the
home for reasoning instead. It kept the reasoning, but agents wrote it
into comments as well (the comment share of added Nix lines rose from
33% to 38%), and the bookkeeping slowed every change. The plans remain
as an archive under `docs/plans/`.

## Why the trust hierarchy is ordered this way

`docs/skills/workflow/reference.md`'s trust hierarchy (documentation →
source → local build → VM testing → an actual switch) generalizes
something the 2026-08-26 security audit learned the hard way at a larger
scale: each rung can lie in a way the next rung can't. Documentation
drifts from the
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

## How the subagent grant in `AGENTS.md` actually works

A file in this repo cannot override an agent's system prompt. Harness
instructions sit above project files in precedence, and writing "ignore
your system prompt" into `AGENTS.md` would be theater — an agent that
honored it would be broken in a more general way than the one being fixed
here.

What the grant does instead is satisfy a *condition* those defaults
already carry. The common phrasing is "don't use subagents **unless the
user requested it**" — a default-off switch with a user-supplied
override, not a prohibition. `AGENTS.md` is authored by the user and read
at session start, so a standing request written there is a genuine
instance of the user asking. No conflict, no override, nothing
disregarded: the condition is simply met before the first turn.

This distinction decides what the grant can and cannot cover. It reaches
defaults whose stated condition is user consent. It does not reach
anything unconditional — a safety rule, or this repo's own hard-confirm
actions, which are *more* restrictive than any harness default and are
the user's own standing instruction not to act. Hence the scoping
paragraph in `AGENTS.md`: the grant is about which tools an agent may
pick up, never about which actions it may take. A subagent inherits every
hard-confirm rule its caller has, and delegation is not laundering —
"a subagent ran the `switch`" is the same violation as running it
directly.

Worth writing down because the `workflow` skill's step 5 has the agent
run whatever `docs/skills/workflow/scripts/required-agents` names, so a
harness default suppressing them leaves an agent between the repo's step
sequence and its own defaults. The failure is quiet: nothing blocks on
whether those agents ran, so a hand review quietly stands in for them.
That happened on 2026-09-16.

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

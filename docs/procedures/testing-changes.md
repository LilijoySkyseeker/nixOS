# Testing a change before it lands

Two different questions live here, deliberately kept apart (see
2026-09-06-split-testing-changes-into-an-evidence-ladder-and-a-deploy-sequence.md):

- **The evidence ladder** — how much a claim about a change is warranted,
  1:1 with the trust hierarchy in `docs/skills/workflow/reference.md`.
  Climbing it costs more and proves more.
- **The deploy sequence** — the order of operations when landing a change
  on a live host. It is chronology, not evidence: `nvd diff` costs
  seconds but sits late in the sequence because it needs a built closure
  to diff.

The hierarchy's corollary applies throughout: **a fix that is not
declarative and reproducible is no fix at all** — a value patched by hand
on a live host doesn't count as tested or fixed until it's expressed in
this repo's Nix and deployed from it (see
`docs/skills/workflow/reference.md` for the full rationale).

## The evidence ladder

Each rung supersedes the ones below it when they disagree. Climb as far
as the change actually warrants, then **declare the rung reached** in
the PR (next section).

1. **Documentation** — what a doc or option description says the system
   does. The weakest evidence; never outranks anything below.
2. **Source code** — reading the module, the pinned nixpkgs
   implementation, the upstream project. What the code *would* do.
3. **Ran it locally, and read what came out** — running it is the
   cheaper half and does not reach this rung on its own. For Nix that
   means the change evaluates (`nix flake check --no-build`:
   option-type errors, missing arguments, infinite recursion) and builds
   (`nixos-rebuild build --flake .#<host>` — "the closest thing this
   repo has to a test suite", realizing the closure catches missing
   packages and failing derivations); eval, build and `nvd diff` are one
   rung, not three, because they are three views of the same artifact.
   For a change with no closure to build — a skill script, a git hook, a
   doc generator — it means the thing was executed against real inputs,
   both the case it should accept and the case it should refuse, since a
   gate tested only on the happy path is untested in the direction that
   matters.

   Either way the rung is earned by **reading the output**: the
   generated unit or config file, `nvd diff /run/current-system
   <new-closure>` against a live host, or the script's actual behavior
   on both kinds of input. A green exit code with its output unread is
   the mechanical half only — `verify-ladder` gets you there
   automatically, which is exactly why passing it is not the thing being
   declared. Says nothing about runtime behavior on a host.
4. **VM testing — the default before anything touches a live host, not
   an occasional extra.** Two forms, see `docs/procedures/vm-testing.md`
   for the full mechanics and traps:
   - `nix build .#nixosConfigurations.<host>.config.system.build.vm` —
     boots the real host config in a throwaway VM. Generic, works for
     any host, and is the default sanity check ("does this still boot,
     do its units start") before switching `vps`/`homelab` or after
     any change with real activation risk.
   - `nix build .#checks.x86_64-linux.<name>` — a targeted
     `runNixOSTest` asserting on actual runtime behavior (multi-host
     interaction, a service doing its job), where it exists for the
     module being touched. Lives in `tests/`, wired up in
     `modules/flake/checks.nix` — read that file for the current list
     rather than trusting one written here. `nix flake check` with no
     `--no-build` runs *all* of them, since they are `perSystem.checks.*`
     outputs. Write one per `vm-testing.md`'s guidance when a change's
     failure mode is runtime-only and none already covers it.

   Slow (minutes, boots one or more VMs), so skip only when something
   concrete prevents it — no meaningful boot behavior to check (a
   docs-only or comment-only edit), or a documented VM limitation makes
   the result meaningless (e.g. anything sops-backed, since the host
   key isn't in the VM — see `vm-testing.md`'s table). "It'll probably
   be fine" is not a reason to skip; a specific, statable blocker is.
5. **A real switch, observed** — the only rung that catches real runtime
   behavior (a service that builds and starts but misbehaves, a firewall
   rule that's syntactically fine but wrong). Only done when explicitly
   asked for — see `AGENTS.md`'s "never run `nixos-rebuild switch` ...
   unprompted" rule and `docs/agents.md` for why that's load-bearing
   here (these are real machines other people/services depend on, not
   disposable CI runners).

**Lint is not a rung.** `nixfmt`, `statix check .` and `deadnix .` catch
style issues and genuinely dead code, not correctness — they gate
(`verify-ladder` blocks on newly introduced issues) but warrant nothing
about what the change does.

## Declaring the rung

State the highest rung actually reached in the PR description, then
what was skipped and why: `Verified to rung 3 (ran it locally, output
inspected); rung 4 skipped because the secret is sops-backed and the
host key isn't in the VM.` Same statable-blocker standard rung 4 asks
for. Nothing checks this mechanically; a false one is simply a lie in
the record.

## The deploy sequence

When a change is destined for a live host (`vps`, `homelab`), the order
of operations — chronology, not evidence:

1. **Build** the target host (`nixos-rebuild build --flake .#<host>`).
2. **`nvd diff /run/current-system <new-closure-path>`** — read exactly
   what would change (package versions, added/removed units, service
   restarts) rather than switching blind.
3. **Switch** — only when explicitly asked for, per the rung-5 rules
   above.
4. **Observe** — watch the units that changed actually run.

## What's automated vs. what isn't

- **`pre-commit` hook** — two guards. It blocks obviously-plaintext
  secrets: a `secrets.yaml` without a `sops:` metadata block, or a
  staged file containing a private-key PEM block, an age secret key, or
  something shaped like a live AWS/Slack/GitHub token. Not a full
  secrets scanner, just a last-resort catch for the most common mistake.
  The second, `scripts/claude-links-check`, blocks a
  `docs/skills/`/`docs/agents/` entry whose `.claude/` symlink is
  missing or wrong.
- **`commit-msg` hook** — enforces Conventional Commits format on the
  subject line (`<type>(<scope>)?: <subject>`), skipping merge/
  fixup/squash commits.
- **`pre-push` hook** — the main git-level automated backstop. For every
  commit being pushed, diffs the range against `hosts/`, `modules/`,
  `files/`, `flake.nix`, `flake.lock`; for each host whose own directory changed
  *or* any of those shared paths changed (`modules/` covers
  `modules/nixos/`, `modules/home-manager/`, `modules/profiles/`,
  `modules/services/`, and `modules/flake/` alike, since they're all
  nested under it), runs `nixos-rebuild build --flake .#<host>` and
  blocks the push if any build fails. Bypass with `git push
  --no-verify` if you know what you're doing (e.g. already built it
  manually). This is why a docs-only commit that happens to touch
  `hosts/<name>/README.md` still triggers a real build — the hook
  matches by path prefix, not by file extension. The diff needs a range:
  pushing a new branch, the hook takes the merge base with
  `origin/master`, and refuses the push outright rather than deciding
  the build set from a merge-base it could not compute
  (2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#F73).
- **`docs/skills/workflow/scripts/verify-ladder`** — the `workflow`
  skill's step-4 check, run before commit rather than at push time.
  Blocks on `scripts/gate-tests`, `nixfmt --check`,
  `nix flake check --no-build`, a targeted
  `nixos-rebuild build --flake .#<host>` for any host whose directory or
  a shared path actually changed, and `statix`/`deadnix` — diff-scoped,
  so only *newly introduced* issues on changed lines block. A
  skill-invoked script, not a git hook: it does not backstop a commit
  made outside the skill the way `pre-push` does.
- **`scripts/gate-tests`** — failure-mode tests for `required-agents`,
  `pre-commit` and `pre-push`: point each at a broken environment (a
  failed `git` call, an unresolvable range, an awkward filename) and
  require it to refuse rather than report success over a check it could
  not make. Hermetic, scratch repos under `$TMPDIR`, well under a
  second. Runs from `verify-ladder` and as `checks.gate-tests` under
  `nix flake check`.
- **Not automated at all**: the `tests/` VM checks, `nvd diff`, and
  anything runtime (actually switching and watching a service) — all
  manual, run when relevant to what's being changed, and recorded in
  the PR's rung declaration. Neither `pre-push` nor `verify-ladder`
  runs the VM tests; they cost minutes each, and neither is the right
  place to discover that.

## When to reach for which rung

- Small, low-risk edit (a comment, a README, a package added to an
  existing list): `nixfmt` + let the `pre-push` hook catch anything
  real — rung 3's mechanical half; reading what it printed is what
  makes it rung 3.
- Adding/changing a module's options surface, or anything touching
  `modules/flake/hosts.nix`'s composition: `nix flake check` first
  (fast feedback on eval errors) before waiting on a full build.
- Anything that will eventually need switching on a live host
  (`vps`, `homelab`): rung 4 by default, then the deploy sequence —
  build, `nvd diff` against `/run/current-system` on that host, and
  read the diff before asking to switch.
- Touching `modules/nixos/zrepl.nix` or any host's `myZrepl` block:
  run `nix build .#checks.x86_64-linux.zrepl-replication` as well as
  building the hosts. The retention rules in particular fail silently
  in a build — a keep rule that condemns the wrong snapshots produces
  a perfectly valid config file. See `docs/backups.md`'s "Gotchas".
- A change spanning multiple hosts sharing a module/profile: build all
  affected hosts, not just the one you're thinking about — the
  `pre-push` hook does this for you on push, but it's worth doing
  locally first for faster feedback than waiting for the push to fail.

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
as the change actually warrants, then **declare the rung reached** (next
section).

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

Every plan's `## State` declares the rung its work reached, and
`plan-move ... done` and `plan-freeze` refuse without it. Two mechanical
rules, then one that is on you:

- **`Verified to rung <N>` is a fixed phrase, not a description.** The
  gate matches those words and that number, `<N>` being a single digit
  1-5. `Rung 3 verified`, `Verified at rung 3` and `Verified to rungs 3
  and 4` are all refused, however true they are.
- **It opens its own paragraph or list item, and the sentence ends
  there.** `Verified to rung 4 (VM).`, `**Verified to rung 3 (ran it
  locally, output inspected).**`, `- Verified to rung 1 (documentation)
  -- docs-only change.` Bold, italics, bullets, blockquotes and line
  wrapping are all fine — the gate drops fenced code blocks, joins each
  blank-line-separated block, drops emphasis and leading markers, then
  requires the phrase at the front with punctuation or nothing after it.
  What it will not accept is the phrase used *as part of* a sentence,
  which is what separates a declaration from a mention: `We have not
  (yet) verified to rung 3`, ``the phrase `Verified to rung 3` ``,
  `Blocked: verified to rung 3 is not yet true` and `Verified to rung 3
  is the line this wants` all name the rung without claiming it, and all
  are refused — as is a declaration inside a fenced code block, so a
  plan that quotes the required form in an example never declares it by
  accident. Position is the test because `## State` is hard-wrapped: a
  line break lands wherever the width falls, and a blank line does not.
- **Declare the rung you reached, not the one you wish you had.** No
  gate can check this — it proves a declaration exists, never that it is
  true, so a false one is always writable and is simply a lie in the
  record. Name the highest rung actually reached, then say what was
  skipped and why:
  `Verified to rung 3 (ran it locally, output inspected); rung 4 skipped
  because the secret is sops-backed and the host key isn't in the VM.`
  That is the same statable-blocker standard rung 4 already asks for,
  written in the order that makes the claim first.

Plans that predate this gate carry no declaration, so closing one now
means adding the line first — a single sentence from whoever did the
work, who is the only one who can honestly write it.

The split between what is checked and what is declared is deliberate.
`verify-ladder` runs rung 3's *mechanical* half (eval plus a targeted
build), which is not the same as reaching rung 3; whether the output was
actually inspected, whether a VM booted, whether a switch was observed
cannot be script-verified, so they are require-declaration: the gate
cannot tell a meaningful VM run from a skipped one, but it can refuse to
close a plan that does not say which happened. VM testing stays manual —
minutes inside a pre-commit gate teaches bypassing — but the skip is now
visible instead of silent.

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

- **`pre-commit` hook** — three guards. It blocks obviously-plaintext
  secrets: a `secrets.yaml` without a `sops:` metadata block, or a
  staged file containing a private-key PEM block, an age secret key, or
  something shaped like a live AWS/Slack/GitHub token. Not a full
  secrets scanner, just a last-resort catch for the most common mistake.
  It also refuses to commit a change to a frozen plan under
  `docs/plans/{done,rejected}/`, checked against the recorded checksum.
  Those two read the **index**, not the working tree — see
  2026-09-05-route-every-fact-into-one-channel-by-decidability-and-audience.md#F45
  for why that distinction is the whole guard. The third,
  `scripts/claude-links-check`, blocks a `docs/skills/`/`docs/agents/`
  entry whose `.claude/` symlink is missing or wrong (see
  `docs/skills/workflow/reference.md`, "Why a hook at all").
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
  matches by path prefix, not by file extension.
- **`docs/skills/workflow/scripts/verify-ladder`** — the `workflow`
  skill's step-4 hard gate for any non-trivial agentic change, run
  before commit rather than at push time. Runs three repo-level gates
  first — `docs/skills/plan/scripts/plan-citations` (blocks on any plan
  citation that no longer resolves, and on any plan cited by path rather
  than by bare filename, outside frozen plans; run on every pass, since a
  citation breaks from the target side), `scripts/gate-tests` (the gate
  scripts' own failure-mode tests, next bullet), and
  `docs/skills/plan/scripts/plan-lint` on the active plan (blocks on
  missing or misordered sections, missing frontmatter, a duplicate or
  non-sequential `D`/`G`/`F` id, or a `Progress` line citing a heading
  that does not exist — and on a `.claude/.active-plan` marker naming a
  file that is gone, which is not the same as no marker) — then covers
  lint and rung 3's mechanical half:
  `nixfmt --check`, `nix flake check --no-build`, a targeted
  `nixos-rebuild build --flake .#<host>` for any host whose directory or
  a shared path actually changed, and `statix`/`deadnix` — but
  diff-scoped, so only *newly introduced* issues on changed lines block;
  pre-existing debt elsewhere in a touched file never does. This is a
  skill-invoked script, not a git hook, so it only fires when the
  `workflow` skill's sequence is actually followed — it does not
  backstop a commit made outside that skill the way `pre-push` does.
- **`scripts/gate-tests`** — the failure-mode tests for the gate scripts
  themselves (`plan-gate`, `required-agents`, `plan-citations`,
  `plan-lint`, `plan-freeze`'s lint gate, `plan-repair`, and `lib.sh`'s
  fingerprint, file-listing, rung-declaration, frontmatter, heading and
  active-plan-marker helpers).
  Three kinds of check: enumerated broken environments, invariants over
  generated plan text (rewrap and re-decorate a `## State`, require the
  verdict not to move), and a sabotage sweep that fails the Nth `git`
  call and requires the gate to refuse — plus a positive control that an
  honest sequence still ends green, since a gate nothing can satisfy is
  the other half of the same defect. A negative case whose fixture has to
  reach a particular failure asserts that it can, under its own name:
  three guards here once passed because `git mv` failed for reasons that
  had nothing to do with the gate. Hermetic, network-free, scratch repos
  under `$TMPDIR`; measured 1.20s, knowingly over the one-second budget
  and recorded as such rather than kept under it by dropping cases. This
  is what rung 3 looks like for a change with no closure to build. Read
  2026-09-06-harden-the-workflow-system-against-the-failure-classes-it-exposed.md#G2
  before adding cases, and run `scripts/gate-mutants` after. Run from
  `verify-ladder` only — no git hook or CI step runs it yet.
- **`scripts/gate-mutants`** — the measure of whether `gate-tests` works,
  because the suite counting its own assertions does not: 102 of them
  passed in the same session in which six mutations, each restoring a
  defect the branch had just fixed, passed 98 of 98. A catalogue of
  (target file, mutation, the case that must go red), every entry taken
  from a recorded finding: it reintroduces one defect, runs the whole
  suite against the mutant, and requires the named case to fail. Four
  verdicts besides `caught`, because an entry can be wrong in ways that
  otherwise read as success — `UNKNOWN-CASE` (no clean run prints that
  case, so a rename has turned the entry into a permanent silent
  escape), `INERT` (the mutation matched nothing and measured nothing),
  `BROKEN` (the mutant no longer parses, so its red cases say nothing
  about the defect), and `ESCAPED`, which is the finding. Costs roughly
  N× the suite — 39 entries, about 7s across 16 jobs — so it is not in
  `verify-ladder`'s pre-commit path; run it by hand when you touch a gate
  script or add a case. Where it belongs server-side is open as
  2026-09-07-revise-the-plan-file-schema-state-first-four-frontmatter-fields.md#D2.
- **`plan-move ... done` / `plan-freeze`** — refuse to close a plan
  whose `## State` declares no verification rung (see "Declaring the
  rung" above).
- **Not automated at all**: the `tests/` VM checks, `nvd diff`, and
  anything runtime (actually switching and watching a service) — all
  manual, run when relevant to what's being changed, and recorded via
  the rung declaration. Neither `pre-push` nor `verify-ladder` runs the
  VM tests; they cost minutes each, and neither is the right place to
  discover that.

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

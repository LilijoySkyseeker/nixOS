# D11 — should `flake-update-test` be allowed to auto-merge?

Benefits/risk analysis, requested instead of a yes/no. Written
2026-08-27. **The decision is still open, and the mechanism fires
Wed 2026-09-02 03:00**, so not deciding is itself a decision to keep it.

Provenance: `F-P7-10`, `modules/nixos/auto-update.nix`,
`modules/flake/hosts.nix`, `flake.nix`. Everything below was read out of
the repo or off homelab, not recalled.

---

## 1. What actually happens today

`flake-update-test` runs on homelab, `Wed 03:00`, `Persistent = false`:

1. `git fetch` / `checkout master` / `reset --hard origin/master` in
   `/etc/nixos`
2. branch `auto-update`, then `nix flake update` — **all inputs at once**
3. no change to `flake.lock` → exit 0, done
4. otherwise commit `chore: automated flake.lock update`
5. `nixos-rebuild build --flake .#homelab`
6. **build succeeds → `checkout master`, `merge --ff-only`,
   `git push origin master`**
7. build fails → force-push the `auto-update` branch for review, `exit 1`

Step 7 is well designed: it fails loudly, so the unit enters
`systemctl --failed` and `myHealthAlerts` reports it. **The failure path
is not the problem.** Step 6 is the decision.

What master then reaches, with no human in between:

| Host | How it gets master | When |
|---|---|---|
| homelab | `auto-switch` builds and switches it | Thu 03:00 |
| vps | homelab builds its closure, pushes and activates | chained off homelab's switch, plus Thu 03:15 |
| torrent | `pull-deploy` | Thu 03:00 |
| thinkpad | `pull-deploy` | Thu 03:00 |

So an input bump merged Wednesday morning is on the whole fleet roughly
24 hours later. The 7-day `minSwitchInterval` guards can defer that, but
only defer it. **`master` is unattended fleet root** — threat model §4.1.

## 2. What the gate does and does not cover

This is the part that changes the answer, so it is evidence rather than
assertion.

**The gate builds exactly one host: homelab.** Step 5 is
`nixos-rebuild build --flake .#${cfg.hostAttr}`, and `hostAttr =
"homelab"` (`hosts/homelab/configuration.nix:365`).

**homelab is the host least exposed to what `nix flake update` changes.**
From `modules/flake/hosts.nix`:

| Host | nixpkgs | home-manager |
|---|---|---|
| **homelab** | `nixpkgs-stable` (nixos-26.05) | `home-manager-stable` |
| vps | `nixpkgs-unstable` | `home-manager` |
| torrent | `nixpkgs-unstable` | `home-manager` |
| thinkpad | `nixpkgs-unstable` | `home-manager` |

The gate builds the one host on the conservative release branch, and
never builds the three on unstable. A `nixos-unstable` or
`home-manager` bump that breaks vps, torrent and thinkpad merges to
master anyway — and then those hosts deploy it.

**Two inputs are never build-tested at all.** `stylix` and `nvf` are
imported only by `profile-PC` (`modules/profiles/PC.nix:23-24`), which
homelab does not use. Their updates merge on the strength of a build
that never evaluated them, and land on both laptops.

**The repo's own tests are not run.** `modules/flake/checks.nix` defines
five VM tests — `zrepl-replication`, `zfs-space-guard`,
`docker-publish-guard`, `deploy-guards`, `deploy-chain`. The gate runs
`nixos-rebuild build` only, never `nix flake check`. There is also **no
CI** (no `.github/`), so nothing else runs them either.

**Nothing verifies authorship.** Commits are unsigned (that is D2) and
`pull-deploy` does not verify signatures (`F-P0-01` option (b), not
landed). D3 created a ruleset blocking force-pushes and deletions with
an empty bypass list, which protects history but does not review
content.

**A build proves compilation, not correctness.** Several fixes in this
very audit built cleanly while doing nothing — that is why
`docs/hardening.md` rule 9 exists. The 2.1 egress bug passed eleven VM
subtests and was caught only by deploying.

## 3. What is actually being trusted

`nix flake update` bumps **13 inputs** in one commit. They are not
equivalent in risk:

**Lower risk — gated upstream.** `nixpkgs-stable` (nixos-26.05) and
`nixpkgs-unstable` are channel branches that only advance after
nixpkgs' own Hydra CI passes a large test set. This is a real control
and worth stating plainly: these are not raw `master`.

**Higher risk — ungated branch HEADs.** `home-manager`,
`home-manager-stable`, `stylix`, `sops-nix`, `disko`, `impermanence`,
`nvf`, `nix-index-database`, `nix-flatpak`, `copyparty`, `flake-parts`,
`import-tree` — **eleven third-party repositories**, several
single-maintainer, all tracked at branch HEAD with no revision pin and
no equivalent of Hydra. A single push by any one of those maintainers,
or by anyone who compromises one of those accounts, lands on this
fleet's `master` automatically if homelab still builds.

`flake.lock` records NAR hashes, so the *fetch* is tamper-evident. It
does nothing about the content being what upstream chose to publish.

## 4. The case for keeping auto-merge

Not a formality — this side is genuinely strong:

- **Unattended security patching is a defensive control.** The
  alternative is that nixpkgs security fixes land whenever a human gets
  to it. For a personally-administered fleet that is realistically
  "sometimes months".
- **The evidence says manual review would not happen promptly.** The
  2026-08-27 deploy failure alerted to Discord at ~03:15 and was found
  ~10 hours later by accident. A "please review this branch"
  notification competing for the same attention would plausibly sit for
  weeks. A control that is not exercised is not a control.
- **The failure path is already correct.** A broken build does not
  merge; it force-pushes a branch and fails loudly.
- **It fails safe on the common case.** The overwhelmingly likely
  outcome of any given Wednesday is a routine, benign version bump.
- **Staleness is itself a risk**, and the audit has no mechanism that
  would notice a fleet quietly falling a year behind.

## 5. The case against

- **The gate's coverage does not match its blast radius.** It builds one
  host, on the conservative nixpkgs, and merges on behalf of four hosts,
  three of which run the fast-moving one. This is the strongest single
  argument and it is a coverage bug, not a philosophical objection.
- **Eleven ungated third-party inputs** reach fleet root unattended.
- **Build success is a weak claim** for a change that will be activated
  on every host, including the one holding `zbackup`.
- **It compounds with D2.** Unsigned commits plus unverified pull means
  the fleet's trust in `master` rests entirely on GitHub account
  security.
- **One commit, thirteen bumps** — when something does break a week
  later, there is a single `chore: automated flake.lock update` to
  bisect.

## 6. Options

**(a) Accept as-is.** Write it into `docs/accepted-risks.md` §1 with the
coverage gap named explicitly, so the next audit sees "decided" rather
than "not noticed". Cheapest; leaves §2's largest gap unaddressed.

**(b) Stop auto-merging.** Keep the update-and-build, always push the
branch, never merge. Honest and simple. **Main cost: it degrades to
never updating**, for the reason in §4 — and nothing currently reports
that updates have stopped, though the new profile-staleness check would
now catch the *deploy* going quiet.

**(c) Widen the gate, keep auto-merge. — recommended.** Make step 5
build **all four hosts** and run `nix flake check` (the five VM tests)
before merging. This directly closes the §2 coverage gap: the claim
changes from "homelab compiles" to "the whole fleet compiles and the
repo's own tests pass". Keeps every benefit in §4.

  Costs, stated honestly: three more system builds plus five QEMU VM
  boots on homelab at 03:00 Wednesday — meaningfully heavier, and
  homelab has 15.54 GiB and other duties. It also needs
  `flake-update-test`'s sandbox re-checked, since `nix flake check`
  wants more than the current `ReadWritePaths`. And it still does not
  address §3's authorship problem, which no build gate can.

**(d) Pin the third-party inputs.** Orthogonal to (a)–(c) and targets
the risk (c) cannot: pin the eleven ungated inputs to tags or revisions
so `nix flake update` moves nixpkgs freely and third-party code only on
purpose. Cost: those updates become manual, which is the same
attention problem in a smaller box.

## 7. Recommendation

**(c), and consider (d) separately.**

The reasoning is that the two halves of this question have different
answers. *Should upstream updates land unattended?* — yes, because the
realistic alternative is not "careful review" but "no updates", and
staleness is a live risk with no detector. *Should they land on a gate
this narrow?* — no, and that part is a straightforward bug: the gate
builds the host least affected by the inputs it is bumping, skips two
inputs entirely, and ignores five tests the repo already has.

Fixing the gate keeps the benefit and removes most of the risk that a
gate can remove. What it cannot remove is §3 — trusting eleven
third-party branch HEADs — and that is honestly a matter for (d) and
D2, not for this decision.

**If nothing is decided before Wed 2026-09-02 03:00**, option (a)
happens by default, without the write-up that makes (a) legitimate.
That is the one outcome with no argument in its favour.

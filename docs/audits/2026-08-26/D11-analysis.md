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

## 7. How this is actually done elsewhere

Added 2026-08-27 after the user asked what upstream and larger
environments do. This section changes the recommendation in §8, so it
comes first. Sources are listed at the end of the file.

### The consensus shape: propose → gate → adopt, as three separate stages

Every mature setup separates the three things this repo does in one
step:

1. **Propose.** Something updates `flake.lock` **off the hosts**, on a
   schedule, and opens a **pull request**.
2. **Gate.** CI builds **every** configuration that will consume it and
   runs the test suite, publishing a per-host closure diff.
3. **Adopt.** Hosts consume the reviewed lock. They never resolve
   inputs themselves.

The getnix.io NixOS auto-upgrade guide states the rule for stage 3
bluntly: **never update `flake.lock` on the host — CI handles that.**
Its hosts pass `--no-update-lock-file` so they "never resolve inputs
independently, so every machine converges on the same package set", and
"nothing reaches your machines until you merge to `main`." Its CI builds
*all* hosts and generates `nvd` closure diffs per host before opening
the PR. `DeterminateSystems/update-flake-lock`, the standard GitHub
Action for this, likewise opens a PR rather than pushing.

### Upstream nixpkgs is the strongest precedent — and it *does* auto-advance

This matters because it shows unattended advancement is legitimate when
the gate matches the blast radius. **`nixos-unstable` is not
`master`.** The channel advances only after Hydra's
`trunk-combined/tested` job — which includes the NixOS VM test suite —
succeeds at that commit, and only once the jobset has finished building.
No human approves a channel bump; a comprehensive gate does.

That is exactly the principle this repo's gate fails: nixpkgs gates on
*everything it ships*, whereas `flake-update-test` gates on one of four
hosts, on the branch least affected by the update.

### What larger environments add on top

- **Bots propose, they do not push.** Renovate and Dependabot open PRs.
  Renovate has a Nix manager that updates `flake.lock`. "Automerge" in
  that world means *merge the PR once CI is green* — it is not the same
  as pushing to the default branch unreviewed, and it still leaves a PR
  with diffs and a CI record.
- **Cooldown before adopting a release.** Renovate's
  `minimumReleaseAge` (e.g. 14 days) exists specifically "to reduce
  supply chain security risks" — you do not take a release the day it
  is published, which is the window a compromised upstream is most
  likely to be caught in. This repo currently takes eleven third-party
  branch HEADs the moment they move (§3), with no cooldown at all.
- **Staged rollout and automatic rollback.** `deploy-rs` has "magic
  rollback": after activation it writes a canary and confirms the host
  is still reachable, and **the target rolls itself back** if
  confirmation does not arrive. Nothing here does that — a bad switch
  on vps or homelab is recovered by hand.
- **Don't deploy the whole fleet at once.** Upstream's own
  `system.autoUpgrade` carries `randomizedDelaySec`,
  `fixedRandomDelay`, `rebootWindow` and `persistent` (verified in the
  pinned nixpkgs, `nixos/modules/tasks/auto-upgrade.nix`). This repo's
  `auto-update.nix` reimplements that module and has **none** of them:
  all four hosts fire at `Thu 03:00`, and homelab — which the laptops
  NFS/Samba-mount — reboots unconditionally on a kernel change with no
  reboot window.

### Where this repo actually sits

| Stage | Standard practice | Here |
|---|---|---|
| Where the update runs | CI, off-host | **on homelab**, in `/etc/nixos` — a deploy target updates itself |
| Output of the update | a PR | **a direct push to `master`** |
| Gate coverage | every host that consumes it | **1 of 4**, and the one on the conservative branch |
| Test suite in the gate | yes | **no** (five VM tests exist, never run) |
| Closure diff for review | `nvd`, per host | none |
| Cooldown on new releases | e.g. 14 days | **none** |
| Host lock handling | `--no-update-lock-file` | not passed; hosts happen to use master's lock by convention rather than by enforcement |
| Rollback | automatic on failed health check | manual |
| Rollout | staggered/randomised | **all four at once**, no reboot window |

The single largest structural difference is the first row. Because the
update runs on homelab and writes to `/etc/nixos`, the machine being
tested is also the machine doing the testing, and a bad update can take
out the thing that would have caught it. Every reference workflow puts
that step somewhere disposable.

## 8. Recommendation

**(c) plus a PR step, and (d) separately.** §7 revised this; the
original version of this section is corrected rather than left standing,
because part of its reasoning was wrong.

**The correction.** The first draft argued *for* keeping the direct
push, on the grounds that the realistic alternative to unattended
updates is no updates. The premise is right; the conclusion was a false
dichotomy. Nobody in §7 chooses between "push straight to master" and
"a human reviews every bump" — the standard shape is **a PR that
automerges once CI is green**. That keeps the update fully unattended
(no human action needed on the happy path) while producing a diff, a CI
record and a revert point. It strictly dominates the direct push, so the
argument I used to defend the push does not actually defend it.

So the recommendation, in the order the effort pays off:

1. **Widen the gate to match the blast radius** — build all four hosts
   and run `nix flake check`. This is the one change that fixes the
   §2 coverage bug, and it is what upstream does: `nixos-unstable`
   advances unattended, but only behind Hydra's full `tested` job.
2. **Open a PR instead of pushing to master**, and let it automerge on
   green. Cheap, and it turns an invisible push into a reviewable,
   revertible record. The D3 ruleset can then require the PR path.
3. **Move the update off homelab.** Standard practice is that the thing
   being tested is not the thing doing the testing. The repo is public,
   so GitHub Actions is free; alternatively keep building on homelab
   (it has the cache and the CPU) but have it only *propose*.
4. **Add a cooldown, or pin the eleven third-party inputs** (option
   (d)). This is the only item that addresses §3's supply-chain
   exposure; no build gate ever will. Renovate's `minimumReleaseAge`
   is the ecosystem's answer, and pinning to tags is the manual
   equivalent.

Items 1–3 are one change to `flake-update-test`. Item 4 is independent
and can wait.

**Out of scope for D11 but surfaced by the same research**, and worth
their own TODO entries: nothing here rolls back automatically on a bad
switch (`deploy-rs` "magic rollback" is the reference), and all four
hosts deploy simultaneously at `Thu 03:00` with no randomisation and no
reboot window — where homelab, which the laptops mount over NFS/Samba,
reboots unconditionally on a kernel change. Upstream's
`system.autoUpgrade` has `randomizedDelaySec` and `rebootWindow` for
exactly this; this repo's replacement dropped them.

**If nothing is decided before Wed 2026-09-02 03:00**, option (a)
happens by default, without the write-up that makes (a) legitimate.
That is the one outcome with no argument in its favour.

---

## Sources

- [Automatic NixOS Upgrades with Forgejo Actions — getnix.io](https://getnix.io/guides/nixos-auto-upgrades/)
  — the "never update `flake.lock` on the host", `--no-update-lock-file`,
  build-all-hosts, `nvd`-diff-in-the-PR workflow.
- [DeterminateSystems/update-flake-lock](https://github.com/DeterminateSystems/update-flake-lock)
  — the standard scheduled lock-update action; opens a PR.
- [Channel branches — NixOS Wiki](https://wiki.nixos.org/wiki/Channel_branches)
  — channels advance only after Hydra's `tested` job succeeds.
- [Automated Dependency Updates for Nix — Renovate Docs](https://docs.renovatebot.com/modules/manager/nix/)
  — Renovate's Nix manager for `flake.lock`.
- [Minimum Release Age — Renovate Docs](https://docs.renovatebot.com/key-concepts/minimum-release-age/)
  — dependency cooldown as a supply-chain control.
- [Our New Nix Deployment Tool: deploy-rs — Serokell](https://serokell.io/blog/deploy-rs)
  — magic rollback / canary confirmation.
- [Best practices for auto-upgrades of flake-enabled NixOS systems — NixOS Discourse](https://discourse.nixos.org/t/best-practices-for-auto-upgrades-of-flake-enabled-nixos-systems/31255)
- Pinned nixpkgs, `nixos/modules/tasks/auto-upgrade.nix` — verified
  `randomizedDelaySec`, `fixedRandomDelay`, `rebootWindow`,
  `allowReboot`, `persistent` in the source, not from memory.

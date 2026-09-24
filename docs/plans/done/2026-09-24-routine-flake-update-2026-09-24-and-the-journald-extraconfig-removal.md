---
slug: routine-flake-update-2026-09-24-and-the-journald-extraconfig-removal
created: 2026-09-24
status: done
frozen: true
kind: task
priority: normal
blocked_by:
---

# Routine flake update 2026-09-24 and the journald extraConfig removal it forced

## State

Verified to rung 4 (VM).

The `loki-pipeline` test passes. It is the right VM test for this change
rather than a token one: its nodes are instantiated from the stable tree,
so it boots and exercises the `extraConfig` arm of the new branch, which
is exactly the arm a unstable-only fix would have broken.

Beyond that: all five hosts build with their output read,
`nix flake check --no-build` passes -- it is what caught the second
breakage, since only the flake check evaluates that stable-pinned test
node -- and the emitted `journald.conf` was diffed between the stable and
unstable builds to confirm the cap lands identically on both (G6).

Not verified by a switch: nothing here has been deployed to a running
host, by design.

## Original plan

User asked for a plain `nix flake update`, then commit, push and merge the
branch. No behaviour change intended beyond whatever upstream brings.

## Progress

- [x] G1 -- `nix flake update`: 13 inputs bumped
- [x] G2 -- migrate the removed `services.journald.extraConfig`
- [x] G4 -- keep the module evaluating on both nixpkgs trees
- [x] D1 -- decide what to do about the newly-insecure immich 2.7.5
- [x] G3 -- build all five hosts
- [x] G6 -- verify the cap actually lands on both trees
- [x] G7 -- give every pin added here a removal condition, and sweep for older ones

## Decisions (D)

### D1 -- immich 2.7.5 is newly marked insecure by the stable bump; allow it, hold the stable pin back, or migrate to 3.x now?

nixpkgs-stable 26.05.10478 marks `immich-2.7.5` insecure -- 2.x is EOL
upstream and carries CVE-2026-59258 and CVE-2026-82272. 3.x ships in
26.11, which homelab is not on. This blocked homelab's eval outright, so
the update could not land without an answer.

Options put to the user: hold `nixpkgs-stable` at its old pin and keep the
other twelve updates; allow the insecure package and log it; migrate to
3.x now; or drop the update entirely.

**Chosen: allow the insecure package**, with the exemption scoped to
`modules/services/immich.nix` rather than a host-wide or fleet-wide
`nixpkgs.config`, so only a host that actually runs immich carries it. The
version string is exact (`immich-2.7.5`), so the next immich bump
re-breaks the build deliberately and forces a fresh look rather than
silently extending the exemption to a future version.

Recorded in `docs/accepted-risks.md`; the real fix is tracked as its own
plan (see G5).

~~so only a host that actually runs immich carries it~~ -- imprecise, see
F2. Correct statement: only a host *importing the immich module* carries
the exemption at all (verified: homelab does, the other four have no such
attribute), but within homelab it is an ordinary host-global
`nixpkgs.config` -- `permittedInsecurePackages` has no per-derivation
scope. AR-9 now says it this way.



**ANSWERED 2026-09-24:** User chose: allow the insecure package, scoped to the immich module and version-exact; 3.x migration tracked separately.

## Gotchas (G)

### G1 -- what the update actually moved

Thirteen inputs. The two that matter for blast radius are the nixpkgs
pins: `nixpkgs-unstable` 26.11pre1066106 -> 26.11pre1078696 (2026-09-02 ->
2026-09-23) and `nixpkgs-stable` 26.05.8846 -> 26.05.10478 (2026-09-01 ->
2026-09-22). The rest: copyparty, disko, home-manager,
home-manager-stable, import-tree, nix-flatpak, nix-index-database, nvf
(+ its `mnw`), sops-nix, stylix. `impermanence` and `flake-parts` were
already at their tips and did not move.

### G2 -- `services.journald.extraConfig` is gone, not deprecated

The unstable bump turned `modules/nixos/alloy.nix` into a hard eval
failure on every host: upstream replaced the option with
`mkRemovedOptionModule`, so it asserts rather than warning. Confirmed
against the newly pinned tree
(`nixos/modules/system/boot/systemd/journald.nix`), not from memory: the
module now exposes `services.journald.settings.Journal`, a
`freeformType = attrsOf unitOption` submodule, and renames `storage`,
`rateLimitInterval`, `rateLimitBurst`, `forwardToSyslog` and `audit` into
it while *removing* `extraConfig` and `console` outright.

Migration was one line, and the freeform attrset takes the string
directly, so `journalMaxUse`'s `types.str` needed no change:

    services.journald.settings.Journal.SystemMaxUse = cfg.journalMaxUse;

Worth knowing for the next update: this is the only `extraConfig` form the
repo used, but the same commit renamed five sibling options, so any future
module reaching for `services.journald.*` should go straight to
`settings.Journal.*`.

### G3 -- ~~the freeform submodule changes nothing about the emitted file~~

~~`environment.etc."systemd/journald.conf"` is still rendered from
`cfg.settings` via `settingsToSections`, so the resulting
`SystemMaxUse=` line is byte-identical to what the old heredoc produced.
The cap itself (`2G` by default, per
2026-09-05-build-the-fleet-log-monitoring-stack-on-loki-grafana-alloy.md#D9)
is unchanged -- this is a pure option-surface migration, not a retention
policy change.~~

**Wrong, corrected by G6.** Written before the two builds were actually
diffed. The `SystemMaxUse=` line does survive unchanged and the cap is
untouched, but "byte-identical file" is false: 26.11 also stopped
emitting nixos's `Storage`/`RateLimit*` defaults, so the rest of the file
differs. Believing this claim is what nearly let the `Storage` change
through unnoticed -- see G6.

### G4 -- the module has to satisfy both trees at once

The obvious fix -- just move to `settings.Journal` -- breaks homelab,
which is `nixpkgs-stable`-pinned, and the `loki-pipeline` VM test, whose
nodes are instantiated from the stable tree too. Stable 26.05 has only
`extraConfig` and no `settings`; unstable has only `settings`. So there is
no single form that evaluates everywhere, and the module needs a branch:

    journalSizeCap =
      if options.services.journald ? settings then
        { settings.Journal.SystemMaxUse = cfg.journalMaxUse; }
      else
        { extraConfig = "SystemMaxUse=${cfg.journalMaxUse}"; };

assigned at the `services.journald` level (`services.journald =
journalSizeCap;`) so only that one line changes -- branching at the
leaf instead would have forced the whole `config` attrset through a
`//` merge and reindented it, turning a two-line fix into a
several-hundred-line diff for no behavioural gain.

Branching on the *option's existence* rather than on
`config.system.nixos.release` means this retires itself the moment stable
reaches 26.11 -- there is no version constant anywhere to remember to
update. `options` had to be added to the module's argument list for this.

### G5 -- follow-up: immich 3.x migration

D1's exemption is a holding action, not a fix. The migration is a
major-version jump on a live photo library with a real database
migration, so it needs its own plan, a verified backup and a VM test --
deliberately not bundled into a routine lock bump. Tracked as
`2026-09-24-migrate-homelab-s-immich-from-the-eol-2-x-to-3-x.md`.

### G6 -- 26.11 stopped writing journald's NixOS-side defaults, and that is load-bearing for impermanence

Comparing the two built systems' `/etc/systemd/journald.conf` shows the
rename was not just cosmetic upstream. Stable still emits the NixOS
defaults:

    [Journal]
    Storage=persistent
    RateLimitInterval=30s
    RateLimitBurst=10000
    Audit=keep
    SystemMaxUse=2G

while 26.11 emits only what is actually set:

    [Journal]
    Audit=keep
    SystemMaxUse=2G

Both carry `SystemMaxUse=2G`, so this plan's own change is verified on
both arms. The rest is upstream dropping its explicit defaults in favour
of systemd's compiled-in ones. `RateLimitIntervalSec`/`RateLimitBurst`
are identical either way (30s/10000), so nothing moves there.

`Storage` is the one that matters: nixos pinned it to `persistent`, and
26.11 stopped pinning it at all.

Read the pinned systemd's own `journald.conf(5)` (systemd 261.2, from
torrent's new closure) rather than assuming, because the answer decides
whether this is benign:

> Defaults to "persistent" in the default journal namespace (this value
> is determined at compilation time)

So behaviour is preserved -- the compiled-in default is `persistent`, not
`auto`. (An earlier draft of this gotcha assumed `auto`, which would have
made journal persistence depend on `/var/log/journal` already existing.
That was wrong; the man page is the authority.)

What did change is *where the guarantee comes from*: an explicit nixos
option became an upstream compile-time default on the four
unstable-pinned hosts. This repo pinned it deliberately (F11), so the
branch now sets `settings.Journal.Storage = "persistent"` on the 26.11
arm rather than inheriting a default that can move without notice. The
26.05 arm is left alone -- its module still emits the line itself, and
appending a duplicate key would only make the rendered file confusing.

Verified after the change, not just assumed -- torrent's built
`journald.conf` reads:

    [Journal]
    Audit=keep
    Storage=persistent
    SystemMaxUse=2G

Also belt-and-braces: both impermanent hosts persist `/var/log` wholesale
(`hosts/vps/configuration.nix:258`, `hosts/homelab/configuration.nix:854`),
so even an `auto` default would have held.

Carry forward to 2026-08-18-migrate-torrent-and-thinkpad-to-impermanence.md:
those hosts must persist `/var/log`, or they come up with a volatile
journal and alloy ships nothing across a reboot, with no error to explain
it.

### G7 -- every pin this update added is tracked; six older ones were not

This update deliberately adds two manual pins (the immich exemption, D1;
the journald dual-spelling branch, G4). Both were given a removal
condition on the way in. That prompted a sweep for the ones already in
the tree, which found six with no removal condition recorded anywhere:

- `modules/flake/pkgs.nix:13-15` -- a fleet-wide `electron-39.8.10`
  permit the 2026-08-26 audit already suspected was dead (F-P8-20)
- `modules/flake/pkgs.nix:22` -- `permittedInsecurePackages = [ "" ]`,
  which matches nothing (same finding, called meaningless outright)
- `hosts/torrent/configuration.nix:55` -- host-wide `allowBroken` for
  r8125, whose own comment says "check on next stable release"; that
  condition has now passed unactioned twice, and `r8125` carries no
  `broken = true` in *either* tree this update pins
- `hosts/isoimage/configuration.nix:94-95` -- the same bypass, never
  audited at all
- `modules/profiles/default.nix:58` -- `zfs-prune-snapshots # TEMP, zfs
  needs module`
- `modules/nixos/tooling.nix:99` -- a `mkForce`'d lualine theme marked
  `# TEMP`

None is urgent and none is touched here -- removing them is not a
lockfile bump's business, and the two `allowBroken` lines in particular
need a build to prove nothing else leans on them. They are written up
with per-item removal conditions in
2026-09-24-track-and-retire-the-untracked-manual-pins-and-temp-workarounds.md.

The transferable bit is in that plan's G1: three of the six *were* found
by the 2026-08-26 audit and written up correctly, then sat for a month
because a finding in a dated audit directory has no owner. Rated
"needs-check" is not the same as tracked.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 -- the 26.11 journald rewrite dropped `Storage=persistent` from the emitted file, and G3's "byte-identical" claim is false

- **File:** `modules/nixos/alloy.nix:160-163` (the retained "Storage=persistent is already the nixos default (F11)" comment), plan G3 above
- **Severity:** LOW
- **Confidence:** CONFIRMED
- **Axis:** hardening (logging/forensics control), needed-used (stale doc)
- **Reachability:** an adversary who has already achieved a foothold on vps (the only internet-facing host) and reboots or crashes it to destroy local evidence -- journal persistence across that reboot is no longer asserted anywhere in this repo, only inherited from systemd's compile-time default. Same path for any future host installed fresh on 26.11.
- **Rule:** `docs/hardening.md` rule 9 ("verify that config actually takes effect -- rendering is not applying") -- the verification that was done proves the `SystemMaxUse=` line renders, not that the surrounding policy survived.
- **Finding:** the emitted `journald.conf` is **not** byte-identical across the migration, contrary to G3's "changes nothing about the emitted file". Verified by `nix eval` on the new pin:
  - homelab (stable 26.05, `extraConfig` arm): `[Journal] / Storage=persistent / RateLimitInterval=30s / RateLimitBurst=10000 / Audit=keep / SystemMaxUse=2G`
  - vps, thinkpad, torrent (unstable 26.11, `settings` arm): `[Journal] / Audit=keep / SystemMaxUse=<cap>` -- and nothing else.

  The cause is upstream, not this branch's code: diffing the old (`3ed67ec0a4d3`) and new (`4975466d3247`) pinned `nixos/modules/system/boot/systemd/journald.nix` shows `services.journald.storage` (`default = "persistent"`) and both `rateLimit*` options deleted outright, replaced by `mkRenamedOptionModule`s carrying no defaults. NixOS now sets only `Audit = mkOptionDefault "keep"`.

  Behaviour is preserved *today*: the pinned systemd's own `journald.conf(5)` (`systemd-261.2-man`) says Storage "Defaults to `persistent` in the default journal namespace (this value is determined at compilation time)", and rate limiting "Defaults to 10000 messages in 30s" -- identical to the values NixOS used to write out. So this is not a live log-loss bug. What changed is that a detection control this repo deliberately pinned (D9 of the loki/alloy plan, the same decision the `SystemMaxUse` cap comes from) is now an unpinned upstream compile-time default on three of four hosts, and the module's own comment asserting it -- "Storage=persistent is already the nixos default (F11)" -- is now false as written on 26.11 and was carried through this diff unchanged. When stable reaches 26.11 and the `extraConfig` arm is deleted, homelab loses the explicit line too.
- **Fix risk:** setting `settings.Journal.Storage = "persistent"` in the `settings` arm is inert-safe (same value as the effective default) but has to be added to *both* arms or the two trees diverge; on the stable arm prefer `services.journald.storage = "persistent"` over a duplicate line inside `extraConfig`. Whatever is chosen, confirm post-deploy on a live 26.11 host with `systemd-analyze cat-config systemd/journald.conf` plus `journalctl --header`, not by re-reading the generated file (rule 9). At minimum, correct the stale F11 comment.


**FIXED 2026-09-24:** Pinned settings.Journal.Storage = persistent on the 26.11 arm and corrected the stale F11 comment; stable arm left alone since 26.05's module still emits the line (a duplicate key would only confuse the rendered file). Verified in torrent's built journald.conf.

### F2 -- the immich insecure-package exemption covers one of the two EOL 2.x derivations actually deployed, and is host-global in effect rather than module-scoped

- **File:** `modules/services/immich.nix:12-16`, `docs/accepted-risks.md` AR-9 ("Scope of the exemption")
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used (documentation vs. mechanism)
- **Reachability:** any device already on the tailnet -- it reaches `immich-server` on `tailscale0:2283`, which hands uploaded media to `immich-machine-learning` on `localhost:3003`. Both binaries are built from the same EOL immich 2.7.5 source; only the former is what `permittedInsecurePackages` names.
- **Rule:** n/a (new-rule candidate: an insecure-package exemption should name every derivation of that source the host actually runs, or record explicitly why the others are unmarked).
- **Finding:** AR-9's containment claims check out as written, verified against the new pin (see the clean note below). Two precision gaps remain:
  1. `services.immich.package.machine-learning` is a **separate derivation**, `immich-machine-learning-2.7.5` (`pkgs/by-name/im/immich-machine-learning/package.nix`, its own `meta` block, no `knownVulnerabilities`). It builds with no exemption and is not mentioned in AR-9, yet it is the component this repo's own comments treat as the higher-risk one ("the component that parses untrusted uploaded media", `modules/services/immich.nix:51-63`). The exemption's tripwire -- "a future `immich-2.7.6` re-breaks the build on purpose" -- is therefore a tripwire on the *server* package only. In practice both move together in nixpkgs, so the tripwire still fires, but the accepted risk reads as if one version string covered the whole deployed surface.
  2. "It sits on the immich module rather than in a host-wide ... `nixpkgs.config`" overstates the mechanism. `nixpkgs.config` has no per-package scope: the definition lands in homelab's *host-global* nixpkgs config (`nix eval` gives `{ allowUnfree = true; permittedInsecurePackages = [ "immich-2.7.5" ]; }`). What is genuinely narrow is *which hosts* carry it -- vps, thinkpad, torrent and isoimage have no `permittedInsecurePackages` attribute at all, confirmed by eval. The residual risk is future-tense: the list now lives in a service module, so the next insecure package on homelab will be tempting to append there, far from its subject.
- **Fix risk:** none for (2) -- a wording fix in AR-9. For (1), adding `immich-machine-learning-2.7.5` to the list pre-emptively would be *worse*: it would suppress a future upstream marking of the ML package, which is exactly the signal that should break the build. The right action is a sentence in AR-9 recording that the ML derivation is unmarked upstream and deliberately not listed.


**FIXED 2026-09-24:** AR-9 reworded: says which hosts carry it vs that it is host-global within homelab, and records that immich-machine-learning-2.7.5 is a separate unmarked derivation deliberately NOT added to the list (adding it would suppress the very signal that should break the build). Migration plan's checklist now covers it.

### F3 -- `.claude/.active-plan` points at the follow-up plan, not this one

- **File:** `.claude/.active-plan` (its contents pointed at the `todo/` copy of 2026-09-24-migrate-homelab-s-immich-from-the-eol-2-x-to-3-x.md)
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used
- **Reachability:** any agent following `docs/agents/security/reference.md`, which says to locate the active plan via `.claude/.active-plan` -- it would append findings about *this* change to the 3.x migration plan, where a later consolidation pass would read them as findings about the migration.
- **Rule:** n/a
- **Finding:** the marker was left pointing at the `todo/` plan created as this task's own follow-up (G5), so the marker and the work in progress disagree. Findings for this review were written here instead, on the launching agent's explicit instruction.
- **Fix risk:** none; repointing the marker is a one-line change, but the 3.x migration plan is a legitimate *future* active plan, so the fix is ordering, not deletion.


**FIXED 2026-09-24:** Repointed .claude/.active-plan at this plan. Note it is gitignored, so this was local state only and never part of the commit.

### F4 -- docs pass: three judgment calls on where this change's rationale and rules belong

- **File:** `docs/hardening.md` (the `/var/log` persistence convention), `docs/accepted-risks.md` AR-9, `modules/nixos/alloy.nix:50`
- **Severity:** INFO
- **Confidence:** CONFIRMED
- **Axis:** needed-used (documentation placement)
- **Reachability:** n/a
- **Rule:** `docs/style-guide.md` "Why context: the plan file, not comments" and its citation-anchor rule
- **Finding:** three things this docs pass deliberately did *not* change, recorded so the next pass does not re-litigate them:
  1. **No new `docs/hardening.md` rule for insecure-package exemptions.** F2 above floated one ("an insecure-package exemption should name every derivation of that source the host actually runs, or record explicitly why the others are unmarked"). Left unwritten: AR-9 now records exactly that for immich, and the standing inventory of manual pins is already a tracked task (`2026-09-24-track-and-retire-the-untracked-manual-pins-and-temp-workarounds.md`). A standing rule generalised from one instance would be speculative. If a second exemption lands, that is the trigger to write the rule.
  2. **The `/var/log` persistence convention in `docs/hardening.md` was left auditd-scoped.** It reads "Any new persist-capable host that gets `security.auditd`/`security.audit` needs `/var/log` in its impermanence persistence list". Since the alloy rollout, *any* alloy host has the same dependency -- `Storage=persistent` writes to `/var/log/journal`, and on an impermanent host without `/var/log` persisted the journal is volatile and alloy silently ships nothing across a reboot. That gap predates this change (26.05 already pinned `Storage=persistent`), and G6 above already carries it forward to `2026-08-18-migrate-torrent-and-thinkpad-to-impermanence.md`. Broadening the rule is a real option, not done here because it is not this diff's regression.
  3. **`modules/nixos/alloy.nix:50` cites the follow-up plan by bare filename, with no anchor.** The style guide wants `<date>-<slug>.md#D3`-form anchors, but the target section in `2026-09-24-migrate-homelab-s-immich-from-the-eol-2-x-to-3-x.md` is `## Item 2 -- remove the journald dual-spelling branch`, which has no `D`/`G`/`F` id to anchor to. Left as a bare filename rather than inventing an id or hand-rolling a heading slug; giving that item a real id when the plan is picked up would fix it properly.
- **Fix risk:** none -- all three are open questions, not defects.

**Docs pass 2026-09-24, fixed directly:**
- `modules/nixos/alloy.nix`: dropped the bare `(F11)` from the `services.journald` comment (bare finding ids are not the repo's citation form, and G6 -- already cited on the next line -- carries the F11 history); tightened the 26.11 arm's three-line "pin it rather than inherit a default that can change under us" rationale to a two-line fragment, since that reasoning lives in G6 above.
- `modules/services/immich.nix`: turned "CVEs and reasoning in AR-9 of docs/accepted-risks.md" into a one-line `accepted risk: docs/accepted-risks.md AR-9` citation.
- `docs/accepted-risks.md`: AR-9's **Sits on** was `§4` (the whole trust-boundary chapter); every other entry names a specific boundary, and this one is §4.4 "Any tailnet device -> nearly everything", which is the boundary AR-9's own prose argues from.
- `hosts/{homelab,thinkpad,torrent,vps}/README.md`: re-ran `scripts/doc-host.sh --all` for the lock bump. Picked up package-version drift (`comma-with-db` 2.4.1->2.4.2, `podman-docker-compat` 5.8.6->5.8.7, `openssl` newly in the closure on thinkpad/vps) plus one pre-existing staleness: homelab's timer list was missing `backup-restore-test-zbackup`.



**FIXED 2026-09-24:** Item 3 fixed: gave the migration plan's journald cleanup a real G1 id and anchored the alloy.nix citation to it. Items 1-2 accepted as deliberate non-changes, but item 2's carry-forward is now written INTO 2026-08-18-migrate-torrent-and-thinkpad-to-impermanence.md#G1 rather than only referenced from here.

### Checked and clean

Reviewed the whole change against HEAD (6 files: `flake.lock`, `modules/nixos/alloy.nix`, `modules/services/immich.nix`, `docs/accepted-risks.md`, and the two plan files) plus the current full content of both touched `.nix` modules. Verified against the newly pinned trees, not from memory:

- **immich containment (AR-9's claims).** `services.immich.openFirewall = false`; port 2283 is opened **only** on `tailscale0`; `networking.firewall.allowedTCPPorts` and `allowedTCPPortRanges` are both empty on homelab; `trustedInterfaces = [ "lo" ]`; the wg0 interface (the path to vps's public Caddy) carries only 8096/25565 plus the game UDP ports; vps's `networking.nat.forwardPorts` DNATs only 25565/tcp, 19132/udp and 34197/udp to 10.100.0.2; vps's Caddy has exactly two vhosts (`:80` respond-421 and the jellyfin/Anubis one) and no immich route; no tailscale `serve`/`funnel` anywhere in the repo. The ML worker binds `localhost:3003` and keeps its `PrivateDevices = mkForce true` / `DeviceAllow = mkForce [ ]` posture. `immich-2.7.5` is identical between the old and new stable pins apart from the new `meta.knownVulnerabilities` block -- the bump marks it, it does not change it -- and the three CVE/EOL strings match what AR-9 records.
- **The journald branch itself is sound.** `options.services.journald ? settings` resolves false on homelab (26.05) and true on vps/thinkpad/torrent (26.11); the stable arm renders `SystemMaxUse=2G` last in the file (journald is last-directive-wins, and nothing follows it, so the missing trailing newline is harmless); the unstable arm merges with upstream's own `Audit = mkOptionDefault "keep"` rather than replacing it, i.e. assigning the whole `services.journald` attrset drops no sibling. Per-unit rate limits are unaffected: `systemd.services.sshd.serviceConfig` still carries `LogRateLimitBurst = 100000` / `LogRateLimitIntervalSec = "30s"` on both trees, and `startWhenNeeded = false`, so the unit name `genAttrs` targets is still the real one. All four real hosts and the `loki-pipeline` VM check evaluate to a `drvPath` on the new lock.
- **Upstream default changes in the bump that are hardening-relevant.** Compared both nixpkgs trees old-vs-new. `networking.firewall.checkReversePath` changed default from `true` (strict) to `"loose"` in unstable -- **no effect here**, every host already resolves to `"loose"` via the tailscale module's own `mkDefault`, verified per host. The `fail2ban` module loosened `RuntimeDirectoryMode` 0750 -> 0755 and added a group-owned 0660 control socket -- **not reachable**, fail2ban is not enabled anywhere (vps replaced that jail with CrowdSec). `security/pam.nix` (fscrypt-experimental -> fscrypt), `polkit.nix` (yubico/fprintd device carve-outs) and `zfs.nix` (two extra PATH entries) touch nothing this fleet enables. The stable tree's 27 changed modules are all services this fleet does not run. sops-nix's only module change is an ordering fix (`before = [ "sysinit.target" ... ]`), strictly safer; the copyparty NixOS module is unchanged between pins.
- **Not filed as a finding, worth knowing.** `flake-update-test` (`modules/nixos/auto-update.nix:243`) gates the automated lock bump on `nixos-rebuild build --flake .#homelab` alone and merges+pushes to master on success. The exact breakage this plan fixed by hand -- an eval failure on the *unstable* hosts only -- is invisible to that gate, which would have pushed it. Bounded by health-alerts' `systemctl --failed` check firing on the hosts that then fail to deploy, and by that unit reportedly never having completed a run. Pre-existing, outside this change.
- **Secrets.** Nothing here touches `secrets/`, `.sops.yaml`, or any `sops.secrets.*` reference. No secret was decrypted or read during this review.

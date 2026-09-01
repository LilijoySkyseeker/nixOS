---
slug: restructure-zfs-so-ordinary-temp-and-cache-data-is
created: 2026-08-28
status: in-progress
frozen: false
---

# restructure ZFS so ordinary temp and cache data is not snapshotted or replicated

## Original plan

Raised 2026-08-27 while working credential rotation. Migrated here from
`TODO.md` on 2026-08-28 when that file was retired by
`establish-the-workflow-and-plan-file-system-2026-08-27.md`.

Today the laptops snapshot `/tmp`, `/var/tmp` and `~/.cache` every five
minutes and ship them to homelab, because those paths sit inside datasets
that are snapshotted wholesale. That forced the awkward "generate keys in
`/dev/shm`" workaround in the credential rotation runbook, and it is the
mechanism behind `F-P7-02`.

**The constraint that decides the shape of the fix: ZFS snapshots whole
datasets.** There is no exclude list. You cannot keep `~/.cache` out of a
`zroot/local/home` snapshot by configuring zrepl — the only way to exclude
a path is to make it *its own dataset* and leave that dataset out of the
snapshot set. So this is genuinely a restructure (disko layout + zrepl
dataset lists), not a settings change.

**homelab already has the right shape; the laptops do not.** Measured live
2026-08-27:

| host | `/tmp` lives on | snapshots on it | replicated? |
|---|---|---|---|
| homelab | `zroot/local/root` | **1** — `@blank` only | no |
| torrent | `zroot/local/root` | **61** zrepl snapshots | yes → `zbackup` |
| thinkpad | `zroot/local/root` | same shape | yes → `zbackup` |

homelab gets this free from impermanence: its root is rolled back to
`@blank` on boot and only `zroot/local/state` + `zdata/storage/*` are in
`myZrepl.local.datasets`. The laptops serve `zroot/local/root` and
`zroot/local/home` whole (`hosts/torrent/configuration.nix:92-95`).

**Two separate costs, worth keeping distinct:**

- *Security.* A secret written to a normal temp location becomes
  unretractable. `F-P7-02` is the live proof: the **live** zrepl puller
  private key (`vars.zreplPullerKey`'s private half, mode 0600, dated
  2026-08-23) is still at `/tmp/homelab_zrepl_key` on torrent, confirmed
  present inside `/.zfs/snapshot/zrepl_20260827_231641_000/tmp/` — one of
  61 snapshots, plus homelab's replica. Deleting the file retracts
  nothing.
- *Volume.* On torrent, `~/.cache` is **22 GB** of regenerable churn
  snapshotted hourly and replicated (7.5G spotify, 3.6G appimage-run,
  2.3G nix, 1.1G chromium…), plus 791M of `~/.local/share/Trash` and 162M
  in `/tmp`. `~/Downloads` is **957 GB** and is also where
  `iso-autobuild` drops built ISOs. torrent's replica on homelab is
  3.16T.

## Progress

- [ ] G1 confirmed empirically — no action taken yet
- [x] D1 land `boot.tmp.useTmpfs` (agreed, not yet written)
- [x] F2 — verify homelab's restic `mount -t zfs` under `/tmp/restic/$snap`
      still works with `/tmp` now tmpfs, at homelab's next real deploy
      (mount-stacking should be unaffected by reasoning, but per
      hardening.md rule 9 that needs the daemon's own output, not
      inference — and this session's own security review deliberately
      did not exercise it live, since a careless test risks kicking off
      part of the multi-day backup)
- [ ] D2 impermanence fleet-wide — see
      `2026-08-18-migrate-torrent-and-thinkpad-to-impermanence.md`
- [ ] D3 dataset split for `~/.cache` / Trash / Downloads — undecided

## Decisions (D)

### D1 — `boot.tmp.useTmpfs = true`, fleet-wide

Agreed 2026-08-27. **No `boot.tmp.*` is set anywhere in this repo today**,
so `/tmp` is on-disk and never cleaned on all four hosts. Cheapest single
improvement, and worth landing *ahead of* the impermanence work rather
than waiting for it: it is one option, needs no disko changes, and makes
`/dev/shm`-style hygiene the default instead of something to remember at
exactly the moment you are handling a private key. Watch the memory cost
on hosts that build large derivations in `/tmp`.

**Landed 2026-08-28.** `boot.tmp.useTmpfs = true;` in
`modules/profiles/default.nix`, alongside the bootloader block — every
host imports this profile, including vps (which `mkForce`s the loader
but not `boot.tmp`). All five `nixosConfigurations` (`torrent`, `vps`,
`thinkpad`, `homelab`, `isoimage`) build clean. Rendered `tmp.mount`
checked on `torrent` and `vps`, not just built: both render
`Type=tmpfs`, `size=50%` (the module default, unset here), `nosuid`,
`nodev` — confirming the option actually took effect rather than only
evaluating. Not yet deployed to any host; takes effect at the next
switch on each.

### D2 — all hosts get impermanence

Agreed 2026-08-27. homelab is the model, not the exception. Settles the
`/tmp` and `/var/tmp` half structurally: a root that rolls back to
`@blank` every boot cannot accumulate temp data for a snapshot to
capture. Folds in the inert thinkpad scaffolding flagged by `F-P5-14`
(`environment.persistence` evaluates to `{}`, no `zfs rollback …@blank`
in its initrd, so `/` is durable today and `@blank` is decorative).

Execution belongs to
`2026-08-18-migrate-torrent-and-thinkpad-to-impermanence.md`; this plan
owns the *reason* and the part impermanence does not cover.

**Impermanence does not finish the job.** It fixes `/`, and therefore
`/tmp` and `/var/tmp`. It does **not** touch `/home`, which is persisted
by design and is where the volume actually is. Landing impermanence must
not be read as closing this plan.

### D3 — what to split out of `/home` — UNDECIDED

- `~/.cache` and `~/.local/share/Trash` into their own datasets, excluded
  from `serve.datasets`. Low controversy — regenerable by definition.
- `~/Downloads` is a judgement call. 957 GB is not obviously disposable,
  and "not backed up" is a promise to the user as much as a storage
  decision. Splitting just the `iso-autobuild` output directory out of it
  may be the narrower, better move.
- Whether `zroot/local/root` needs replicating on a laptop at all once it
  is impermanent, given `/nix` is excluded already and the config is in
  this repo.

## Gotchas (G)

### G1 — `/tmp` survives a reboot on torrent, confirmed 2026-08-28

torrent was restarted on 2026-08-28 (boot 10:43). `/dev/shm` was wiped as
expected — it took an in-flight rotation key with it, see
`do-a-full-security-audit-hardening-pass-on-homelab-2026-08-26.md`. But
`/tmp/homelab_zrepl_key` was **still present afterwards**, dated
2026-08-23.

That is this plan's premise demonstrated rather than argued: with no
`boot.tmp.cleanOnBoot` and no impermanence, a secret written to `/tmp`
survives reboots indefinitely *and* accumulates snapshot copies the whole
time. The reboot also proves the two halves are independent — `/dev/shm`
is safe across reboots by being volatile, `/tmp` is unsafe by being
durable, and only `/tmp` is what people reach for by default.

## Findings (F)
*(populated by security/docs-updater when invoked)*

### F1 — nix-daemon builds now spend host RAM instead of disk for `/tmp` scratch, fleet-wide, uncapped by any per-service ceiling

- **File:** `modules/profiles/default.nix:269` (the new `boot.tmp.useTmpfs = true`); rendered evidence at `/nix/store/0738ns3s8rl2isns0ynzpnihbc3ijb3h-unit-nix-daemon.service/nix-daemon.service` (this session's own build artifact, still present in the local store)
- **Severity:** MEDIUM
- **Confidence:** CONFIRMED that `nix-daemon.service`'s rendered unit sets no `TMPDIR`/`Environment=TMPDIR=…` and no `PrivateTmp=`, so it inherits the host's real `/tmp` (now `Type=tmpfs, size=50%`, confirmed from this same session's rendered `tmp.mount`). PLAUSIBLE (well-established Nix behavior, not re-verified against the pinned `nix` source this session) that Nix's build sandbox defaults its scratch/build directory to `$TMPDIR` (falling back to `/tmp`) when `nix.settings.build-dir` is unset — which this repo never sets (`grep -rn "build-dir"` fleet-wide: no hits).
- **Axis:** hardening (new-rule candidate; also touches the container-OOM concern rule 10 already codifies for a different mechanism)
- **Reachability:** Any principal who can cause a large local build on one of these hosts — the repo's own automated pipelines (`myAutoUpdate`/`myPullDeploy` doing `nixos-rebuild build/switch` on every push to `master`, so effectively anyone with push access to the repo; `myIsoAutobuild`'s `nix build .#nixosConfigurations.isoimage...` on whichever host runs it) — now has that build's scratch data compete directly for physical RAM rather than disk+page-cache. Before this change, `/tmp` was on-disk (part of `zroot/local/root` on the laptops, per this same plan's own measurement table), so a large build's temp files were bounded by disk space; now they are bounded by 50% of RAM, and every byte written there is pinned as anonymous/tmpfs memory the kernel cannot reclaim by writeback the way it can page cache. On `vps`, this also directly competes with `zramSwap.enable = true` (`hosts/vps/configuration.nix:209`) for the same physical RAM pool, so a host that already trades RAM for swap capacity now has less RAM to trade with.
- **Rule:** n/a directly, but adjacent to hardening.md's OCI-container rule ("Without a cgroup ceiling, container OOM pressure is host OOM pressure and the kernel picks its own victim among whatever else the host runs") — the same mechanism, no ceiling, for a *fleet-wide* default rather than one container.
- **Finding:** `boot.tmp.useTmpfs = true` is landed with no accompanying `nix.settings.build-dir` (or `TMPDIR=` override for the relevant build/`nix-daemon` units) to keep large, unrelated builds off the now-RAM-backed `/tmp`. The plan text itself flags "watch the memory cost on hosts that build large derivations in `/tmp`" as an open concern (Decisions §D1) but nothing was added to address it, and nothing in this session's verification (rendered-unit checks on `torrent`/`vps`) exercised an actual large build under the new tmpfs to see whether it changes OOM behavior or just fails cleanly with ENOSPC on a memory-constrained host.
- **Fix risk:** Setting `nix.settings.build-dir` (e.g. to `/var/tmp` or a dedicated on-disk path) to keep Nix's own scratch space off tmpfs would need re-testing every host's build (`nixos-rebuild build`) to confirm the setting actually takes effect (per hardening.md rule 9 — verify, don't assume), and would need checking that the chosen path isn't itself inside a dataset this same plan is trying to keep temp data out of.

> **Corrected 2026-08-28: F1's PLAUSIBLE premise does not hold for the
> pinned Nix version, checked rather than assumed.** `nix show-config`
> reports `build-dir = ` (empty); the pinned `nix-2.34.8-doc`'s
> `store/types/local-store.html` states explicitly: *"If not set, Nix
> will use the **builds subdirectory of its configured state
> directory**."* Verified live: `/nix/var/nix/builds` exists
> (root-owned, on `/nix`, not `/tmp`), and `nix-daemon.service`'s
> rendered `Environment=` has no `TMPDIR` at all. So on this pinned
> version, derivation build scratch space — the sandbox's `/build`,
> bind-mounted from the host's `build-dir` — lands on the store
> filesystem by default, not on the new tmpfs `/tmp`. Older Nix
> versions did fall back to `$TMPDIR`/`/tmp`, which is almost certainly
> where this PLAUSIBLE claim came from; it is simply no longer this
> version's behavior. **Severity revised MEDIUM → INFO.** The narrower
> residual is evaluation-time scratch use (fetcher tarball extraction,
> `builtins.fetchTarball`, etc., which can use `$TMPDIR`/`/tmp` outside
> the sandboxed-build path) — smaller in practice than a full derivation
> build and not separately measured here. Not re-tested against an
> actual large build (e.g. a from-source package or an ISO build); if
> one is ever observed to stress `/tmp`, re-open this with that evidence.


**MOOT 2026-09-01:** Checked against the pinned nix-2.34.8 source and live nix-daemon.service: build-dir defaults to /nix/var/nix/builds, not $TMPDIR, so derivation build scratch never lands on the new tmpfs /tmp. Already reasoned in-doc (severity revised MEDIUM -> INFO); this only adds the formal marker. Residual (fetcher/evaluation-time scratch use) not separately measured -- reopen if ever observed to stress /tmp.

### F2 — this session's rendered-unit verification skipped the one host with an actual `/tmp` consumer

- **File:** `hosts/homelab/configuration.nix:216-233` (the `backupPrepareCommand`/`backupCleanupCommand` that `mkdir -p /tmp/restic/$snapshot` and `mount -t zfs $snapshot /tmp/restic/$snapshot` for the weekly, multi-day, ~2.9TiB offsite restic backup); plan text's own "Landed 2026-08-28" note under D1
- **Severity:** LOW
- **Confidence:** CONFIRMED — `grep` shows this is the only place in the repo that programmatically mounts something *onto* `/tmp` rather than merely writing files into it, and the plan's own D1 note names `torrent` and `vps` as the two hosts whose rendered `tmp.mount` was actually read, not `homelab`.
- **Axis:** needed-used / verification
- **Reachability:** n/a (this is a gap in the verification story, not a live exposure) — but the consequence, if the reasoning below is ever wrong, lands on `homelab`'s only offsite backup path, which `docs/hardening.md` rule 8 already treats as the fleet's one out-of-band data-loss backstop.
- **Rule:** hardening.md rule 9, "verify that config actually takes effect — rendering is not applying" — followed for the option in general, not for the specific consumer most likely to interact with it unusually.
- **Finding:** Mounting a different filesystem (`zfs`) over a directory that lives inside the new tmpfs `/tmp` is ordinary Linux mount-stacking and should not consume tmpfs capacity for the mounted snapshot's own data (only the empty directory entry does) — so by reasoning alone this should keep working unchanged. But that is reasoning, not verification, and it is exactly the kind of case hardening.md's rule 9 says to check with the daemon's own output rather than infer. Nobody has run `systemctl start restic-backups-backblazeWeekly` (or even rendered its unit alongside the new `tmp.mount`) against a build that actually has `boot.tmp.useTmpfs = true`, on the one host where this mount-under-`/tmp` pattern exists.
- **Fix risk:** Actually exercising this (even a `--dry-run`-style restic run against a small test dataset) risks kicking off part of a multi-day, multi-TB backup job if done carelessly on the real host; should be tested against a throwaway dataset/snapshot first, not against production `zroot/local/state`/`zdata/storage/storage`.


**MOOT 2026-09-01:** Superseded by a4f5e95 (fix(restic): mount snapshots under a 0700 RuntimeDirectory, not /tmp), landed the same session for an unrelated reason (L-02, findings-tail.md -- /tmp/restic was world-traversable and mkdir -p would follow a planted symlink). backupPrepareCommand/backupCleanupCommand now mount exclusively under $RUNTIME_DIRECTORY (/run/restic-backups-backblazeWeekly), which is always tmpfs under /run by systemd default -- completely independent of boot.tmp.useTmpfs. Confirmed live in hosts/homelab/configuration.nix: no /tmp/restic reference remains. The mount-stacking-under-tmpfs question this finding raised no longer has a code path to apply to.

## Checked and clean

Reviewed the two-line diff (`modules/profiles/default.nix:268-269`, `boot.tmp.useTmpfs = true`) against `docs/hardening.md` and the surrounding file. Confirmed via this session's own leftover build artifacts in the local `/nix/store` (not re-derived from memory) that: the rendered `tmp.mount` unit fleet-wide is `Type=tmpfs`, `size=50%`, `mode=1777`, `nosuid`, `nodev` — matching upstream's documented defaults and the plan's own claim; no host overrides `boot.tmp.*` anywhere in the repo (`grep -rn "boot.tmp\."` — one hit, the new line itself), so `vps` (which `mkForce`s the bootloader block) is not silently exempted; the option sits after the bootloader block with no shared `let`/`with` bindings in between that could be shadowed or reordered. No secrets were read or referenced by this change. Did not find any per-host `boot.tmp.cleanOnBoot` setting that this option could conflict with (none exists). Did not attempt to build or switch any host, per the read-only scope of this review — relied entirely on artifacts this session's own `nixos-rebuild build` runs already left in the store. The two findings above (F1, F2) are about the change's *interaction* with the rest of the fleet's config, not about the option itself being mis-set — `boot.tmp.useTmpfs = true` is exactly what upstream NixOS documents it to be.

_security finished 2026-08-28T23:51:56Z -- see Findings above._

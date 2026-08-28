---
slug: restructure-zfs-so-ordinary-temp-and-cache-data-is
created: 2026-08-28
status: todo
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
- [ ] D1 land `boot.tmp.useTmpfs` (agreed, not yet written)
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

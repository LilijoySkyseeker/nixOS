# Backups and ZFS snapshots

How snapshots are taken and replicated across `homelab`, `torrent`, and
`thinkpad`, and the zrepl behaviours that are easy to get wrong. For the
offsite restic path see the last section; for deployment status see
`TODO.md`.

## Three independent paths

1. **Offsite: restic → Backblaze B2 via rclone.** Inline in
   `hosts/homelab/configuration.nix`. Weekly, from a mounted ZFS snapshot.
   Independent of everything below.
2. **Local replication on homelab**: its own datasets → `zbackup`, over
   zrepl's in-process `local` transport.
3. **Remote replication**: `torrent`/`thinkpad` → `zbackup`, over SSH.
   homelab pulls; the sources are passive.

Paths 2 and 3 are both zrepl, configured by the single shared module
`modules/nixos/zrepl.nix` (`myZrepl`), registered `"zrepl"` and listed for
all three hosts in `modules/flake/hosts.nix`. It replaced sanoid + syncoid
and the old `modules/nixos/backup-push.nix`.

## The module's roles

One module covers every role, so a host declares datasets and a role rather
than hand-written YAML:

| Role | zrepl job | Used by |
|---|---|---|
| `myZrepl.snap` | `snap` | all three — local snapshotting + local prune ceiling |
| `myZrepl.serve` | `source` | torrent, thinkpad — passive, answers pulls |
| `myZrepl.pull.remotes.<name>` | `pull` | homelab — one job per remote |
| `myZrepl.local` | `source` + `pull` pair | homelab — same-host replication |
| `myZrepl.push.targets.<name>` | `push` | nobody currently; per-host opt-in |
| `myZrepl.sink` | `sink` | nobody currently; only needed to receive pushes |

Transport is pluggable (`myZrepl.defaultTransport`, currently
`ssh+stdinserver`; `tcp`, `tls`, and `local` are also wired). Retention is
three shared presets under `myZrepl.retention`, so changing a window
changes every host at once.

## Why pull, not push

zrepl's receiving endpoint exposes `DestroySnapshots` to any authenticated
client, bounded only to that client's own subtree
(`internal/endpoint/endpoint.go`). And `keep_receiver` is evaluated by the
pruner on the **active** side (`internal/daemon/pruner/pruner.go`) — so
under push, the retention policy for homelab's copy would live in a config
file on the source host.

Net effect: a compromised torrent could delete its own backup history.
Under pull, homelab dials out, the sources only answer, and retention
authority stays on homelab.

Use `myZrepl.push` only where pull genuinely loses coverage — a machine
whose online windows a 15m puller would miss. It has a real cost beyond the
above; see "push is welded to its snapshotter" below.

## Retention

| Preset | Grid | Snapshots | Window | Applies to |
|---|---|---|---|---|
| `source` | `1x1h(keep=all) \| 48x1h \| 7x1d` | ~67 | ~9 days | snapshots on the host that owns the data, pruned by homelab's pull job |
| `ceiling` | `1x1h(keep=all) \| 48x1h \| 30x1d` | ~90 | ~32 days | enforced on-box by each host's own `snap` job |
| `archive` | `168x1h \| 30x1d \| 12x30d` | ~210 | ~13 months | every copy in `zbackup` |

Snapshot interval is a uniform **5m** on all three hosts
(`myZrepl.snapshot.interval`). Replication runs on its own schedule —
**15m** for every pull job, including homelab's local one. The two are
deliberately separate: snapshots are cheap and local, whereas each
replication run costs I/O on a pool sitting behind a contended USB link.

`ceiling` is deliberately slacker than `source` so that in normal running
the puller's stricter rules are what actually prune; the ceiling only takes
over once a peer has been unreachable long enough that the alternative is
unbounded growth.

## Layout on zbackup

zrepl extends `root_fs` with the **full source dataset path**
(`subroot.MapToLocal`), so the tree is deeper than syncoid's was:

```
zbackup/backup/homelab/zdata/storage/storage
zbackup/backup/homelab/zdata/storage/storage-bulk
zbackup/backup/homelab/zroot/local/state
zbackup/backup/torrent/zroot/local/{home,root}
zbackup/backup/thinkpad/zroot/local/{home,root}
```

`myHealthAlerts.backupStaleness` on homelab keys off these paths — update
both together.

**zrepl does not create `root_fs` itself.** It creates children beneath it,
but the container dataset must already exist or every pull for that remote
fails with `root_fs does not exist` and nothing else in the log explains
why. `zbackup/backup/{homelab,thinkpad,torrent}` are declared in
`hosts/homelab/disko.nix`, but disko only creates datasets when it formats
a disk — a `nixos-rebuild switch` on an already-installed host will not
add a missing one. Before deploying a new pull remote, check on homelab:

```
zfs list -o name zbackup/backup/homelab zbackup/backup/thinkpad zbackup/backup/torrent
```

and `zfs create -o mountpoint=none -o com.sun:auto-snapshot=false <name>`
for any that is missing.

## Gotchas

These each cost real investigation; none are obvious from the config.

- **A grid rule condemns foreign snapshots, it does not ignore them.**
  `KeepGrid` puts every snapshot failing its regex onto its *destroy* list
  (`internal/pruning/keep_grid.go`), and `PruneSnapshots` destroys anything
  **all** rules list (`internal/pruning/pruning.go`). Regex-scoping a grid
  to `^zrepl_` therefore does not protect other snapshots — it condemns
  them. Combined with the pruner treating everything older than the
  replication cursor as replicated, an unguarded config destroys every
  foreign snapshot on the first prune.
- **`myZrepl.protectRegexes` is what actually protects.** A `regex` keep
  rule keeps what it matches and only lists non-matches for destruction, so
  one matching rule is enough to hold a snapshot forever. Defaults to
  `^blank$` — the impermanence rollback point created once by disko's
  `postCreateHook`, which cannot be regenerated without reinstalling.
  thinkpad has one on both `zroot/local/root` and `zroot/local/home`, which
  are exactly the datasets it serves. `myZrepl.preserveLegacySnapshots`
  adds `^autosnap_` for the sanoid changeover; turn it off and clear the
  leftovers by hand once zrepl has its own history, since nothing ages them
  out while it is on.
- **Push replication is welded to its snapshotter.**
  `modePush.RunPeriodic` is just `snapper.Run`
  (`internal/daemon/job/active.go`) and `PushJob` has no `interval` field,
  so setting a push job to `snapshotting: manual` leaves it replicating
  only on `zrepl signal wakeup`. This is why homelab's local replication is
  a `source`+`pull` pair rather than `push`+`sink`, and why push jobs keep
  their own snapshotting while `serve`/`local-source` are set to manual.
- **`pull` does not append a client identity; `sink` does.**
  `PullJob.GetAppendClientIdentity()` returns false, so each pull job needs
  its own explicit `root_fs`. A single sink, by contrast, serves many
  clients and confines each to `root_fs/<identity>`.
- **A `snap` job has no replication cursor**, so `not_replicated` is inert
  there — zrepl substitutes `alwaysUpToDateReplicationCursorHistory`
  (`internal/daemon/job/snapjob.go`). The local ceiling can therefore
  destroy never-replicated snapshots after a long outage. Replication
  itself stays safe via holds and the cursor bookmark.
- **The receiver skips filesystems with no counterpart on the sender**
  (`SkipNoCorrespondenceOnSender`). This is why the old syncoid target
  paths on `zbackup` are not pruned by the new jobs.
- **`ssh+stdinserver` requires the SSH user to be root.** The stdinserver
  socket lives in the daemon's `RuntimeDirectory` at mode 0700 and
  go-netssh creates it with a bare `net.Listen("unix", …)` and no chmod, so
  only the owner can connect. A non-root user needs `Group` /
  `RuntimeDirectoryMode` / `UMask` overrides that also expose zrepl's
  *control* socket to that group. The forced command in `authorized_keys`
  is the real boundary instead: the key can run exactly
  `zrepl stdinserver <identity>` and the identity is fixed server-side, so
  a source host cannot claim to be a different one.
- **Receiving jobs must declare `recv.placeholder.encryption`.** Because
  `root_fs` is extended with the full source path, receiving
  `zroot/local/home` means zrepl first creates `zroot` and `zroot/local`
  on the receiver as *placeholders*. Creating one requires knowing what
  to do with the encryption property, and the config default is
  `unspecified` (`PlaceholderRecvOptions`, `internal/config/config.go`),
  which fails the receive with "placeholder filesystem encryption
  handling is unspecified in receiver config". Crucially `zrepl
  configcheck` accepts the file either way, so the build-time validation
  below cannot catch this — it only appears on a real receive. Valid
  values are `inherit` and `off`
  (`placeholdercreationencryptionproperty_enumer.go`);
  `myZrepl.placeholderEncryption` defaults to `off` because `zbackup` is
  not encrypted. This is covered by the `zrepl-replication` VM test.
- **The config is validated at build time.** zrepl parses with
  `UnmarshalStrict`, so a stray or misspelled key is a hard startup
  failure. `myZrepl.validateConfig` (default on) runs `zrepl configcheck`
  against the generated YAML during `nixos-rebuild build`, turning that
  into a build error rather than an activation failure on the target host.

## Testing a change to this subsystem

`tests/zrepl-replication.nix` (`nix build
.#checks.x86_64-linux.zrepl-replication`) boots a source and a puller with
real zpools and exercises a real replication. Reach for it whenever you
touch `modules/nixos/zrepl.nix` or a host's `myZrepl` block: several of
the gotchas above produce a config that `zrepl configcheck` happily
accepts, so a build proves nothing about them. See
`docs/procedures/vm-testing.md`.

## Behaviour when a host is offline

A source host that is off takes no snapshots and accumulates nothing;
homelab's pull job logs errors but the daemon stays running, so nothing
enters systemd's `failed` state. This is why staleness is measured by
snapshot age (`myHealthAlerts.backupStaleness`) rather than unit state.

On return, replication resumes **incrementally** — the replication cursor
bookmark survives, and `IncrementalPath` accepts a bookmark as the
incremental base. No full resend, which was the failure mode that stranded
the old syncoid push.

If a host is *running* while homelab is unreachable, it cannot be pruned by
the puller, which is what the on-box `ceiling` exists to bound: ~90
snapshots per dataset instead of roughly 8,600 a month at a 5m cadence.
Catch-up then replays every intermediate snapshot, so a long outage means a
long chain of send steps.

## SSH on the source hosts

Pull means homelab dials *into* `torrent` and `thinkpad`, which
consequently now run `sshd` — they did not before. Locked down in both host
configs: `openFirewall = false` with a
`networking.firewall.interfaces.tailscale0` rule so it is tailnet-only,
`PermitRootLogin = "forced-commands-only"`, and the zrepl forced command is
the only root key present. See `docs/hardening.md` and
`docs/procedures/remote-access.md`.

## Offsite restic path

Weekly (Fri 03:00) to Backblaze B2 via rclone, backing up
`zroot/local/state` and `zdata/storage/storage` — not `storage-bulk`, too
large to be worth the offsite cost — from mounted ZFS snapshots rather than
the live filesystem. It reads an explicit hardcoded dataset list and never
touches `zbackup`.

Uses rclone rather than restic's native S3/B2 support, which was unreliable
with this repo's systemd + CLI-wrapper setup. The rclone remote is named
`backblazeDaily` inside the `homelab_backblaze_rclone_config` sops secret
even though the job is weekly — a leftover from a rename; don't "fix" the
name without also updating the secret (see
`docs/procedures/secrets.md` — secrets are never edited directly).

Success is tracked by an `ExecStartPost` touching a marker file, watched by
`myHealthAlerts.staleMarkerFiles`, because a hung run never reaches
systemd's `failed` state.

## Restore

See `docs/procedures/backup-restore.md` for the restore paths out of both
`zbackup` and Backblaze. It is written from the mechanics and has not yet
been exercised against a deployed copy of the layout above — verify each
step's output as you go, and correct that doc once a real restore has been
done.
